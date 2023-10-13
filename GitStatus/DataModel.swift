//
//  DataModel.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import Foundation

// https://docs.github.com/en/rest/activity/notifications?apiVersion=2022-11-28#list-notifications-for-the-authenticated-user
struct Notification: Identifiable, Codable, Observable {
    let id: String
    
    let repository: Repository
    struct Repository: Codable {
        let fullName: String
    }
    
    let subject: Subject
    struct Subject: Codable {
        let title: String
        let type: String
    }
    
    let reason: String
    let unread: Bool
}

@MainActor class RuntimeData: ObservableObject {
    @Published var message: String = ""
    @Published var notifications: [Notification] = []

    @Published var listLength: Int  = 10 {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "listLength")
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
            debugPrint("set interval: \(self.interval)")
        }
    }
    
    private var pullTask: Task = Task {}
    @Published var lastPull: Date?
    
    @Published var githubToken: String {
        willSet(newValue) {
            UserDefaults.standard.set(newValue, forKey: "githubToken")
        }
        didSet {
            if self.pullTask.isCancelled {
                renewPullTask(interval: self.interval)
            }
        }
    }
    
    init() {
        let defaults = UserDefaults.standard
        self.interval = defaults.integer(forKey: "interval")
        self.listLength = defaults.integer(forKey: "listLength")
        self.githubToken = defaults.string(forKey: "githubToken") ?? ""
    }
    
    // for swiftui
    func run() -> RuntimeData {
        renewPullTask(interval: self.interval)
        return self
    }
    
    func renewPullTask(interval: Int) {
        self.pullTask.cancel()
        
        if interval < 1 {
            self.message = "Interval is too short"
            return
        }
        
        if self.githubToken == "" {
            self.message = "Set GitHub token in settings first!"
            return
        }
        
        self.pullTask = Task {
            var failsCount = 0
            repeat {
                let (notifications, ok, err) = await pull(githubToken: self.githubToken)
                
                debugPrint(notifications)
                await MainActor.run {
                    self.notifications = notifications
                    self.message = err
                    self.lastPull = Date()
                }
                
                if ok {
                    failsCount = 0
                } else {
                    print(err)
                    failsCount += 1
                }
                
                if Task.isCancelled || failsCount >= 3 {
                    return
                }
                
                try? await Task.sleep(for: .seconds(interval))
            } while(!Task.isCancelled)
        }
    }
    
    func pull(githubToken: String) async -> ([Notification], Bool, String) {
        debugPrint("pulling")
        
        var errMsg = ""
        
        var request = URLRequest(url: URL(string: "https://api.github.com/notifications")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                        do {
                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            let notifications = try decoder.decode([Notification].self, from: data)
                            return (notifications, true, "")
                        } catch {
                            errMsg = "cannot parsing data"
                            print("cannot parsing data：\(error)")
                        }
                } else {
                    let err  = String(decoding: data, as: UTF8.self)
                    errMsg = "bad request: \(httpResponse.statusCode), \(err)"
                    print(err)
                }
            }
        } catch {
            errMsg = "cannot request, please check network or firewall"
            print("cannot request：\(error)")
        }
        return ([], false, errMsg)
    }
    
    func testGithubToken() async -> (Bool, String) {
        let (notifications, ok, err) = await pull(githubToken: self.githubToken)
        if ok {
            self.notifications = notifications
        }
        return (ok, err)
    }
}
