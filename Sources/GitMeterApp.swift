import SwiftUI
import AppKit

@main
struct GitMeterApp: App {
    private let settings: SettingsStore
    private let tokenProvider: DefaultTokenProvider
    private let notifier: Notifier
    @State private var store: PRStore

    init() {
        let s = SettingsStore()
        let provider = DefaultTokenProvider()
        let n = Notifier()

        let fetcher = GitHubClient(tokenProvider: provider)
        // Both PRStore and SettingsStore are @MainActor; the closures are always invoked
        // from PRStore's @MainActor context. MainActor.assumeIsolated is safe here and
        // suppresses the Swift 6 @Sendable closure warning.
        let prStore = PRStore(
            fetcher: fetcher,
            repos: { MainActor.assumeIsolated { s.repoConfigs } },
            interval: { MainActor.assumeIsolated { s.pollInterval } },
            onEvents: { [weak n] events in
                guard let notifier = n else { return }
                Task { @MainActor in
                    notifier.post(
                        events,
                        notifyReviewRequested: s.notifyReviewRequested,
                        notifyPRApproved: s.notifyPRApproved,
                        notifyPRChangesRequested: s.notifyPRChangesRequested
                    )
                }
            },
            invalidator: { await provider.invalidate() }
        )

        settings = s
        tokenProvider = provider
        notifier = n
        _store = State(initialValue: prStore)

        n.configure()
        n.requestAuthorizationIfNeeded()
        prStore.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store, repoCount: settings.repoConfigs.count)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: settings,
                tokenProvider: tokenProvider,
                store: store,
                notifier: notifier
            )
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let badge = store.summary.badgeCount
        let hasErrors = !store.repoErrors.isEmpty

        if hasErrors && badge == 0 {
            Image(systemName: "exclamationmark.triangle")
        } else if badge > 0 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.pull")
                Text("\(badge)")
                    .bold()
            }
        } else {
            Image(systemName: "arrow.triangle.pull")
        }
    }
}
