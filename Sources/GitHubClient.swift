import Foundation

// GraphQL transport, response DTOs, domain mapper, token protocol, and fetch error types.

// MARK: - Top-level response envelope

nonisolated struct GitHubResponse: Decodable, Sendable {
    let data: ResponseData?
    let errors: [GraphQLError]?

    nonisolated struct ResponseData: Decodable, Sendable {
        let viewer: Viewer
        let rateLimit: RateLimit
        let repository: RepositoryPayload?
    }

    nonisolated struct GraphQLError: Decodable, Sendable {
        let message: String
        let type: String?
    }
}

// MARK: - Viewer

nonisolated struct Viewer: Decodable, Sendable {
    let login: String
}

// MARK: - RateLimit

nonisolated struct RateLimit: Decodable, Sendable {
    let cost: Int
    let remaining: Int
    let resetAt: String
}

// MARK: - Repository

nonisolated struct RepositoryPayload: Decodable, Sendable {
    let pullRequests: PullRequestConnection
}

nonisolated struct PullRequestConnection: Decodable, Sendable {
    let totalCount: Int
    let nodes: [PRNode]
}

// MARK: - PR node

nonisolated struct PRNode: Decodable, Sendable {
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let updatedAt: String
    let headRefName: String?
    let author: AuthorNode?
    let reviewDecision: String?
    let reviewRequests: ReviewRequestConnection
    let latestReviews: LatestReviewConnection
    let reviewThreads: ReviewThreadConnection
    let comments: CommentConnection
    let additions: Int
    let deletions: Int
    let mergeable: String
    let commits: CommitConnection
}

// MARK: - Commits (for statusCheckRollup)

nonisolated struct CommitConnection: Decodable, Sendable {
    let nodes: [CommitNode]
}

nonisolated struct CommitNode: Decodable, Sendable {
    let commit: CommitDetail
}

nonisolated struct CommitDetail: Decodable, Sendable {
    let statusCheckRollup: StatusCheckRollup?
}

nonisolated struct StatusCheckRollup: Decodable, Sendable {
    let state: String
}

// MARK: - Author

nonisolated struct AuthorNode: Decodable, Sendable {
    let login: String
}

// MARK: - Review requests

nonisolated struct ReviewRequestConnection: Decodable, Sendable {
    let totalCount: Int
    let nodes: [ReviewRequestNode]
}

nonisolated struct ReviewRequestNode: Decodable, Sendable {
    let requestedReviewer: RequestedReviewer?
}

/// Tolerant decode: captures __typename, and conditionally login/slug.
/// Unknown __typename values are preserved (login/slug will be nil).
nonisolated struct RequestedReviewer: Decodable, Sendable {
    let __typename: String
    let login: String?
    let slug: String?
}

// MARK: - Latest reviews

nonisolated struct LatestReviewConnection: Decodable, Sendable {
    let nodes: [LatestReviewNode]
}

nonisolated struct LatestReviewNode: Decodable, Sendable {
    let author: AuthorNode?
    let state: String
}

// MARK: - Review threads

nonisolated struct ReviewThreadConnection: Decodable, Sendable {
    let totalCount: Int
    let nodes: [ReviewThreadNode]
}

nonisolated struct ReviewThreadNode: Decodable, Sendable {
    let isResolved: Bool
}

// MARK: - Comments

nonisolated struct CommentConnection: Decodable, Sendable {
    let totalCount: Int
    let nodes: [CommentNode]
}

nonisolated struct CommentNode: Decodable, Sendable {
    let author: AuthorNode?
}

// MARK: - Fetch result

nonisolated struct RepoFetchResult: Sendable {
    let viewerLogin: String
    let prs: [PullRequest]
    let totalOpenCount: Int
    let rateRemaining: Int
}

// MARK: - Mapping

