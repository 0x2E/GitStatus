import XCTest
@testable import GitStatus

final class GitStatusLogicTests: XCTestCase {
    func testParseISO8601Dates() {
        XCTAssertNotNil(GitHubDate.parse("2024-01-02T03:04:05Z"))
        XCTAssertNotNil(GitHubDate.parse("2024-01-02T03:04:05.123Z"))
        XCTAssertNil(GitHubDate.parse("not-a-date"))
    }

    func testPreferredWebURLConvertsCommonAPIPaths() {
        let pull = GitHubNotificationThread.Subject(
            title: "Fix bug",
            type: "PullRequest",
            url: URL(string: "https://api.github.com/repos/foo/bar/pulls/12")
        )
        XCTAssertEqual(pull.preferredWebURL()?.absoluteString, "https://github.com/foo/bar/pull/12")

        let commit = GitHubNotificationThread.Subject(
            title: "sha",
            type: "Commit",
            url: URL(string: "https://api.github.com/repos/foo/bar/commits/abc")
        )
        XCTAssertEqual(commit.preferredWebURL()?.absoluteString, "https://github.com/foo/bar/commit/abc")

        let issue = GitHubNotificationThread.Subject(
            title: "Issue",
            type: "Issue",
            url: URL(string: "https://api.github.com/repos/foo/bar/issues/3")
        )
        XCTAssertEqual(issue.preferredWebURL()?.absoluteString, "https://github.com/foo/bar/issues/3")
    }

    func testPreferredWebURLReturnsNilWithoutSubjectURL() {
        let subject = GitHubNotificationThread.Subject(
            title: "Missing",
            type: "Issue",
            url: nil
        )
        XCTAssertNil(subject.preferredWebURL())
    }

    func testNotificationReferrerIdMatchesGitHubFormat() {
        let expected = Data("018:NotificationThread138661096:123456789".utf8).base64EncodedString()
        XCTAssertEqual(
            GitHubNotificationReferrerId.value(threadId: "138661096", userId: 123456789),
            expected
        )
    }

    func testNotificationReferrerIdIsAppendedOnce() {
        let url = URL(string: "https://github.com/foo/bar/pull/1")!
        let once = GitHubNotificationReferrerId.appending(to: url, threadId: "1", userId: 2)
        let twice = GitHubNotificationReferrerId.appending(to: once, threadId: "1", userId: 2)

        XCTAssertTrue(once.absoluteString.contains("notification_referrer_id="))
        XCTAssertEqual(once, twice)
    }

    func testLinkHeaderDetectsNextPage() {
        XCTAssertTrue(GitHubLinkHeader.hasNextPage("<https://api.github.com/notifications?page=2>; rel=\"next\", <https://api.github.com/notifications?page=4>; rel=\"last\""))
        XCTAssertFalse(GitHubLinkHeader.hasNextPage("<https://api.github.com/notifications?page=1>; rel=\"prev\""))
        XCTAssertFalse(GitHubLinkHeader.hasNextPage(nil))
        XCTAssertFalse(GitHubLinkHeader.hasNextPage(""))
    }

    func testPollTimingUsesMinimumAndServerFloor() {
        XCTAssertEqual(PollTiming.successDelay(userInterval: 30, serverPollInterval: nil), 60)
        XCTAssertEqual(PollTiming.successDelay(userInterval: 120, serverPollInterval: nil), 120)
        XCTAssertEqual(PollTiming.successDelay(userInterval: 60, serverPollInterval: 90), 90)
    }

    func testPollTimingBackoffDoesNotStopRetrying() {
        XCTAssertEqual(PollTiming.retryDelay(failCount: 1, serverPollInterval: nil), 60)
        XCTAssertEqual(PollTiming.retryDelay(failCount: 2, serverPollInterval: nil), 120)
        XCTAssertEqual(PollTiming.retryDelay(failCount: 3, serverPollInterval: nil), 300)
        XCTAssertEqual(PollTiming.retryDelay(failCount: 8, serverPollInterval: 90), 300)
    }

    func testLocalDismissalFiltersPendingAndPrunesGoneIDs() {
        var dismissed: Set = ["gone", "pending"]
        let visible = LocalDismissal.visibleIDs(from: ["pending", "other"], dismissed: &dismissed)
        XCTAssertEqual(visible, ["other"])
        XCTAssertEqual(dismissed, ["pending"])
    }

