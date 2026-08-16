//
//  DataModel.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import Foundation
import Observation

// GitHub REST API: GET /notifications
// https://docs.github.com/en/rest/activity/notifications#list-notifications-for-the-authenticated-user

struct GitHubUser: Identifiable, Codable, Hashable {
    let id: Int64
    let login: String
    let avatarUrl: URL
}

struct GitHubRepository: Codable {
    let fullName: String
    let owner: GitHubUser?
}

struct GitHubNotificationThread: Identifiable, Codable {
    let id: String

    let repository: GitHubRepository

    let subject: Subject
    struct Subject: Codable {
        let title: String
        let type: String
        let url: URL?
        let latestCommentUrl: URL?
    }

    let reason: String
    let unread: Bool
    let updatedAt: Date
    let lastReadAt: Date?
    let url: URL
    let subscriptionUrl: URL?
}

extension GitHubNotificationThread.Subject {
    func preferredWebURL() -> URL? {
        guard let apiURL = url else { return nil }

        // Best-effort conversion for a few common API URLs.
        if apiURL.host == "api.github.com" {
            let parts = apiURL.pathComponents
            if parts.count >= 3, parts[1] == "repos" {
                let rest = parts.dropFirst(2).joined(separator: "/")
                var webPath = "/" + rest
                webPath = webPath.replacing("/pulls/", with: "/pull/")
                webPath = webPath.replacing("/commits/", with: "/commit/")
                return URL(string: "https://github.com" + webPath)
            }
        }

        return apiURL
    }
}

struct GitHubSubjectDetails: Equatable {
    let htmlUrl: URL?
    let participants: [GitHubUser]
}

enum GitHubNotificationReferrerId {
    private static let queryName = "notification_referrer_id"

    static func value(threadId: String, userId: Int64) -> String {
        // Matches GitHub's tracking format used when opening a notification thread from the inbox.
        // Example raw string: "018:NotificationThread138661096:123456789"
        let raw = "018:NotificationThread\(threadId):\(userId)"
        return Data(raw.utf8).base64EncodedString()
    }

    static func appending(to url: URL, threadId: String, userId: Int64) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var items = components.queryItems ?? []
        guard !items.contains(where: { $0.name == queryName }) else {
            return url
        }

        items.append(URLQueryItem(name: queryName, value: value(threadId: threadId, userId: userId)))
        components.queryItems = items
        return components.url ?? url
    }
}

enum GitHubEndpoint {
    static let notifications = URL(string: "https://api.github.com/notifications")!
    static let user = URL(string: "https://api.github.com/user")!
    static let notificationsWeb = URL(string: "https://github.com/notifications")!
}

enum GitHubLinkHeader {
    static func hasNextPage(_ linkHeader: String?) -> Bool {
        guard let linkHeader, !linkHeader.isEmpty else { return false }
        // Format: <url>; rel="next", <url>; rel="last"
        return linkHeader.split(separator: ",").contains { part in
            part.contains("rel=\"next\"")
        }
    }
}

enum PollTiming {
    static let minimumInterval = 60

    static func successDelay(userInterval: Int, serverPollInterval: Int?) -> Int {
        max(userInterval, serverPollInterval ?? 0, minimumInterval)
    }

    static func retryDelay(failCount: Int, serverPollInterval: Int?) -> Int {
        let backoff: Int
        switch failCount {
        case ...1:
            backoff = minimumInterval
        case 2:
            backoff = 120
        default:
            backoff = 300
        }
        return max(backoff, serverPollInterval ?? 0, minimumInterval)
    }
}

enum LocalDismissal {
    static func visibleIDs(from serverIDs: [String], dismissed: inout Set<String>) -> [String] {
        dismissed.formIntersection(Set(serverIDs))
        return serverIDs.filter { !dismissed.contains($0) }
    }
}

enum NotificationPullResult {
    case notModified(pollInterval: Int?)
    case updated(threads: [GitHubNotificationThread], hasNext: Bool, etag: String?, pollInterval: Int?)
    case failed(String, stopRetrying: Bool = false)
}

