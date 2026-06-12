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

// MARK: - TokenStatus

/// The actual token source as verified at runtime.
enum TokenStatus: Sendable {
    /// A Personal Access Token is stored in the Keychain.
    case pat
    /// gh CLI resolved and returned a token; path is the binary that was used.
    case ghAuthenticated(String)
    /// No token is available from any source.
    case none
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

    /// Honest async check of the actual token source.
    /// Attempts real resolution — never returns an optimistic guess.
    func tokenStatus() async -> TokenStatus {
        if Keychain.exists() { return .pat }
        do {
            let t = try await tokenFromGHCLI()
            guard !t.isEmpty else { return .none }
            return .ghAuthenticated(ghBinaryPath() ?? "gh")
        } catch {
            return .none
        }
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
                // GUI apps inherit a minimal PATH that excludes Homebrew.
                // Augment it so /usr/bin/env can find a Homebrew-installed gh.
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["gh", "auth", "token"]
                process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
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
