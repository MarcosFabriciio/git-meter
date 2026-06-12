import Foundation
import Security

// MARK: - Keychain helper

private nonisolated enum Keychain {
    private nonisolated static let service = "com.marcosfabriciio.GitMeter"
    private nonisolated static let account = "github-pat"

    nonisolated static func read() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    nonisolated static func save(_ token: String) {
        // Delete-then-add: simplest idempotent upsert.
        delete()
        guard let data = token.data(using: .utf8) else { return }
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    nonisolated static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    nonisolated static func exists() -> Bool {
        read() != nil
    }
}

// MARK: - gh binary discovery

private nonisolated func ghBinaryPath() -> String? {
    let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    let fm = FileManager.default
    for path in candidates {
        if fm.isExecutableFile(atPath: path) { return path }
    }
    // Fallback: let env resolve it
    if fm.isExecutableFile(atPath: "/usr/bin/env") { return nil } // signals "use env"
    return nil
}

// MARK: - DefaultTokenProvider

/// Resolves tokens in order: Keychain PAT → gh CLI.
/// Caches the resolved token in memory; `invalidate()` clears the cache.
actor DefaultTokenProvider: TokenProviding {
    private var cachedToken: String?

    func token() async throws -> String {
        if let cached = cachedToken { return cached }
        let resolved = try await resolve()
        cachedToken = resolved
        return resolved
    }

    func invalidate() {
        cachedToken = nil
    }

    // MARK: Settings surface

    func setPAT(_ pat: String) {
        Keychain.save(pat)
        cachedToken = nil // force re-resolve from Keychain on next call
    }

    func clearPAT() {
        Keychain.delete()
        cachedToken = nil
    }

    /// Human-readable description of the active token source.
    /// Reads the cached state — does not trigger a new resolution.
    func sourceDescription() -> String {
        if Keychain.exists() { return "PAT do Keychain" }
        if let path = ghBinaryPath() { return "gh CLI (\(path))" }
        return "gh CLI (/usr/bin/env gh)"
    }

    // MARK: Private

    private func resolve() async throws -> String {
        if let pat = Keychain.read() { return pat }
        return try await tokenFromGHCLI()
    }

    private func tokenFromGHCLI() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // suppress stderr

            if let ghPath = ghBinaryPath() {
                process.executableURL = URL(fileURLWithPath: ghPath)
                process.arguments = ["auth", "token"]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["gh", "auth", "token"]
            }

            // terminationHandler MUST be set before run().
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard proc.terminationStatus == 0,
                      let raw = String(data: data, encoding: .utf8),
                      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    continuation.resume(throwing: FetchError.noToken)
                    return
                }
                let tokenValue = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: tokenValue)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FetchError.noToken)
            }
            // Never call waitUntilExit — terminationHandler fires asynchronously.
        }
    }
}