func pullNotificationThreads(
    githubToken: String,
    page: Int = 1,
    perPage: Int = 50,
    etag: String? = nil
) async -> NotificationPullResult {
    AppLog.debug("Fetching notification threads")
    do {
        let api = GitHubAPIClient(token: githubToken)
        switch try await api.fetchNotifications(page: page, perPage: perPage, etag: etag) {
        case .notModified(let pollInterval):
            AppLog.debug("Notification threads not modified")
            return .notModified(pollInterval: pollInterval)
        case .page(let threads, let hasNext, let newEtag, let pollInterval):
            AppLog.debug("Fetched \(threads.count) notification threads")
            return .updated(threads: threads, hasNext: hasNext, etag: newEtag, pollInterval: pollInterval)
        }
    } catch let e as GitHubAPIClient.APIError {
        switch e {
        case .invalidResponse:
            AppLog.warning("GitHub API invalid response")
        case .httpError(let statusCode, let body):
            let preview = body.prefix(512)
            AppLog.warning("GitHub API HTTP \(statusCode), body: \(preview)")
        }
        let stopRetrying: Bool
        if case .httpError(let statusCode, _) = e, statusCode == 401 {
            stopRetrying = true
        } else {
            stopRetrying = false
        }
        return .failed(e.userMessage, stopRetrying: stopRetrying)
    } catch {
        AppLog.warning("GitHub API request failed (network/firewall?)")
        return .failed("cannot request, please check network or firewall")
    }
}

enum GitHubDate {
    private static let withFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true).parseStrategy
    private static let withoutFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: false).parseStrategy

    static func parse(_ value: String) -> Date? {
        if let d = try? withFractional.parse(value) { return d }
        if let d = try? withoutFractional.parse(value) { return d }
        return nil
    }
}

struct GitHubAPIClient {
    enum APIError: Error {
        case invalidResponse
        case httpError(statusCode: Int, body: String)

        var userMessage: String {
            switch self {
            case .invalidResponse:
                return "Invalid response from GitHub"
            case .httpError(let statusCode, _):
                switch statusCode {
                case 401:
                    return "Invalid GitHub token"
                case 403:
                    return "Access denied or rate limited"
                case 404:
                    return "Not found"
                default:
                    return "GitHub API error (\(statusCode))"
                }
            }
        }
    }

    enum NotificationsFetch {
        case notModified(pollInterval: Int?)
        case page(threads: [GitHubNotificationThread], hasNext: Bool, etag: String?, pollInterval: Int?)
    }

    let token: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = GitHubDate.parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return decoder
    }()

    func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let started = Date()
#if DEBUG
        AppLog.debug("HTTP \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
#endif
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            AppLog.warning("HTTP invalid response for \(request.url?.absoluteString ?? "")")
            throw APIError.invalidResponse
        }

#if DEBUG
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if (200...299).contains(http.statusCode) || http.statusCode == 304 {
            AppLog.debug("HTTP \(http.statusCode) \(request.url?.absoluteString ?? "") (\(ms)ms)")
        } else {
            let preview = String(decoding: data, as: UTF8.self).prefix(1024)
            AppLog.debug("HTTP \(http.statusCode) \(request.url?.absoluteString ?? "") (\(ms)ms), body: \(preview)")
        }
