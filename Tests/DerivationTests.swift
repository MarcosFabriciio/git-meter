import Testing
import Foundation

// MARK: - Factory

private let baseRepo = RepoConfig(owner: "acme", name: "example")
private let baseURL = URL(string: "https://github.com/acme/example/pull/1")!
private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

private func makePR(
    number: Int = 1,
    author: String = "alice",
    isDraft: Bool = false,
    updatedAt: Date = baseDate,
    reviewDecision: ReviewDecision? = nil,
    requestedUserLogins: [String] = [],
    requestedTeamSlugs: [String] = [],
    latestReviewByAuthor: [String: ReviewState] = [:],
    codeRabbitTouched: Bool = false,
    threadsTotal: Int = 0,
    threadsResolved: Int = 0,
    threadsUnresolved: Int = 0,
    additions: Int = 0,
    deletions: Int = 0,
    mergeableState: MergeableState = .unknown,
    ciState: CIState? = nil,
    headRefName: String = "feature/x"
) -> PullRequest {
    PullRequest(
        repo: baseRepo,
        number: number,
        title: "PR \(number)",
        url: URL(string: "https://github.com/acme/example/pull/\(number)")!,
        isDraft: isDraft,
        updatedAt: updatedAt,
        authorLogin: author,
        reviewDecision: reviewDecision,
        requestedUserLogins: requestedUserLogins,
        requestedTeamSlugs: requestedTeamSlugs,
        latestReviewByAuthor: latestReviewByAuthor,
        codeRabbitTouched: codeRabbitTouched,
        threadsTotal: threadsTotal,
        threadsResolvedFetched: threadsResolved,
        threadsUnresolvedFetched: threadsUnresolved,
        additions: additions,
        deletions: deletions,
        mergeableState: mergeableState,
        ciState: ciState,
        headRefName: headRefName
    )
}

// MARK: - Classification tests

@Test("Re-request after my approval → pendingMyReview (rule 2 beats rule 3)")
func reRequestAfterApproval() {
    let pr = makePR(
        author: "bob",
        requestedUserLogins: ["alice"],
        latestReviewByAuthor: ["alice": .approved]
    )
    #expect(classify(pr, viewer: "alice") == .pendingMyReview)
}

@Test("Draft PR with my review requested → .other (excluded from badge)")
func draftExcludedFromBadge() {
    let pr = makePR(author: "bob", isDraft: true, requestedUserLogins: ["alice"])
    #expect(classify(pr, viewer: "alice") == .other)
}

@Test("My own PR with my login also in requestedUserLogins → .mine (rule 1 short-circuits)")
func ownPRRuleOneShortCircuits() {
    let pr = makePR(author: "alice", requestedUserLogins: ["alice"])
    #expect(classify(pr, viewer: "alice") == .mine(.awaitingReview))
}

@Test("Team-only request (my login not in users) → .other")
func teamOnlyRequestNotPending() {
    let pr = makePR(author: "bob", requestedTeamSlugs: ["backend-team"])
    #expect(classify(pr, viewer: "alice") == .other)
}

@Test("My latest review DISMISSED, no re-request → .other")
func dismissedNoReRequest() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .dismissed])
    #expect(classify(pr, viewer: "alice") == .other)
}

@Test("My latest review COMMENTED only → .commentedByMe")
func commentedOnlyIsCommentedByMe() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .commented])
    #expect(classify(pr, viewer: "alice") == .commentedByMe)
}

@Test("My latest review PENDING (unsubmitted) → .other")
func pendingReviewNotHandled() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .pending])
    #expect(classify(pr, viewer: "alice") == .other)
}

@Test("My draft PR with changesRequested decision → .mine(.draft) and counts in mineDrafts only")
func myDraftWithChangesRequestedCountsAsDraft() {
    let pr = makePR(author: "alice", isDraft: true, reviewDecision: .changesRequested)
    #expect(classify(pr, viewer: "alice") == .mine(.draft))
    let summary = summarize([pr], viewer: "alice")
    #expect(summary.mineDrafts == 1)
    #expect(summary.mineChangesRequested == 0)
    #expect(summary.mineApproved == 0)
    #expect(summary.mineAwaiting == 0)
}

