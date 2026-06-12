import Foundation
import AppKit
import Observation
import OSLog

private nonisolated let logger = Logger(subsystem: "com.marcosfabriciio.GitMeter", category: "store")

// MARK: - Snapshot persistence

private nonisolated struct SnapshotEnvelope: Codable {
    let savedAt: Date
    let prs: [String: PullRequest]
}

private nonisolated let snapshotURL: URL? = {
    guard let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first else { return nil }
    let dir = appSupport.appending(path: "com.marcosfabriciio.GitMeter", directoryHint: .isDirectory)
    return dir.appending(path: "snapshot.json")
}()

private nonisolated func saveSnapshot(_ prs: [String: PullRequest]) {
    guard let url = snapshotURL else { return }
    do {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let envelope = SnapshotEnvelope(savedAt: Date(), prs: prs)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: .atomic)
    } catch {
        logger.info("snapshot save failed: \(error.localizedDescription)")
    }
}

private nonisolated func loadSnapshot() -> [String: PullRequest]? {
    guard let url = snapshotURL,
          FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
        let age = Date().timeIntervalSince(envelope.savedAt)
        guard age < 48 * 3600 else {
            logger.info("snapshot too old (\(Int(age / 3600))h), discarding")
            return nil
        }
        logger.info("snapshot loaded: \(envelope.prs.count) PRs, age \(Int(age / 60))min")
        return envelope.prs
    } catch {
        logger.info("snapshot load failed: \(error.localizedDescription)")
        return nil
    }
}

// MARK: - PRStore

@Observable @MainActor final class PRStore {

    // MARK: Public state

    private(set) var summary: Summary = .empty
    private(set) var viewerLogin: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    /// repo id → pt-BR error message
    private(set) var repoErrors: [String: String] = [:]
    /// repo id → totalCount when server reports more PRs than the 50-node cap
    private(set) var cappedRepos: [String: Int] = [:]
    /// repo id → (codeRabbit-touched PRs, total PRs fetched)
    private(set) var codeRabbitStats: [String: CodeRabbitStat] = [:]

    struct CodeRabbitStat: Equatable {
        let touched: Int
        let total: Int
    }

    // MARK: Private state

    private var byRepo: [String: [PullRequest]] = [:]
    private var previousByID: [String: PullRequest]? = nil
    private var pollTask: Task<Void, Never>?
    private var currentDelay: TimeInterval

    // MARK: Dependencies

    private let fetcher: any PRFetching
    private let repos: @Sendable () -> [RepoConfig]
    private let interval: @Sendable () -> TimeInterval
    private let onEvents: @Sendable ([NotificationEvent]) -> Void
    private let invalidator: (@Sendable () async -> Void)?

    // MARK: Init

    init(
        fetcher: any PRFetching,
        repos: @escaping @Sendable () -> [RepoConfig],
        interval: @escaping @Sendable () -> TimeInterval,
        onEvents: @escaping @Sendable ([NotificationEvent]) -> Void = { _ in },
        invalidator: (@Sendable () async -> Void)? = nil
    ) {
        self.fetcher = fetcher
        self.repos = repos
        self.interval = interval
        self.onEvents = onEvents
        self.invalidator = invalidator
        self.currentDelay = interval()

        // Seed previousByID from last session so the first poll fires retroactive notifications.
        if let saved = loadSnapshot() {
            previousByID = saved
        }

        observeWakeNotification()
    }

    // MARK: Lifecycle

    func start() {
        cancelPollTask()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let delay = await self?.currentDelay ?? 60
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        cancelPollTask()
    }

    /// Cancels the running poll loop and immediately starts a new one (refresh fires first).
    func refreshNow() {
        start()
    }

    func settingsChanged() {
        currentDelay = interval()
        start()
    }

    // MARK: Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let repoList = repos()
        guard !repoList.isEmpty else {
            summary = .empty
            return
        }

        // First pass: fetch all repos in parallel
        var outcomes = await fetchAll(repos: repoList, fetcher: fetcher)

        // If any repo returned .unauthorized and we have an invalidator, invalidate once + retry those repos
        let hasUnauthorized = outcomes.values.contains { outcome in
            if case .failure(let e) = outcome, let fe = e as? FetchError, case .unauthorized = fe {
                return true
            }
            return false
        }