#endif
        return (data, http)
    }

    private func throwIfUnsuccessful(_ data: Data, _ http: HTTPURLResponse) throws {
        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func pollInterval(from http: HTTPURLResponse) -> Int? {
        guard let raw = http.value(forHTTPHeaderField: "X-Poll-Interval"),
              let value = Int(raw),
              value > 0
        else {
            return nil
        }
        return value
    }

    func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, http) = try await perform(makeRequest(url: url))
        try throwIfUnsuccessful(data, http)
        return try Self.decoder.decode(T.self, from: data)
    }

    func fetchViewer() async throws -> GitHubUser {
        try await fetch(GitHubEndpoint.user)
    }

    func fetchNotifications(page: Int, perPage: Int, etag: String? = nil) async throws -> NotificationsFetch {
        var components = URLComponents(url: GitHubEndpoint.notifications, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), 50))),
        ]
        let url = components.url!

        var request = makeRequest(url: url)
        if page == 1, let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, http) = try await perform(request)
        let poll = pollInterval(from: http)

        if http.statusCode == 304 {
            return .notModified(pollInterval: poll)
        }

        try throwIfUnsuccessful(data, http)
        let threads = try Self.decoder.decode([GitHubNotificationThread].self, from: data)
        let hasNext = GitHubLinkHeader.hasNextPage(http.value(forHTTPHeaderField: "Link"))
        let newEtag = http.value(forHTTPHeaderField: "Etag") ?? http.value(forHTTPHeaderField: "ETag")
        return .page(threads: threads, hasNext: hasNext, etag: newEtag, pollInterval: poll)
    }

    func markThreadAsRead(_ url: URL) async throws {
        var request = makeRequest(url: url)
        request.httpMethod = "PATCH"
        let (data, http) = try await perform(request)
        if http.statusCode == 304 {
            return
        }
        try throwIfUnsuccessful(data, http)
    }

    func fetchSubjectDetails(subjectURL: URL) async -> GitHubSubjectDetails? {
        struct SubjectResource: Codable {
            let htmlUrl: URL?
            let user: GitHubUser?
            let assignees: [GitHubUser]?
            let requestedReviewers: [GitHubUser]?
            let author: GitHubUser?
            let committer: GitHubUser?
        }

        do {
            let res: SubjectResource = try await fetch(subjectURL)
            var seen: Set<Int64> = []
            var participants: [GitHubUser] = []

            func append(_ user: GitHubUser?) {
                guard let user else { return }
                guard !seen.contains(user.id) else { return }
                seen.insert(user.id)
                participants.append(user)
            }

            append(res.user)
            append(res.author)
            append(res.committer)
            for u in res.requestedReviewers ?? [] { append(u) }
            for u in res.assignees ?? [] { append(u) }
            return GitHubSubjectDetails(htmlUrl: res.htmlUrl, participants: participants)
        } catch {
#if DEBUG
            AppLog.debug("Subject details fetch failed: \(subjectURL.absoluteString)")
#endif
            return nil
        }
    }
}

@MainActor
@Observable
final class RuntimeData {
    static let shared = RuntimeData()

    var message: String = ""
    var notifications: [GitHubNotificationThread] = []
    var subjectDetailsByThreadId: [String: GitHubSubjectDetails] = [:]

    private(set) var viewerUserId: Int64?
    private(set) var isLoadingMoreNotifications: Bool = false
    private(set) var hasMoreNotifications: Bool = false
    private(set) var loadMoreError: String = ""
    private(set) var lastPull: Date?