nonisolated enum GitHubMapper {
    private nonisolated static func parseDate(_ string: String) -> Date {
        // ISO8601DateFormatter is not Sendable — create per call.
        // For polling at 60s intervals this allocation is negligible.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: string) { return date }
        // Retry without fractional seconds (some GitHub fields omit them)
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string) ?? Date(timeIntervalSince1970: 0)
    }

    nonisolated static func map(response: GitHubResponse, repo: RepoConfig) throws -> RepoFetchResult {
        guard let data = response.data else {
            let messages = response.errors?.map(\.message).joined(separator: "; ") ?? "unknown"
            throw MappingError.graphQLErrors(messages)
        }

        guard let repoPayload = data.repository else {
            throw MappingError.repositoryNotFound(repo.id)
        }

        let viewerLogin = data.viewer.login
        let prs = repoPayload.pullRequests.nodes.compactMap { node -> PullRequest? in
            mapNode(node, repo: repo)
        }

        return RepoFetchResult(
            viewerLogin: viewerLogin,
            prs: prs,
            totalOpenCount: repoPayload.pullRequests.totalCount,
            rateRemaining: data.rateLimit.remaining
        )
    }

    private nonisolated static func mapNode(_ node: PRNode, repo: RepoConfig) -> PullRequest? {
        guard let url = URL(string: node.url) else { return nil }

        let authorLogin = node.author?.login ?? "ghost"

        // reviewDecision: tolerant — unknown strings → nil
        let reviewDecision = node.reviewDecision.flatMap { ReviewDecision(rawValue: $0) }

        // Review requests: User → login, Team → slug, unknown → skip
        var requestedUserLogins: [String] = []
        var requestedTeamSlugs: [String] = []
        for req in node.reviewRequests.nodes {
            guard let reviewer = req.requestedReviewer else { continue }
            switch reviewer.__typename {
            case "User":
                if let login = reviewer.login { requestedUserLogins.append(login) }
            case "Team":
                if let slug = reviewer.slug { requestedTeamSlugs.append(slug) }
            default:
                break // unknown typename — tolerate silently
            }
        }

        // latestReviewByAuthor: author null skipped; unknown state strings skipped
        var latestReviewByAuthor: [String: ReviewState] = [:]
        for review in node.latestReviews.nodes {
            guard let login = review.author?.login else { continue }
            guard let state = ReviewState(rawValue: review.state) else { continue }
            latestReviewByAuthor[login] = state
        }

        // codeRabbitTouched: "coderabbitai" in latestReviews OR in comments
        let codeRabbitInReviews = latestReviewByAuthor["coderabbitai"] != nil
        let codeRabbitInComments = node.comments.nodes.contains { $0.author?.login == "coderabbitai" }
        let codeRabbitTouched = codeRabbitInReviews || codeRabbitInComments

        // Thread counts
        let threadsResolved = node.reviewThreads.nodes.filter(\.isResolved).count
        let threadsUnresolved = node.reviewThreads.nodes.filter { !$0.isResolved }.count

        // mergeableState: tolerant — unknown raw strings → .unknown
        let mergeableState = MergeableState(rawValue: node.mergeable) ?? .unknown

        // ciState: derived from statusCheckRollup.state of the last commit
        let rollupState = node.commits.nodes.first?.commit.statusCheckRollup?.state
        let ciState: CIState? = rollupState.flatMap { raw in
            switch raw {
            case "SUCCESS":           return .success
            case "FAILURE", "ERROR":  return .failure
            case "PENDING", "EXPECTED": return .pending
            default:                  return nil
            }
        }

        return PullRequest(
            repo: repo,
            number: node.number,
            title: node.title,
            url: url,
            isDraft: node.isDraft,
            updatedAt: parseDate(node.updatedAt),
            authorLogin: authorLogin,
            reviewDecision: reviewDecision,
            requestedUserLogins: requestedUserLogins,
            requestedTeamSlugs: requestedTeamSlugs,
            latestReviewByAuthor: latestReviewByAuthor,
            codeRabbitTouched: codeRabbitTouched,
            threadsTotal: node.reviewThreads.totalCount,
            threadsResolvedFetched: threadsResolved,
            threadsUnresolvedFetched: threadsUnresolved,
            additions: node.additions,
            deletions: node.deletions,
            mergeableState: mergeableState,
            ciState: ciState,
            headRefName: node.headRefName ?? ""
        )
    }
}

// MARK: - Mapping errors

nonisolated enum MappingError: Error, Sendable {
    case graphQLErrors(String)
    case repositoryNotFound(String)
}

// MARK: - Token provider protocol

protocol TokenProviding: Sendable {
    func token() async throws -> String
    func invalidate() async
}

// MARK: - PR fetching protocol

protocol PRFetching: Sendable {
    func fetchRepo(_ repo: RepoConfig) async throws -> RepoFetchResult
}

// MARK: - Fetch errors

nonisolated enum FetchError: Error, Sendable {
    case noToken
    case unauthorized
    case repoNotFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case graphQL([String])
    case network(Error)
    case badResponse
}

// MARK: - GraphQL query

private nonisolated let repoPRsQuery = """
query RepoPRs($owner: String!, $name: String!) {
  viewer { login }
  rateLimit { cost remaining resetAt }
  repository(owner: $owner, name: $name) {
    pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      nodes {
        number title url isDraft updatedAt headRefName
        additions deletions mergeable
        author { login }
        reviewDecision
        reviewRequests(first: 10) { totalCount nodes { requestedReviewer { __typename ... on User { login } ... on Team { slug } } } }
        latestReviews(first: 20) { nodes { author { login } state } }
        reviewThreads(first: 100) { totalCount nodes { isResolved } }
        comments(first: 10) { totalCount nodes { author { login } } }
        commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      }
    }
  }
}
"""

// MARK: - GitHubClient

nonisolated struct GitHubClient: PRFetching {
    let tokenProvider: any TokenProviding
    nonisolated var session: URLSession = .shared

    nonisolated func fetchRepo(_ repo: RepoConfig) async throws -> RepoFetchResult {
        let tok: String
        do {
            tok = try await tokenProvider.token()
        } catch {
            throw FetchError.noToken
        }

        let body: [String: Any] = [
            "query": repoPRsQuery,
            "variables": ["owner": repo.owner, "name": repo.name]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GitMeter", forHTTPHeaderField: "User-Agent")
        request.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw FetchError.network(urlError)
        } catch {
            throw FetchError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FetchError.badResponse
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw FetchError.unauthorized
        case 403, 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After"))
                .flatMap { TimeInterval($0) }
            throw FetchError.rateLimited(retryAfter: retryAfter)
        default:
            throw FetchError.badResponse
        }

        let decoded = try JSONDecoder().decode(GitHubResponse.self, from: data)

        // GraphQL-level errors
        if let errors = decoded.errors, !errors.isEmpty {
            let isNotFound = errors.contains { err in
                err.type == "NOT_FOUND" ||
                err.message.lowercased().contains("could not resolve to a repository")
            }
            if isNotFound {
                throw FetchError.repoNotFound(repo.id)
            }
            throw FetchError.graphQL(errors.map(\.message))
        }

        // data.repository nil with no errors
        if decoded.data?.repository == nil {
            throw FetchError.repoNotFound(repo.id)
        }

        do {
            return try GitHubMapper.map(response: decoded, repo: repo)
        } catch let mappingErr as MappingError {
            switch mappingErr {
            case .repositoryNotFound(let id):
                throw FetchError.repoNotFound(id)
            case .graphQLErrors(let msg):
                throw FetchError.graphQL([msg])
            }
        }
    }
}
