//
//  ContentView.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var runtimeData: RuntimeData
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        if runtimeData.lastPull != nil {
            Text("Updated \(formatDate(runtimeData.lastPull))")
        }
        
        if runtimeData.message != "" {
            Text(runtimeData.message)
        }
        else if runtimeData.notifications.count == 0 {
            Text("All caught up!")
        } else {
            ForEach(runtimeData.notifications.prefix(runtimeData.listLength)){ notification in
                Divider()
                VStack() {
                    Text(notification.subject.title)
                        .font(.headline)
                    Text("\(notification.repository.fullName) - \(notification.subject.type)")
                        .font(.subheadline)
                }
            }
        }
        
        Divider()
        
        Button("Force Retry") {
            runtimeData.renewPullTask(interval: runtimeData.interval)
        }
        Link(destination: URL(string: "https://github.com/notifications")!) {
            Text("View in Broswer")
        }

        Divider()

        // https://stackoverflow.com/questions/65355696/how-to-programatically-open-settings-preferences-window-in-a-macos-swiftui-app
        if #available(macOS 14.0, *) {
            SettingsLink(label: {
                Text("Settings")
            })
        } else {
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        Button("Source Code") {
            openURL(URL(string: "https://github.com/0x2E/GitStatus")!)
        }
        
        Divider()
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
    
    func formatDate(_ d: Date?) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
        
        if let timestamp = d {
            return dateFormatter.string(from: timestamp)
        } else {
            return "nil"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(RuntimeData())
}