// MARK: - effectiveDecision tests

@Test("reviewDecision nil + other-user CHANGES_REQUESTED → effectiveDecision .changesRequested (coderabbitai/author ignored)")
func effectiveDecisionFallbackChangesRequested() {
    let pr = makePR(
        author: "alice",
        reviewDecision: nil,
        latestReviewByAuthor: [
            "alice": .approved,         // author — excluded
            "coderabbitai": .approved,  // bot — excluded
            "bob": .changesRequested    // counts
        ]
    )
    #expect(effectiveDecision(pr) == .changesRequested)
}

@Test("reviewDecision nil + only coderabbitai APPROVED → effectiveDecision nil (bot excluded)")
func effectiveDecisionCodeRabbitExcluded() {
    let pr = makePR(
        author: "alice",
        reviewDecision: nil,
        latestReviewByAuthor: ["coderabbitai": .approved]
    )
    #expect(effectiveDecision(pr) == nil)
}

// MARK: - classify: handledByMe variants

@Test("My changesRequested review → .handledByMe(.changesRequested)")
func handledByMeChangesRequested() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .changesRequested])
    #expect(classify(pr, viewer: "alice") == .handledByMe(.changesRequested))
}

@Test("My approved review → .handledByMe(.approved)")
func handledByMeApproved() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .approved])
    #expect(classify(pr, viewer: "alice") == .handledByMe(.approved))
}

// MARK: - effectiveDecision: reviewDecision non-null dominates contradictory reviews

@Test("reviewDecision non-null wins over contradictory latestReviews")
func effectiveDecisionNonNullDominates() {
    // reviewDecision says APPROVED; a reviewer left CHANGES_REQUESTED in latestReviews.
    // effectiveDecision must return .approved (non-null field wins).
    let pr = makePR(
        author: "alice",
        reviewDecision: .approved,
        latestReviewByAuthor: ["bob": .changesRequested]
    )
    #expect(effectiveDecision(pr) == .approved)
}

// MARK: - summarize invariants

@Test("summarize empty input → Summary.empty equivalence")
func summarizeEmptyInput() {
    let summary = summarize([], viewer: "alice")
    #expect(summary.pendingMyReview.isEmpty)
    #expect(summary.handledByMe.isEmpty)
    #expect(summary.mine.isEmpty)
    #expect(summary.badgeCount == 0)
    #expect(summary.mineApproved == 0)
    #expect(summary.mineChangesRequested == 0)
    #expect(summary.mineAwaiting == 0)
    #expect(summary.mineDrafts == 0)
}