    func testAvatarPixelSizeRoundsUpToMultipleOfTen() {
        XCTAssertEqual(githubAvatarPixelSize(pointSize: 18, scale: 2), 40)
        XCTAssertEqual(githubAvatarPixelSize(pointSize: 18, scale: 3), 60)
        XCTAssertEqual(githubAvatarPixelSize(pointSize: 18, scale: 1), 20)
        XCTAssertEqual(githubAvatarPixelSize(pointSize: 18, scale: 0), 40)
    }

    func testSizedAvatarURLAddsPixelSizeOnce() {
        let url = URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!
        let sized = sizedGitHubAvatarURL(url, pixelSize: 40)
        XCTAssertEqual(URLComponents(url: sized, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "s" })?.value, "40")

        let again = sizedGitHubAvatarURL(sized, pixelSize: 80)
        XCTAssertEqual(URLComponents(url: again, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "s" })?.value, "40")
    }

    func testCompactNotificationTimeUsesShortUnitsThenDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")
        let now = try XCTUnwrap(GitHubDate.parse("2026-02-07T12:00:00Z"))

        XCTAssertEqual(
            NotificationTime.compact(now.addingTimeInterval(-10), now: now, calendar: calendar, locale: locale),
            "now"
        )
        XCTAssertEqual(
            NotificationTime.compact(now.addingTimeInterval(30), now: now, calendar: calendar, locale: locale),
            "now"
        )
        XCTAssertEqual(
            NotificationTime.compact(now.addingTimeInterval(-120), now: now, calendar: calendar, locale: locale),
            "2m"
        )
        XCTAssertEqual(
            NotificationTime.compact(now.addingTimeInterval(-7200), now: now, calendar: calendar, locale: locale),
            "2h"
        )
        XCTAssertEqual(
            NotificationTime.compact(now.addingTimeInterval(-86_400 * 3), now: now, calendar: calendar, locale: locale),
            "3d"
        )
        XCTAssertEqual(
            NotificationTime.compact(
                try XCTUnwrap(GitHubDate.parse("2026-01-26T12:00:00Z")),
                now: now,
                calendar: calendar,
                locale: locale
            ),
            "Jan 26"
        )
        XCTAssertEqual(
            NotificationTime.compact(
                try XCTUnwrap(GitHubDate.parse("2025-01-26T12:00:00Z")),
                now: now,
                calendar: calendar,
                locale: locale
            ),
            "Jan 26, 2025"
        )
    }

    func testMenuPanelListHeightHugsThenCaps() {
        XCTAssertEqual(
            MenuPanelLayout.listHeight(itemCount: 0, showsLoadMore: false, showsLoadMoreError: false),
            0
        )
        XCTAssertEqual(
            MenuPanelLayout.listHeight(itemCount: 4, showsLoadMore: false, showsLoadMoreError: false),
            208
        )
        XCTAssertEqual(
            MenuPanelLayout.listHeight(itemCount: 4, showsLoadMore: true, showsLoadMoreError: false),
            248
        )
        XCTAssertEqual(
            MenuPanelLayout.listHeight(itemCount: 10, showsLoadMore: true, showsLoadMoreError: false),
            MenuPanelLayout.maxListHeight
        )
    }

    func testAPIErrorMessagesDoNotLeakResponseBodies() {
        XCTAssertEqual(GitHubAPIClient.APIError.invalidResponse.userMessage, "Invalid response from GitHub")
        XCTAssertEqual(GitHubAPIClient.APIError.httpError(statusCode: 401, body: "secret").userMessage, "Invalid GitHub token")
        XCTAssertEqual(GitHubAPIClient.APIError.httpError(statusCode: 403, body: "secret").userMessage, "Access denied or rate limited")
        XCTAssertEqual(GitHubAPIClient.APIError.httpError(statusCode: 500, body: "secret").userMessage, "GitHub API error (500)")
        XCTAssertFalse(GitHubAPIClient.APIError.httpError(statusCode: 500, body: "secret").userMessage.contains("secret"))
    }
}
