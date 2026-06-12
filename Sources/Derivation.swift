import Foundation

// MARK: - effectiveDecision

/// Returns the review decision for a PR.
/// Prefers the server-provided `reviewDecision` field; falls back to deriving
/// from `latestReviewByAuthor`, excluding the PR author and "coderabbitai".
/// Precedence in the fallback: .changesRequested > .approved > nil.
nonisolated func effectiveDecision(_ pr: PullRequest) -> ReviewDecision? {
    if let decision = pr.reviewDecision { return decision }

    let relevantStates = pr.latestReviewByAuthor
        .filter { login, _ in login != pr.authorLogin && login != "coderabbitai" }
        .values

    if relevantStates.contains(.changesRequested) { return .changesRequested }
    if relevantStates.contains(.approved) { return .approved }
    return nil
}

// MARK: - classify

/// Classifies a PR relative to the viewer. First match wins.
nonisolated func classify(_ pr: PullRequest, viewer: String) -> Bucket {
    // Rule 1: viewer is the author
    if pr.authorLogin == viewer {
        switch effectiveDecision(pr) {
        case .approved:           return .mine(.approved)
        case .changesRequested:   return pr.isDraft ? .mine(.draft) : .mine(.changesRequested)
        default:                  return pr.isDraft ? .mine(.draft) : .mine(.awaitingReview)
        }
    }

    // Rule 2: viewer is directly requested — drafts are excluded from badge
    if pr.requestedUserLogins.contains(viewer) {
        return pr.isDraft ? .other : .pendingMyReview
    }

    // Rule 3: viewer already submitted an opinionated review
    if let state = pr.latestReviewByAuthor[viewer], state == .approved || state == .changesRequested {
        return .handledByMe(state)
    }

    // Rule 3.5: viewer left a comment-only review (no approval/rejection, no pending request)
    if pr.latestReviewByAuthor[viewer] == .commented {
        return .commentedByMe
    }

    // Rule 4: everything else (DISMISSED, PENDING, no review at all)
    return .other
}

// MARK: - summarize

/// Builds a Summary for a list of PRs viewed by `viewer`.
/// Each section is sorted by updatedAt descending (stable sort).
nonisolated func summarize(_ prs: [PullRequest], viewer: String) -> Summary {
    var pending: [PullRequest] = []
    var handled: [PullRequest] = []
    var commented: [PullRequest] = []
    var mine: [PullRequest] = []
    var mineApproved = 0
    var mineChangesRequested = 0
    var mineAwaiting = 0
    var mineDrafts = 0

    for pr in prs {
        switch classify(pr, viewer: viewer) {
        case .pendingMyReview:
            pending.append(pr)
        case .handledByMe:
            handled.append(pr)
        case .commentedByMe:
            commented.append(pr)
        case .mine(let status):
            mine.append(pr)
            switch status {
            case .approved:           mineApproved += 1
            case .changesRequested:   mineChangesRequested += 1
            case .awaitingReview:     mineAwaiting += 1
            case .draft:              mineDrafts += 1
            }
        case .other:
            break
        }
    }

    let desc: (PullRequest, PullRequest) -> Bool = { $0.updatedAt > $1.updatedAt }
    return Summary(
        pendingMyReview: pending.sorted(by: desc),
        handledByMe: handled.sorted(by: desc),
        commentedByMe: commented.sorted(by: desc),
        mine: mine.sorted(by: desc),
        mineApproved: mineApproved,
        mineChangesRequested: mineChangesRequested,
        mineAwaiting: mineAwaiting,
        mineDrafts: mineDrafts
    )
}

// MARK: - notificationEvents

/// Computes notification events by diffing old and new PR snapshots.
/// Returns [] when `old` is nil (first successful snapshot — silent baseline).
/// Order: by PR number ascending for determinism.
nonisolated func notificationEvents(
    old: [String: PullRequest]?,
    new: [PullRequest],
    viewer: String
) -> [NotificationEvent] {
    guard let old else { return [] }

    var events: [NotificationEvent] = []

    let sorted = new.sorted { $0.number < $1.number }
    for pr in sorted {
        let newBucket = classify(pr, viewer: viewer)
        let oldPR = old[pr.id]
        let oldBucket = oldPR.map { classify($0, viewer: viewer) }

        // Review newly requested
        if newBucket == .pendingMyReview, oldBucket != .pendingMyReview {
            events.append(.reviewRequested(pr))
        }

        // My PR transitions
        guard pr.authorLogin == viewer, let previousPR = oldPR else { continue }
        let prevDecision = effectiveDecision(previousPR)
        let newDecision = effectiveDecision(pr)

        if prevDecision != .approved, newDecision == .approved {
            events.append(.myPRApproved(pr))
        } else if prevDecision != .changesRequested, newDecision == .changesRequested {
            events.append(.myPRChangesRequested(pr))
        }
    }

    return events
}
