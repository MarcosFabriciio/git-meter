import Testing
import Foundation

// MARK: - Helpers (local to DiffTests)

private let diffRepo = RepoConfig(owner: "acme", name: "example")
private let diffBase = Date(timeIntervalSince1970: 1_700_000_000)

private func diffPR(
    number: Int,
    author: String = "alice",
    isDraft: Bool = false,
    reviewDecision: ReviewDecision? = nil,
    requestedUserLogins: [String] = [],
    latestReviewByAuthor: [String: ReviewState] = [:]
) -> PullRequest {
    PullRequest(
        repo: diffRepo,
        number: number,
        title: "PR \(number)",
        url: URL(string: "https://github.com/acme/example/pull/\(number)")!,
        isDraft: isDraft,
        updatedAt: diffBase,
        authorLogin: author,
        reviewDecision: reviewDecision,
        requestedUserLogins: requestedUserLogins,
        requestedTeamSlugs: [],
        latestReviewByAuthor: latestReviewByAuthor,
        codeRabbitTouched: false,
        threadsTotal: 0,
        threadsResolvedFetched: 0,
        threadsUnresolvedFetched: 0,
        additions: 0,
        deletions: 0,
        mergeableState: .unknown,
        ciState: nil,
        headRefName: ""
    )
}

private func oldSnapshot(_ prs: [PullRequest]) -> [String: PullRequest] {
    Dictionary(uniqueKeysWithValues: prs.map { ($0.id, $0) })
}

// MARK: - Tests

@Test("old nil → no events (silent baseline)")
func oldNilNoEvents() {
    let pr = diffPR(number: 1, author: "bob", requestedUserLogins: ["alice"])
    let events = notificationEvents(old: nil, new: [pr], viewer: "alice")
    #expect(events.isEmpty)
}

@Test("absent → pendingMyReview → .reviewRequested fires")
func newPRPendingFiresReviewRequested() {
    let pr = diffPR(number: 1, author: "bob", requestedUserLogins: ["alice"])
    let events = notificationEvents(old: [:], new: [pr], viewer: "alice")
    #expect(events == [.reviewRequested(pr)])
}

@Test("pendingMyReview → pendingMyReview → no duplicate event")
func noDuplicateReviewRequested() {
    let pr = diffPR(number: 1, author: "bob", requestedUserLogins: ["alice"])
    let old = oldSnapshot([pr])
    let events = notificationEvents(old: old, new: [pr], viewer: "alice")
    #expect(events.isEmpty)
}

@Test("handledByMe → pendingMyReview (re-request) → .reviewRequested fires again")
func reRequestAfterHandledFiresAgain() {
    let handled = diffPR(number: 1, author: "bob", latestReviewByAuthor: ["alice": .approved])
    let rerequest = diffPR(number: 1, author: "bob", requestedUserLogins: ["alice"], latestReviewByAuthor: ["alice": .approved])
    let old = oldSnapshot([handled])
    let events = notificationEvents(old: old, new: [rerequest], viewer: "alice")
    #expect(events == [.reviewRequested(rerequest)])
}

@Test("mine awaiting → approved → .myPRApproved fires")
func mineAwaitingToApprovedFiresEvent() {
    let awaiting = diffPR(number: 2, author: "alice")
    let approved = diffPR(number: 2, author: "alice", reviewDecision: .approved)
    let old = oldSnapshot([awaiting])
    let events = notificationEvents(old: old, new: [approved], viewer: "alice")
    #expect(events == [.myPRApproved(approved)])
}

@Test("approved → approved → no event (no dup)")
func approvedToApprovedNoEvent() {
    let pr = diffPR(number: 2, author: "alice", reviewDecision: .approved)
    let old = oldSnapshot([pr])
    let events = notificationEvents(old: old, new: [pr], viewer: "alice")
    #expect(events.isEmpty)
}

@Test("mine awaiting → changesRequested → .myPRChangesRequested fires")
func mineAwaitingToChangesRequestedFiresEvent() {
    let awaiting = diffPR(number: 3, author: "alice")
    let changed = diffPR(number: 3, author: "alice", reviewDecision: .changesRequested)
    let old = oldSnapshot([awaiting])
    let events = notificationEvents(old: old, new: [changed], viewer: "alice")
    #expect(events == [.myPRChangesRequested(changed)])
}

@Test("PR disappears → no events")
func disappearedPRNoEvent() {
    let pr = diffPR(number: 99, author: "bob", requestedUserLogins: ["alice"])
    let old = oldSnapshot([pr])
    let events = notificationEvents(old: old, new: [], viewer: "alice")
    #expect(events.isEmpty)
}

@Test("mine approved → changesRequested → .myPRChangesRequested fires")
func mineApprovedToChangesRequestedFiresEvent() {
    let approved = diffPR(number: 4, author: "alice", reviewDecision: .approved)
    let changed = diffPR(number: 4, author: "alice", reviewDecision: .changesRequested)
    let old = oldSnapshot([approved])
    let events = notificationEvents(old: old, new: [changed], viewer: "alice")
    #expect(events == [.myPRChangesRequested(changed)])
}

@Test("mine changesRequested → approved → .myPRApproved fires")
func mineChangesRequestedToApprovedFiresEvent() {
    let changed = diffPR(number: 5, author: "alice", reviewDecision: .changesRequested)
    let approved = diffPR(number: 5, author: "alice", reviewDecision: .approved)
    let old = oldSnapshot([changed])
    let events = notificationEvents(old: old, new: [approved], viewer: "alice")
    #expect(events == [.myPRApproved(approved)])
}

@Test("commentedByMe → pendingMyReview (re-request) fires .reviewRequested")
func commentedByMeToRequestedFiresReviewRequested() {
    let commented  = diffPR(number: 20, author: "bob", latestReviewByAuthor: ["alice": .commented])
    let rerequest  = diffPR(number: 20, author: "bob", requestedUserLogins: ["alice"], latestReviewByAuthor: ["alice": .commented])
    let old = oldSnapshot([commented])
    let events = notificationEvents(old: old, new: [rerequest], viewer: "alice")
    #expect(events == [.reviewRequested(rerequest)])
}

@Test("absent → commentedByMe fires NO events (fresh comment, silent baseline for this PR)")
func newPRCommentedByMeFiresNothing() {
    let commented = diffPR(number: 21, author: "bob", latestReviewByAuthor: ["alice": .commented])
    let events = notificationEvents(old: [:], new: [commented], viewer: "alice")
    #expect(events.isEmpty)
}

@Test("notificationEvents ordering — multiple events emitted in PR number ascending order")
func notificationEventsAscendingOrder() {
    // Three new pending PRs appear simultaneously; events must come out lowest number first.
    let pr10 = diffPR(number: 10, author: "bob", requestedUserLogins: ["alice"])
    let pr3  = diffPR(number: 3,  author: "carol", requestedUserLogins: ["alice"])
    let pr7  = diffPR(number: 7,  author: "bob", requestedUserLogins: ["alice"])
    let events = notificationEvents(old: [:], new: [pr10, pr3, pr7], viewer: "alice")
    // All three should fire
    #expect(events.count == 3)
    // Numbers must be in ascending order
    let numbers = events.compactMap { event -> Int? in
        if case .reviewRequested(let pr) = event { return pr.number }
        return nil
    }
    #expect(numbers == [3, 7, 10])
}