@Test("summarize invariants: buckets disjoint; badgeCount == pendingMyReview.count; updatedAt desc")
func summarizeInvariants() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let t1 = Date(timeIntervalSince1970: 1_700_001_000)
    let t2 = Date(timeIntervalSince1970: 1_700_002_000)

    let prs: [PullRequest] = [
        // pending (older)
        makePR(number: 1, author: "bob", updatedAt: t0, requestedUserLogins: ["alice"]),
        // pending (newer)
        makePR(number: 2, author: "carol", updatedAt: t2, requestedUserLogins: ["alice"]),
        // handled by me — approved
        makePR(number: 3, author: "bob", updatedAt: t1, latestReviewByAuthor: ["alice": .approved]),
        // handled by me — changes requested
        makePR(number: 4, author: "carol", updatedAt: t0, latestReviewByAuthor: ["alice": .changesRequested]),
        // my PR awaiting
        makePR(number: 5, author: "alice", updatedAt: t2),
        // my PR approved
        makePR(number: 6, author: "alice", updatedAt: t1, reviewDecision: .approved),
        // my PR draft
        makePR(number: 7, author: "alice", isDraft: true, updatedAt: t0),
        // other
        makePR(number: 8, author: "bob", updatedAt: t1),
    ]

    let summary = summarize(prs, viewer: "alice")

    // disjoint: collect all IDs
    let allBucketIDs = (summary.pendingMyReview + summary.handledByMe + summary.mine).map(\.id)
    #expect(Set(allBucketIDs).count == allBucketIDs.count)

    // every non-other PR appears in exactly one bucket
    #expect(summary.pendingMyReview.count == 2)
    #expect(summary.handledByMe.count == 2)
    #expect(summary.mine.count == 3)

    // badge == pendingMyReview.count
    #expect(summary.badgeCount == summary.pendingMyReview.count)
    #expect(summary.badgeCount == 2)

    // mine counts
    #expect(summary.mineApproved == 1)
    #expect(summary.mineChangesRequested == 0)
    #expect(summary.mineAwaiting == 1)
    #expect(summary.mineDrafts == 1)

    // updatedAt desc within each section
    let pendingDates = summary.pendingMyReview.map(\.updatedAt)
    #expect(pendingDates == pendingDates.sorted(by: >))

    let handledDates = summary.handledByMe.map(\.updatedAt)
    #expect(handledDates == handledDates.sorted(by: >))

    let mineDates = summary.mine.map(\.updatedAt)
    #expect(mineDates == mineDates.sorted(by: >))
}

// MARK: - commentedByMe bucket tests

@Test("My latest review DISMISSED, no re-request → .other (unchanged)")
func dismissedStillOther() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .dismissed])
    #expect(classify(pr, viewer: "alice") == .other)
}

@Test("My latest review PENDING (unsubmitted) → .other (unchanged)")
func pendingStillOther() {
    let pr = makePR(author: "bob", latestReviewByAuthor: ["alice": .pending])
    #expect(classify(pr, viewer: "alice") == .other)
}

@Test("commentedByMe excluded from badgeCount")
func commentedByMeExcludedFromBadge() {
    let commented = makePR(number: 1, author: "bob", latestReviewByAuthor: ["alice": .commented])
    let pending   = makePR(number: 2, author: "carol", requestedUserLogins: ["alice"])
    let summary = summarize([commented, pending], viewer: "alice")
    #expect(summary.badgeCount == 1)
    #expect(summary.commentedByMe.count == 1)
    #expect(summary.pendingMyReview.count == 1)
}

@Test("summarize invariants extended: buckets disjoint including commentedByMe; exactly one bucket per PR")
func summarizeInvariantsWithCommentedByMe() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let t1 = Date(timeIntervalSince1970: 1_700_001_000)
    let t2 = Date(timeIntervalSince1970: 1_700_002_000)

    let prs: [PullRequest] = [
        // pending
        makePR(number: 1, author: "bob",   updatedAt: t0, requestedUserLogins: ["alice"]),
        // handled
        makePR(number: 2, author: "carol", updatedAt: t1, latestReviewByAuthor: ["alice": .approved]),
        // commented
        makePR(number: 3, author: "bob",   updatedAt: t2, latestReviewByAuthor: ["alice": .commented]),
        // mine
        makePR(number: 4, author: "alice", updatedAt: t1),
        // other
        makePR(number: 5, author: "dave",  updatedAt: t0),
    ]

    let summary = summarize(prs, viewer: "alice")

    let allBucketIDs = (summary.pendingMyReview + summary.handledByMe + summary.commentedByMe + summary.mine).map(\.id)
    #expect(Set(allBucketIDs).count == allBucketIDs.count, "buckets must be disjoint")

    #expect(summary.pendingMyReview.count == 1)
    #expect(summary.handledByMe.count == 1)
    #expect(summary.commentedByMe.count == 1)
    #expect(summary.mine.count == 1)
    // PR 5 is .other — not in any named bucket
    #expect(allBucketIDs.count == 4)

    // commented sorted updatedAt desc
    let commentedDates = summary.commentedByMe.map(\.updatedAt)
    #expect(commentedDates == commentedDates.sorted(by: >))
}
