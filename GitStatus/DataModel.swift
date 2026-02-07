//
//  DataModel.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import Foundation

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
                webPath = webPath.replacingOccurrences(of: "/pulls/", with: "/pull/")
                webPath = webPath.replacingOccurrences(of: "/commits/", with: "/commit/")
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

func fetchNotificationThreads(
    githubToken: String,
    page: Int = 1,
    perPage: Int = 50
) async -> ([GitHubNotificationThread], Bool, Bool, String) {
    AppLog.debug("Fetching notification threads")
    do {
        let api = GitHubAPIClient(token: githubToken)
        let (notifications, hasNext) = try await api.fetchNotifications(page: page, perPage: perPage)
        AppLog.debug("Fetched \(notifications.count) notification threads")
        return (notifications, true, hasNext, "")
    } catch let e as GitHubAPIClient.APIError {
        switch e {
        case .invalidResponse:
            AppLog.warning("GitHub API invalid response")
            return ([], false, false, "invalid response")
        case .httpError(let statusCode, let body):
            let preview = body.prefix(512)
            AppLog.warning("GitHub API HTTP \(statusCode), body: \(preview)")
            return ([], false, false, "bad request: \(statusCode), \(preview)")
        }
    } catch {
        AppLog.warning("GitHub API request failed (network/firewall?)")
        return ([], false, false, "cannot request, please check network or firewall")
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

    func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let started = Date()
#if DEBUG
        AppLog.debug("HTTP GET \(url.absoluteString)")
#endif
        let (data, response) = try await Self.session.data(for: makeRequest(url: url))
        guard let http = response as? HTTPURLResponse else {
            AppLog.warning("HTTP invalid response for \(url.absoluteString)")
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
#if DEBUG
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let preview = body.prefix(1024)
            AppLog.debug("HTTP \(http.statusCode) \(url.absoluteString) (\(ms)ms), body: \(preview)")
#endif
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

#if DEBUG
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.debug("HTTP 2xx \(url.absoluteString) (\(ms)ms)")
#endif

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
        return try decoder.decode(T.self, from: data)
    }

    func fetchNotifications() async throws -> [GitHubNotificationThread] {
        try await fetch(URL(string: "https://api.github.com/notifications")!)
    }

    private func linkHeaderHasNextPage(_ linkHeader: String?) -> Bool {
        guard let linkHeader, !linkHeader.isEmpty else { return false }
        // Format: <url>; rel="next", <url>; rel="last"
        return linkHeader.split(separator: ",").contains { part in
            part.contains("rel=\"next\"")
        }
    }

    func fetchNotifications(page: Int, perPage: Int) async throws -> ([GitHubNotificationThread], Bool) {
        var components = URLComponents(string: "https://api.github.com/notifications")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), 50))),
        ]
        let url = components.url!

        let started = Date()
 #if DEBUG
        AppLog.debug("HTTP GET \(url.absoluteString)")
 #endif
        let (data, response) = try await Self.session.data(for: makeRequest(url: url))
        guard let http = response as? HTTPURLResponse else {
            AppLog.warning("HTTP invalid response for \(url.absoluteString)")
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
 #if DEBUG
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let preview = body.prefix(1024)
            AppLog.debug("HTTP \(http.statusCode) \(url.absoluteString) (\(ms)ms), body: \(preview)")
 #endif
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

 #if DEBUG
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.debug("HTTP 2xx \(url.absoluteString) (\(ms)ms)")
 #endif

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
        let threads = try decoder.decode([GitHubNotificationThread].self, from: data)
        let hasNext = linkHeaderHasNextPage(http.value(forHTTPHeaderField: "Link"))
        return (threads, hasNext)
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

@MainActor class RuntimeData: ObservableObject {
    static let shared = RuntimeData()
    @Published var message: String = ""
    @Published var notifications: [GitHubNotificationThread] = []
    @Published var subjectDetailsByThreadId: [String: GitHubSubjectDetails] = [:]

    @Published private(set) var isLoadingMoreNotifications: Bool = false
    @Published private(set) var hasMoreNotifications: Bool = false
    @Published private(set) var loadMoreError: String = ""

    @Published var listLength: Int = 10 {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "listLength")
        }
        didSet(oldValue) {
            if listLength == oldValue { return }
            resetPaginationState()
            renewPullTask(interval: interval)
        }
    }

    @Published var interval: Int  = 300 {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "interval")
        }
        didSet(oldValue) {
            if self.interval == oldValue {
                return
            }
            renewPullTask(interval: self.interval)
        }
    }
    
    private var pullTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var tokenDebounceTask: Task<Void, Never>?
    @Published var lastPull: Date?

    private var nextNotificationsPage: Int? = nil
    
    @Published var githubToken: String {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "githubToken")
        }
        didSet {
            tokenDebounceTask?.cancel()
            let interval = self.interval
            tokenDebounceTask = Task(priority: .utility) { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.renewPullTask(interval: interval)
            }
        }
    }
    
    init() {
        let defaults = UserDefaults.standard
        self.interval = (defaults.object(forKey: "interval") as? Int) ?? 300
        self.listLength = (defaults.object(forKey: "listLength") as? Int) ?? 10
        self.githubToken = defaults.string(forKey: "githubToken") ?? ""

        if self.interval < 30 { self.interval = 300 }
        if self.interval > 3600 { self.interval = 3600 }
        if self.listLength < 1 { self.listLength = 10 }
        if self.listLength > 50 { self.listLength = 50 }

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
    
    func renewPullTask(interval: Int) {
        AppLog.info("Renew pull task (interval=\(interval)s)")
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
        
        let token = self.githubToken
        let perPage = notificationsPerPage
        pullTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var failsCount = 0
            repeat {
                AppLog.debug("Pull notifications (fails=\(failsCount))")
                let (firstPage, ok, hasNext, err) = await fetchNotificationThreads(
                    githubToken: token,
                    page: 1,
                    perPage: perPage
                )

                if !ok {
                    AppLog.warning("Pull notifications failed: \(err)")
                }

                await MainActor.run {
                    self.notifications = firstPage
                    self.message = err
                    self.lastPull = Date()

                    self.nextNotificationsPage = hasNext ? 2 : nil
                    self.hasMoreNotifications = self.nextNotificationsPage != nil
                    self.isLoadingMoreNotifications = false
                    self.loadMoreError = ""

                    let ids = Set(firstPage.map { $0.id })
                    self.subjectDetailsByThreadId = self.subjectDetailsByThreadId.filter { ids.contains($0.key) }
                }
                
                if ok {
                    failsCount = 0
                } else {
                    failsCount += 1
                }

                if Task.isCancelled || failsCount >= 3 {
                    AppLog.debug("Stopping pull task (cancelled=\(Task.isCancelled), fails=\(failsCount))")
                    return
                }
                
                try? await Task.sleep(for: .seconds(interval))
            } while(!Task.isCancelled)
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

        loadMoreTask = Task.detached(priority: .utility) { [token, perPage, page] in
            let (threads, ok, hasNext, err) = await fetchNotificationThreads(
                githubToken: token,
                page: page,
                perPage: perPage
            )

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.loadMoreTask = nil }

                // Ignore stale results when pagination state changed.
                guard self.nextNotificationsPage == page else {
                    self.isLoadingMoreNotifications = false
                    return
                }

                self.isLoadingMoreNotifications = false

                guard ok else {
                    self.loadMoreError = err
                    return
                }

                var seen = Set(self.notifications.map { $0.id })
                var merged = self.notifications
                for t in threads {
                    guard !seen.contains(t.id) else { continue }
                    seen.insert(t.id)
                    merged.append(t)
                }
                self.notifications = merged

                self.nextNotificationsPage = hasNext ? (page + 1) : nil
                self.hasMoreNotifications = self.nextNotificationsPage != nil

                let ids = Set(merged.map { $0.id })
                self.subjectDetailsByThreadId = self.subjectDetailsByThreadId.filter { ids.contains($0.key) }
            }
        }
    }

    func prefetchSubjectDetails(for threads: [GitHubNotificationThread]) {
        self.detailsTask?.cancel()

        let token = self.githubToken
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

        self.detailsTask = Task.detached(priority: .utility) { [weak self] in
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
                    if let details {
                        await MainActor.run {
                            self.subjectDetailsByThreadId[id] = details
                        }
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
    
    func testGithubToken() async -> (Bool, String) {
        let token = self.githubToken
        let (_, ok, _, err) = await fetchNotificationThreads(
            githubToken: token,
            page: 1,
            perPage: 1
        )
        return (ok, err)
    }
}
