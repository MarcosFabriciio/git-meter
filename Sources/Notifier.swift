import Foundation
import UserNotifications
import AppKit

// MARK: - Notifier

@MainActor final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Setup

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    // MARK: - Post events

    func post(
        _ events: [NotificationEvent],
        notifyReviewRequested: Bool,
        notifyPRApproved: Bool,
        notifyPRChangesRequested: Bool
    ) {
        for event in events {
            switch event {
            case .reviewRequested(let pr):
                guard notifyReviewRequested else { continue }
                schedule(
                    identifier: pr.id,
                    title: "Nova review solicitada",
                    body: "#\(pr.number) \(pr.title) — \(pr.repo.name)",
                    urlString: pr.url.absoluteString
                )

            case .myPRApproved(let pr):
                guard notifyPRApproved else { continue }
                schedule(
                    identifier: pr.id,
                    title: "PR aprovada",
                    body: "Sua PR #\(pr.number) foi aprovada — \(pr.repo.name)",
                    urlString: pr.url.absoluteString
                )

            case .myPRChangesRequested(let pr):
                guard notifyPRChangesRequested else { continue }
                schedule(
                    identifier: pr.id,
                    title: "Mudanças solicitadas",
                    body: "Sua PR #\(pr.number) recebeu pedido de mudanças — \(pr.repo.name)",
                    urlString: pr.url.absoluteString
                )
            }
        }
    }

    // MARK: - Test notification

    func postTest() {
        schedule(
            identifier: "gitmeter.test",
            title: "Notificação de teste",
            body: "GitMeter está funcionando.",
            urlString: "https://github.com"
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Menu bar apps are always "active" — without this, banners are silently suppressed.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    // MARK: - Private

    private func schedule(identifier: String, title: String, body: String, urlString: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": urlString]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