    var listLength: Int = 10 {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "listLength")
        }
        didSet(oldValue) {
            if listLength == oldValue { return }
            notificationsETag = nil
            resetPaginationState()
            renewPullTask(interval: interval)
        }
    }

    var interval: Int = 300 {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "interval")
        }
        didSet(oldValue) {
            if interval == oldValue { return }
            renewPullTask(interval: interval)
        }
    }

    var githubToken: String {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "githubToken")
        }
        didSet {
            guard githubToken != oldValue else { return }
            viewerFetchTask?.cancel()
            viewerFetchTask = nil
            viewerUserId = nil
            notificationsETag = nil
            serverPollInterval = nil
            locallyDismissedThreadIds = []
            renewPullTask(interval: interval)
        }
    }

    @ObservationIgnored private var pullTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var viewerFetchTask: Task<Void, Never>?
    @ObservationIgnored private var nextNotificationsPage: Int?
    @ObservationIgnored private var notificationsETag: String?
    @ObservationIgnored private var serverPollInterval: Int?
    @ObservationIgnored private var locallyDismissedThreadIds: Set<String> = []

    init() {
        let defaults = UserDefaults.standard
        var storedInterval = (defaults.object(forKey: "interval") as? Int) ?? 300
        var storedListLength = (defaults.object(forKey: "listLength") as? Int) ?? 10
        self.githubToken = defaults.string(forKey: "githubToken") ?? ""

        if storedInterval < PollTiming.minimumInterval {
            storedInterval = PollTiming.minimumInterval
            defaults.set(storedInterval, forKey: "interval")
        } else if storedInterval > 3600 {
            storedInterval = 3600
            defaults.set(storedInterval, forKey: "interval")
        }
        if storedListLength < 1 || storedListLength > 50 {
            storedListLength = 10
            defaults.set(storedListLength, forKey: "listLength")
        }

        self.interval = storedInterval
        self.listLength = storedListLength
        resetPaginationState()
    }

    private var notificationsPerPage: Int {
        min(max(listLength, 1), 50)
    }

    private func resetPaginationState() {
        loadMoreTask?.cancel()
        loadMoreTask = nil
        nextNotificationsPage = nil
        hasMoreNotifications = false
        isLoadingMoreNotifications = false
        loadMoreError = ""
    }

    func start() {
        AppLog.info("RuntimeData start")
        renewPullTask(interval: interval)
    }

    func renewPullTask(interval: Int, force: Bool = false) {
        AppLog.info("Renew pull task (interval=\(interval)s, force=\(force))")
        if force {
            notificationsETag = nil
        }
        pullTask?.cancel()
        detailsTask?.cancel()
        loadMoreTask?.cancel()
        pullTask = nil
        detailsTask = nil
        loadMoreTask = nil

        if interval < 1 {
            self.message = "Interval is too short"
            AppLog.warning("Interval too short: \(interval)")
            return
        }

        if githubToken.isEmpty {
            self.message = "Set GitHub token in settings first!"
            AppLog.warning("GitHub token missing")
            return
        }

        let token = githubToken
        let perPage = notificationsPerPage
        let userInterval = max(interval, PollTiming.minimumInterval)

        ensureViewerUserId()
        pullTask = Task { [weak self] in
            guard let self else { return }
            var failsCount = 0
            while !Task.isCancelled {
                AppLog.debug("Pull notifications (fails=\(failsCount))")
                let result = await pullNotificationThreads(
                    githubToken: token,
                    page: 1,
                    perPage: perPage,
                    etag: self.notificationsETag
                )

                if Task.isCancelled { return }

                switch result {
                case .notModified(let pollInterval):
                    failsCount = 0
                    if let pollInterval {
                        self.serverPollInterval = pollInterval
                    }
                    self.message = ""
                    self.lastPull = Date()

                case .updated(let firstPage, let hasNext, let etag, let pollInterval):
                    failsCount = 0
                    if let pollInterval {
                        self.serverPollInterval = pollInterval
                    }
                    if let etag {
                        self.notificationsETag = etag
                    }
                    self.applyFetchedPage(firstPage, hasNext: hasNext)
                    self.message = ""
                    self.lastPull = Date()

                case .failed(let err, let stopRetrying):
                    failsCount += 1
                    AppLog.warning("Pull notifications failed: \(err)")
                    self.message = err
                    if stopRetrying {
                        AppLog.warning("Stopping pull task (non-retryable error)")
                        return
                    }
                }

                if Task.isCancelled { return }

                let sleepSeconds: Int
                if failsCount == 0 {
                    sleepSeconds = PollTiming.successDelay(
                        userInterval: userInterval,
                        serverPollInterval: self.serverPollInterval
                    )
                } else {
                    sleepSeconds = PollTiming.retryDelay(
                        failCount: failsCount,
                        serverPollInterval: self.serverPollInterval
                    )
                    AppLog.debug("Retrying pull in \(sleepSeconds)s (fails=\(failsCount))")
                }
                try? await Task.sleep(for: .seconds(sleepSeconds))
            }
        }
    }

    func loadMoreNotifications() {
        guard !isLoadingMoreNotifications else { return }
        guard loadMoreTask == nil else { return }
        guard let page = nextNotificationsPage else { return }

        let token = githubToken
        let perPage = notificationsPerPage

        isLoadingMoreNotifications = true
        loadMoreError = ""

        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            let result = await pullNotificationThreads(
                githubToken: token,
                page: page,
                perPage: perPage
            )

            defer { self.loadMoreTask = nil }
            guard !Task.isCancelled else { return }

            // Ignore stale results when pagination state changed.
            guard self.nextNotificationsPage == page else {
                self.isLoadingMoreNotifications = false
                return
            }

            self.isLoadingMoreNotifications = false

            switch result {
            case .notModified:
                self.hasMoreNotifications = false
                self.nextNotificationsPage = nil

            case .updated(let threads, let hasNext, _, _):
                var seen = Set(self.notifications.map(\.id))
                var merged = self.notifications
                for t in threads {
                    guard !seen.contains(t.id) else { continue }
                    guard !self.locallyDismissedThreadIds.contains(t.id) else { continue }
                    seen.insert(t.id)
                    merged.append(t)
                }
                self.notifications = merged
                self.nextNotificationsPage = hasNext ? (page + 1) : nil
                self.hasMoreNotifications = self.nextNotificationsPage != nil

                let ids = Set(merged.map(\.id))
                self.subjectDetailsByThreadId = self.subjectDetailsByThreadId.filter { ids.contains($0.key) }

            case .failed(let err, _):
                self.loadMoreError = err
            }
        }
    }

    func prefetchSubjectDetails(for threads: [GitHubNotificationThread]) {
        detailsTask?.cancel()

        let token = githubToken
        let targets = threads.compactMap { thread -> (String, URL)? in
            guard subjectDetailsByThreadId[thread.id] == nil else { return nil }
            guard let url = thread.subject.url else { return nil }
            return (thread.id, url)
        }

        guard !targets.isEmpty, !token.isEmpty else {
            return
        }

#if DEBUG
        AppLog.debug("Prefetch subject details: \(targets.count) targets")
#endif

        detailsTask = Task { [weak self] in
            guard let self else { return }
            let api = GitHubAPIClient(token: token)

            let maxInFlight = 4
            await withTaskGroup(of: (String, GitHubSubjectDetails?).self) { group in
                var it = targets.makeIterator()

                for _ in 0..<maxInFlight {
                    guard let (id, url) = it.next() else { break }
                    group.addTask {
                        let details = await api.fetchSubjectDetails(subjectURL: url)
                        return (id, details)
                    }
                }

                while let (id, details) = await group.next() {
                    if Task.isCancelled { return }
                    if let details {
                        self.subjectDetailsByThreadId[id] = details
                    }

                    if let (nextId, nextURL) = it.next() {
                        group.addTask {
                            let details = await api.fetchSubjectDetails(subjectURL: nextURL)
                            return (nextId, details)
                        }
                    }
                }
            }
        }
    }

    func handleNotificationOpened(_ thread: GitHubNotificationThread) {
        locallyDismissedThreadIds.insert(thread.id)
        notifications.removeAll { $0.id == thread.id }
        subjectDetailsByThreadId[thread.id] = nil

        let token = githubToken
        let threadURL = thread.url
        let threadId = thread.id
        Task { [weak self] in
            do {
                try await GitHubAPIClient(token: token).markThreadAsRead(threadURL)
            } catch {
                AppLog.warning("Mark thread \(threadId) as read failed")
                guard let self else { return }
                self.locallyDismissedThreadIds.remove(threadId)
                self.insertNotificationPreservingOrder(thread)
            }
        }
    }

    private func applyFetchedPage(_ firstPage: [GitHubNotificationThread], hasNext: Bool) {
        let visibleIDs = LocalDismissal.visibleIDs(
            from: firstPage.map(\.id),
            dismissed: &locallyDismissedThreadIds
        )
        let visible = Set(visibleIDs)
        notifications = firstPage.filter { visible.contains($0.id) }
        nextNotificationsPage = hasNext ? 2 : nil
        hasMoreNotifications = nextNotificationsPage != nil
        isLoadingMoreNotifications = false
        loadMoreError = ""

        let ids = Set(notifications.map(\.id))
        subjectDetailsByThreadId = subjectDetailsByThreadId.filter { ids.contains($0.key) }
    }

    private func insertNotificationPreservingOrder(_ thread: GitHubNotificationThread) {
        guard !notifications.contains(where: { $0.id == thread.id }) else { return }
        let index = notifications.firstIndex { $0.updatedAt < thread.updatedAt } ?? notifications.endIndex
        notifications.insert(thread, at: index)
    }

    func urlForOpeningNotificationDetail(threadId: String, baseURL: URL) -> URL {
        guard let viewerUserId else {
            ensureViewerUserId()
            return baseURL
        }
        return GitHubNotificationReferrerId.appending(to: baseURL, threadId: threadId, userId: viewerUserId)
    }

    private func ensureViewerUserId() {
        guard viewerUserId == nil else { return }
        guard viewerFetchTask == nil else { return }

        let token = githubToken
        guard !token.isEmpty else { return }

        viewerFetchTask = Task { [weak self] in
            defer { self?.viewerFetchTask = nil }
            do {
                let viewer = try await GitHubAPIClient(token: token).fetchViewer()
                guard !Task.isCancelled else { return }
                guard let self, self.githubToken == token else { return }
                self.viewerUserId = viewer.id
            } catch {
                // Best-effort only. The app still works without this value.
            }
        }
    }

    func testGithubToken(_ token: String? = nil) async -> (Bool, String) {
        let token = token ?? githubToken
        switch await pullNotificationThreads(githubToken: token, page: 1, perPage: 1) {
        case .notModified, .updated:
            return (true, "")
        case .failed(let err, _):
            return (false, err)
        }
    }
}
