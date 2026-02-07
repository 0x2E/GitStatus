//
//  ContentView.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var runtimeData: RuntimeData
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
     
    var body: some View {
        ZStack {
            VisualEffectView(material: .menu, blendingMode: .withinWindow)

            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                content
            }
            .padding(12)
        }
        .frame(width: 420)
        .task(id: prefetchKey) {
            guard runtimeData.message.isEmpty else { return }
            guard !runtimeData.notifications.isEmpty else { return }
            runtimeData.prefetchSubjectDetails(for: runtimeData.notifications)
        }
    }

    private var prefetchKey: String {
        "\(runtimeData.notifications.count)-\(runtimeData.notifications.first?.id ?? "")-\(runtimeData.notifications.last?.id ?? "")"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                runtimeData.renewPullTask(interval: runtimeData.interval)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .help("Refresh")

            Button {
                openURL(URL(string: "https://github.com/notifications")!)
            } label: {
                Image(systemName: "safari")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .help("Open in Browser")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .help("Quit")
            .keyboardShortcut("q")
        }
    }

    private var subtitle: String {
        if !runtimeData.message.isEmpty {
            return "Error"
        }
        if runtimeData.notifications.isEmpty {
            return "All caught up"
        }
        if runtimeData.hasMoreNotifications {
            return "Loaded \(runtimeData.notifications.count)+"
        }
        return "Loaded \(runtimeData.notifications.count)"
    }

    @ViewBuilder
    private var content: some View {
        if !runtimeData.message.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(runtimeData.message)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Retry") {
                    runtimeData.renewPullTask(interval: runtimeData.interval)
                }
                .buttonStyle(.link)
            }
        } else if runtimeData.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("All caught up")
                    .font(.headline)
                Text("New notifications will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(runtimeData.notifications) { thread in
                        NotificationRowView(
                            thread: thread,
                            details: runtimeData.subjectDetailsByThreadId[thread.id],
                            onOpen: { thread, url in
                                closeMenuWindowIfPossible()
                                openURL(runtimeData.urlForOpeningNotificationDetail(threadId: thread.id, baseURL: url))
                            }
                        )
                    }

                    if runtimeData.isLoadingMoreNotifications {
                        HStack(spacing: 10) {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if runtimeData.hasMoreNotifications {
                        HStack {
                            Spacer()
                            Button("Load more") {
                                runtimeData.loadMoreNotifications()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    if !runtimeData.loadMoreError.isEmpty {
                        HStack {
                            Spacer()
                            Text(runtimeData.loadMoreError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.bottom, 6)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 220, idealHeight: 360, maxHeight: 420)
        }
    }

    @MainActor
    private func closeMenuWindowIfPossible() {
        // MenuBarExtra(.window) windows may not support performClose, which can trigger a system beep.
        dismiss()
        NSApp.keyWindow?.orderOut(nil)
    }
}

#Preview {
    ContentView()
        .environmentObject(RuntimeData())
}