        if hasUnauthorized, let inv = invalidator {
            await inv()
            let unauthorizedRepos = repoList.filter { repo in
                if let outcome = outcomes[repo.id],
                   case .failure(let e) = outcome,
                   let fe = e as? FetchError,
                   case .unauthorized = fe {
                    return true
                }
                return false
            }
            let retried = await fetchAll(repos: unauthorizedRepos, fetcher: fetcher)
            for (id, result) in retried { outcomes[id] = result }
        }

        // Aggregate results
        var newByRepo: [String: [PullRequest]] = [:]
        var newErrors: [String: String] = [:]
        var newCapped: [String: Int] = [:]
        var newCRStats: [String: CodeRabbitStat] = [:]
        var latestViewer: String? = viewerLogin
        var latestRateRemaining: Int = Int.max
        var anySuccess = false
        var allFailed = !repoList.isEmpty
        var rateLimitedDelay: TimeInterval? = nil

        for repo in repoList {
            guard let outcome = outcomes[repo.id] else { continue }
            switch outcome {
            case .success(let result):
                newByRepo[repo.id] = result.prs
                latestViewer = result.viewerLogin
                latestRateRemaining = min(latestRateRemaining, result.rateRemaining)
                anySuccess = true
                allFailed = false

                if result.totalOpenCount > result.prs.count {
                    newCapped[repo.id] = result.totalOpenCount
                }
                let crTouched = result.prs.filter(\.codeRabbitTouched).count
                newCRStats[repo.id] = CodeRabbitStat(touched: crTouched, total: result.prs.count)

            case .failure(let error):
                newByRepo[repo.id] = byRepo[repo.id] ?? []
                newErrors[repo.id] = ptBRMessage(for: error)

                if case .rateLimited(let retryAfter) = error as? FetchError,
                   let after = retryAfter {
                    rateLimitedDelay = max(after, rateLimitedDelay ?? 0)
                }
            }
        }

        // Apply state
        byRepo = newByRepo
        repoErrors = newErrors
        cappedRepos = newCapped
        codeRabbitStats = newCRStats
        if let viewer = latestViewer { viewerLogin = viewer }

        // Compute merged list in config order, then derive summary + events
        let merged = repoList.flatMap { newByRepo[$0.id] ?? [] }

        if let viewer = viewerLogin {
            summary = summarize(merged, viewer: viewer)
            let events = notificationEvents(old: previousByID, new: merged, viewer: viewer)
            let newByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
            previousByID = newByID
            if !events.isEmpty { onEvents(events) }
            Task.detached { saveSnapshot(newByID) }
        }

        if anySuccess { lastUpdated = .now }

        // Backoff
        if let rlDelay = rateLimitedDelay {
            currentDelay = max(rlDelay, currentDelay)
        } else if allFailed {
            currentDelay = min(currentDelay * 2, 600)
        } else {
            currentDelay = interval()
        }
        if latestRateRemaining < 500 {
            currentDelay = min(currentDelay * 2, 600)
        }

        logger.info("fetched \(merged.count) PRs, badge=\(self.summary.badgeCount), viewer=\(self.viewerLogin ?? "unknown")")
    }

    // MARK: Private helpers

    private func cancelPollTask() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func observeWakeNotification() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }

    /// Fetches a list of repos in parallel. Returns a dict of id → outcome.
    private nonisolated func fetchAll(
        repos: [RepoConfig],
        fetcher: any PRFetching
    ) async -> [String: FetchOutcome] {
        await withTaskGroup(of: (String, FetchOutcome).self) { group in
            for repo in repos {
                group.addTask {
                    do {
                        let result = try await fetcher.fetchRepo(repo)
                        return (repo.id, .success(result))
                    } catch {
                        return (repo.id, .failure(error))
                    }
                }
            }

            var results: [String: FetchOutcome] = [:]
            for await (id, outcome) in group {
                results[id] = outcome
            }
            return results
        }
    }
}

// MARK: - Outcome type

private nonisolated enum FetchOutcome: Sendable {
    case success(RepoFetchResult)
    case failure(Error)
}

// MARK: - Error messages (pt-BR)

private nonisolated func ptBRMessage(for error: Error) -> String {
    guard let fe = error as? FetchError else {
        return "Erro na API do GitHub"
    }
    switch fe {
    case .repoNotFound:   return "Repositório não encontrado"
    case .unauthorized:   return "Falha de autenticação"
    case .rateLimited:    return "Limite de requisições atingido"
    case .network:        return "Sem conexão"
    case .graphQL:        return "Erro na API do GitHub"
    case .noToken:        return "Sem token do GitHub — configure em Ajustes"
    case .badResponse:    return "Erro na API do GitHub"
    }
}
