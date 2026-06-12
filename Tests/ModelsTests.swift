import Testing
import Foundation

// MARK: - RepoConfig.parse

@Test("RepoConfig.parse valid 'owner/repo' → parses owner and name")
func parseValidOwnerRepo() {
    let config = RepoConfig.parse("alice/my-repo")
    #expect(config?.owner == "alice")
    #expect(config?.name == "my-repo")
}

@Test("RepoConfig.parse leading/trailing whitespace → trimmed and valid")
func parseTrimsWhitespace() {
    let config = RepoConfig.parse("  alice/my-repo  ")
    #expect(config?.owner == "alice")
    #expect(config?.name == "my-repo")
}

@Test("RepoConfig.parse no slash → nil")
func parseNoSlash() {
    #expect(RepoConfig.parse("owneronly") == nil)
}

@Test("RepoConfig.parse empty string → nil")
func parseEmptyString() {
    #expect(RepoConfig.parse("") == nil)
}

@Test("RepoConfig.parse empty owner part → nil")
func parseEmptyOwner() {
    #expect(RepoConfig.parse("/repo") == nil)
}

@Test("RepoConfig.parse empty repo part → nil")
func parseEmptyRepo() {
    #expect(RepoConfig.parse("owner/") == nil)
}

@Test("RepoConfig.parse three-segment 'a/b/c' → nil (extra slash in name)")
func parseExtraSlash() {
    // The regex '^[\w.\-]+/[\w.\-]+$' does not allow '/' in the repo name part.
    #expect(RepoConfig.parse("a/b/c") == nil)
}

@Test("RepoConfig.parse dots and hyphens are valid in both parts")
func parseDotsAndHyphens() {
    let config = RepoConfig.parse("my.org/cool-repo.js")
    #expect(config?.owner == "my.org")
    #expect(config?.name == "cool-repo.js")
}

@Test("RepoConfig.parse valid id matches owner/name pattern")
func parseIdMatchesComponents() {
    let config = RepoConfig.parse("acme/example")
    #expect(config?.id == "acme/example")
}
