import Testing
import Foundation

// Marker class used to locate the test bundle at runtime.
private final class BundleMarker {}

// MARK: - Fixture loader

private func loadSampleFixture() throws -> GitHubResponse {
    let bundle = Bundle(for: BundleMarker.self)
    guard let url = bundle.url(forResource: "sample", withExtension: "json") else {
        // Fallback: resolve relative to the source file for `swift test` / SPM-style layout
        let sourceFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = sourceFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(GitHubResponse.self, from: data)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(GitHubResponse.self, from: data)
}

// MARK: - Tests

@Test("fixture decodes without throwing")
func fixtureDecodesSuccessfully() throws {
    _ = try loadSampleFixture()
}

@Test("viewerLogin and rateRemaining map correctly")
func viewerAndRateLimit() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    #expect(result.viewerLogin == "alice")
    #expect(result.rateRemaining == 4850)
    #expect(result.totalOpenCount == 7)
    #expect(result.prs.count == 7)
}

@Test("PR 101: codeRabbitTouched via latestReviews; thread counts; user review request")
func pr101CodeRabbitViaReviews() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 101 })

    #expect(pr.codeRabbitTouched == true)
    #expect(pr.threadsTotal == 12)
    #expect(pr.threadsResolvedFetched == 8)
    #expect(pr.threadsUnresolvedFetched == 4)
    #expect(pr.threadsCapped == false)
    #expect(pr.requestedUserLogins.contains("alice"))
    #expect(pr.reviewDecision == .reviewRequired)
    #expect(pr.authorLogin == "bob")
}

@Test("PR 102: codeRabbitTouched via comments ONLY; reviewDecision nil derived from carol's changesRequested")
func pr102CodeRabbitViaComments() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 102 })

    #expect(pr.codeRabbitTouched == true)
    #expect(pr.reviewDecision == nil)
    #expect(effectiveDecision(pr) == .changesRequested)
    #expect(pr.threadsTotal == 3)
    #expect(pr.threadsResolvedFetched == 1)
    #expect(pr.threadsUnresolvedFetched == 2)
    #expect(pr.threadsCapped == false)
}

@Test("PR 103: no coderabbit; team slug captured; user login captured; threadsCapped true (total 120 > 4 fetched)")
func pr103TeamRequestAndCappedThreads() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 103 })

    #expect(pr.codeRabbitTouched == false)
    #expect(pr.requestedTeamSlugs.contains("backend-team"))
    #expect(pr.requestedUserLogins.contains("alice"))
    #expect(pr.threadsTotal == 120)
    #expect(pr.threadsCapped == true)
    #expect(pr.reviewDecision == .changesRequested)
}

@Test("PR 104: unknown __typename Mannequin tolerated; null requestedReviewer tolerated; author null → ghost; unknown review state skipped; null review author skipped")
func pr104ToleratedUnknownTypenameAndNulls() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 104 })

    #expect(pr.authorLogin == "ghost")
    #expect(pr.reviewDecision == nil)
    // Mannequin should be silently dropped from both user and team lists
    #expect(pr.requestedUserLogins.isEmpty)
    #expect(pr.requestedTeamSlugs.isEmpty)
    // null author in review → skipped; unknown state "UNKNOWNSTATE" → skipped
    #expect(pr.latestReviewByAuthor.isEmpty)
    #expect(pr.codeRabbitTouched == false)
}

@Test("PR 106: isDraft flag; reviewDecision APPROVED maps to enum; alice in latestReviewByAuthor")
func pr106DraftAndApproved() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 106 })

    #expect(pr.isDraft == true)
    #expect(pr.reviewDecision == .approved)
    #expect(pr.latestReviewByAuthor["alice"] == .approved)
}

