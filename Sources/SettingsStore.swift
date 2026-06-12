import Foundation
import Observation
import ServiceManagement

// MARK: - SettingsStore

@Observable @MainActor final class SettingsStore {

    // MARK: - Persistence keys

    private enum Key {
        static let repos = "repos"
        static let pollInterval = "pollInterval"
        static let notifyReviewRequested = "notifyReviewRequested"
        static let notifyPRApproved = "notifyPRApproved"
        static let notifyPRChangesRequested = "notifyPRChangesRequested"
    }

    // MARK: - Observed state

    private(set) var repoStrings: [String]
    var pollInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(pollInterval, forKey: Key.pollInterval)
        }
    }
    var notifyReviewRequested: Bool {
        didSet {
            UserDefaults.standard.set(notifyReviewRequested, forKey: Key.notifyReviewRequested)
        }
    }
    var notifyPRApproved: Bool {
        didSet {
            UserDefaults.standard.set(notifyPRApproved, forKey: Key.notifyPRApproved)
        }
    }
    var notifyPRChangesRequested: Bool {
        didSet {
            UserDefaults.standard.set(notifyPRChangesRequested, forKey: Key.notifyPRChangesRequested)
        }
    }

    // MARK: - Derived

    var repoConfigs: [RepoConfig] {
        repoStrings.compactMap { RepoConfig.parse($0) }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        repoStrings = defaults.stringArray(forKey: Key.repos) ?? []

        let stored = defaults.double(forKey: Key.pollInterval)
        pollInterval = stored > 0 ? stored : 60

        // Notification toggles default to true when not yet set (nil in UserDefaults).
        notifyReviewRequested = defaults.object(forKey: Key.notifyReviewRequested)
            .flatMap { $0 as? Bool } ?? true
        notifyPRApproved = defaults.object(forKey: Key.notifyPRApproved)
            .flatMap { $0 as? Bool } ?? true
        notifyPRChangesRequested = defaults.object(forKey: Key.notifyPRChangesRequested)
            .flatMap { $0 as? Bool } ?? true
    }

    // MARK: - Repo management

    /// Returns nil on success, or an error string describing why the repo was rejected.
    @discardableResult
    func addRepo(_ raw: String) -> String? {
        guard let config = RepoConfig.parse(raw) else {
            return "Formato inválido. Use owner/repositório."
        }
        let normalized = config.id.lowercased()
        guard !repoStrings.contains(where: { $0.lowercased() == normalized }) else {
            return "Repositório já adicionado."
        }
        repoStrings.append(config.id)
        persistRepos()
        return nil
    }

    func removeRepo(atOffsets offsets: IndexSet) {
        repoStrings.remove(atOffsets: offsets)
        persistRepos()
    }

    func removeRepo(_ id: String) {
        repoStrings.removeAll { $0.lowercased() == id.lowercased() }
        persistRepos()
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    /// True when the app bundle is located under /Applications.
    /// The SMAppService login item only works reliably when installed there.
    var isRunningFromApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    // MARK: - Private

    private func persistRepos() {
        UserDefaults.standard.set(repoStrings, forKey: Key.repos)
    }
}
