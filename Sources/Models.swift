import Foundation

// MARK: - RepoConfig

nonisolated struct RepoConfig: Codable, Hashable, Identifiable, Sendable {
    var owner: String
    var name: String

    var id: String { "\(owner)/\(name)" }

    static func parse(_ raw: String) -> RepoConfig? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[\w.\-]+/[\w.\-]+$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let parts = trimmed.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return RepoConfig(owner: String(parts[0]), name: String(parts[1]))
    }
}

// MARK: - Review types

nonisolated enum ReviewDecision: String, Codable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

nonisolated enum MergeableState: String, Codable, Sendable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

nonisolated enum CIState: String, Codable, Sendable {
    case success
    case failure
    case pending
}

nonisolated enum ReviewState: String, Codable, Sendable {
    case pending = "PENDING"
    case commented = "COMMENTED"
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case dismissed = "DISMISSED"
}

// MARK: - PullRequest

nonisolated struct PullRequest: Identifiable, Hashable, Codable, Sendable {
    let repo: RepoConfig
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let updatedAt: Date
    let authorLogin: String
    let reviewDecision: ReviewDecision?
    let requestedUserLogins: [String]
    let requestedTeamSlugs: [String]
    let latestReviewByAuthor: [String: ReviewState]
    let codeRabbitTouched: Bool
    let threadsTotal: Int
    let threadsResolvedFetched: Int
    let threadsUnresolvedFetched: Int
    let additions: Int
    let deletions: Int
    let mergeableState: MergeableState
    let ciState: CIState?
    let headRefName: String

    var threadsCapped: Bool { threadsTotal > threadsResolvedFetched + threadsUnresolvedFetched }
    var id: String { "\(repo.id)#\(number)" }
}

// MARK: - Bucket

nonisolated enum Bucket: Equatable, Sendable {
    case pendingMyReview
    case handledByMe(ReviewState)
    case mine(MineStatus)
    case commentedByMe
    case other

    nonisolated enum MineStatus: Equatable, Sendable {
        case draft, approved, changesRequested, awaitingReview
    }
}

// MARK: - Summary

nonisolated struct Summary: Equatable, Sendable {
    var pendingMyReview: [PullRequest]
    var handledByMe: [PullRequest]
    var commentedByMe: [PullRequest]
    var mine: [PullRequest]
    var mineApproved: Int
    var mineChangesRequested: Int
    var mineAwaiting: Int
    var mineDrafts: Int

    /// Badge reflects only PRs actively awaiting my review decision.
    /// Commented PRs are excluded: I already know what I said.
    var badgeCount: Int { pendingMyReview.count }

    static let empty = Summary(
        pendingMyReview: [],
        handledByMe: [],
        commentedByMe: [],
        mine: [],
        mineApproved: 0,
        mineChangesRequested: 0,
        mineAwaiting: 0,
        mineDrafts: 0
    )
}

// MARK: - NotificationEvent

nonisolated enum NotificationEvent: Equatable, Sendable {
    case reviewRequested(PullRequest)
    case myPRApproved(PullRequest)
    case myPRChangesRequested(PullRequest)
}