@Test("ISO8601 updatedAt with fractional seconds decodes to non-epoch date")
func iso8601FractionalSecondsDecodes() throws {
    // parseDate tries .withFractionalSeconds first; verify that path returns a real date
    // (not the epoch fallback) when the string contains milliseconds.
    let json = """
    {
      "data": {
        "viewer": { "login": "alice" },
        "rateLimit": { "cost": 1, "remaining": 5000, "resetAt": "2026-06-11T12:00:00Z" },
        "repository": {
          "pullRequests": {
            "totalCount": 1,
            "nodes": [
              {
                "number": 201,
                "title": "fractional seconds test",
                "url": "https://github.com/acme/example/pull/201",
                "isDraft": false,
                "updatedAt": "2026-06-11T08:30:00.123Z",
                "author": { "login": "bob" },
                "reviewDecision": null,
                "additions": 0,
                "deletions": 0,
                "mergeable": "MERGEABLE",
                "reviewRequests": { "totalCount": 0, "nodes": [] },
                "latestReviews": { "nodes": [] },
                "reviewThreads": { "totalCount": 0, "nodes": [] },
                "comments": { "totalCount": 0, "nodes": [] },
                "commits": { "nodes": [] }
              }
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(GitHubResponse.self, from: json)
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 201 })
    // Epoch fallback is Date(timeIntervalSince1970: 0); a real 2026 date is >> epoch
    #expect(pr.updatedAt > Date(timeIntervalSince1970: 1_000_000_000))
}

@Test("reviewDecision unknown string → nil (tolerant decode)")
func reviewDecisionUnknownStringToleratedAsNil() throws {
    let json = """
    {
      "data": {
        "viewer": { "login": "alice" },
        "rateLimit": { "cost": 1, "remaining": 5000, "resetAt": "2026-06-11T12:00:00Z" },
        "repository": {
          "pullRequests": {
            "totalCount": 1,
            "nodes": [
              {
                "number": 202,
                "title": "unknown reviewDecision",
                "url": "https://github.com/acme/example/pull/202",
                "isDraft": false,
                "updatedAt": "2026-06-11T08:00:00Z",
                "author": { "login": "bob" },
                "reviewDecision": "SOME_FUTURE_VALUE",
                "additions": 0,
                "deletions": 0,
                "mergeable": "MERGEABLE",
                "reviewRequests": { "totalCount": 0, "nodes": [] },
                "latestReviews": { "nodes": [] },
                "reviewThreads": { "totalCount": 0, "nodes": [] },
                "comments": { "totalCount": 0, "nodes": [] },
                "commits": { "nodes": [] }
              }
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(GitHubResponse.self, from: json)
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 202 })
    #expect(pr.reviewDecision == nil)
}

@Test("threadsCapped false when totalCount exactly matches fetched resolved + unresolved")
func threadsCappedFalseWhenExactMatch() {
    // threadsCapped = threadsTotal > threadsResolvedFetched + threadsUnresolvedFetched
    // When equal they must NOT be capped.
    let repo = RepoConfig(owner: "acme", name: "example")
    let pr = PullRequest(
        repo: repo,
        number: 301,
        title: "exact match",
        url: URL(string: "https://github.com/acme/example/pull/301")!,
        isDraft: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        authorLogin: "bob",
        reviewDecision: nil,
        requestedUserLogins: [],
        requestedTeamSlugs: [],
        latestReviewByAuthor: [:],
        codeRabbitTouched: false,
        threadsTotal: 6,
        threadsResolvedFetched: 4,
        threadsUnresolvedFetched: 2,
        additions: 0,
        deletions: 0,
        mergeableState: .unknown,
        ciState: nil,
        headRefName: ""
    )
    #expect(pr.threadsCapped == false)
}

@Test("error envelope with null data throws MappingError.graphQLErrors")
func errorEnvelopeThrows() throws {
    let json = """
    {
      "data": null,
      "errors": [{ "message": "Not Found", "type": "NOT_FOUND" }]
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(GitHubResponse.self, from: json)
    do {
        _ = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
        Issue.record("Expected MappingError.graphQLErrors to be thrown")
    } catch MappingError.graphQLErrors {
        // expected
    }
}

@Test("PR 101: additions/deletions/mergeableState/ciState mapped correctly (SUCCESS, MERGEABLE)")
func pr101NewFields() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 101 })

    #expect(pr.additions == 42)
    #expect(pr.deletions == 7)
    #expect(pr.mergeableState == .mergeable)
    #expect(pr.ciState == .success)
}

@Test("PR 102: CONFLICTING mergeableState; FAILURE ciState")
func pr102ConflictingAndFailure() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 102 })

    #expect(pr.mergeableState == .conflicting)
    #expect(pr.ciState == .failure)
    #expect(pr.additions == 120)
    #expect(pr.deletions == 55)
}

@Test("PR 103: ERROR rollup state maps to CIState.failure")
func pr103ErrorRollupMapsToFailure() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 103 })

    #expect(pr.ciState == .failure)
    #expect(pr.mergeableState == .unknown)
}

@Test("PR 104: empty commits → ciState nil; unknown mergeable string → .unknown")
func pr104EmptyCommitsAndUnknownMergeable() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 104 })

    #expect(pr.ciState == nil)
    #expect(pr.mergeableState == .unknown)
    #expect(pr.additions == 0)
    #expect(pr.deletions == 0)
}

@Test("PR 105: PENDING rollup → CIState.pending")
func pr105PendingCIState() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 105 })

    #expect(pr.ciState == .pending)
    #expect(pr.mergeableState == .mergeable)
}

@Test("PR 106: null statusCheckRollup → ciState nil")
func pr106NullRollupMapsToNilCIState() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 106 })

    #expect(pr.ciState == nil)
    #expect(pr.additions == 0)
    #expect(pr.deletions == 0)
}

@Test("headRefName: PR 101 decodes to branch name; PR 104 null → empty string")
func headRefNameDecoding() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))

    let pr101 = try #require(result.prs.first { $0.number == 101 })
    #expect(pr101.headRefName == "feature/coderabbit-reviews")

    // PR 104 has headRefName: null in fixture → must map to ""
    let pr104 = try #require(result.prs.first { $0.number == 104 })
    #expect(pr104.headRefName == "")
}

@Test("PR 107: alice COMMENTED latest review → latestReviewByAuthor[alice] == .commented; headRefName absent → empty string")
func pr107AliceCommentedAndMissingBranch() throws {
    let response = try loadSampleFixture()
    let result = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
    let pr = try #require(result.prs.first { $0.number == 107 })

    #expect(pr.latestReviewByAuthor["alice"] == .commented)
    #expect(pr.authorLogin == "carol")
    // headRefName absent from JSON node → default "" via DTO optional + mapper
    #expect(pr.headRefName == "")
}

@Test("null repository throws MappingError.repositoryNotFound")
func nullRepositoryThrows() throws {
    let json = """
    {
      "data": {
        "viewer": { "login": "alice" },
        "rateLimit": { "cost": 1, "remaining": 5000, "resetAt": "2026-06-11T12:00:00Z" },
        "repository": null
      }
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(GitHubResponse.self, from: json)
    do {
        _ = try GitHubMapper.map(response: response, repo: RepoConfig(owner: "acme", name: "example"))
        Issue.record("Expected MappingError.repositoryNotFound to be thrown")
    } catch MappingError.repositoryNotFound {
        // expected
    }
}
