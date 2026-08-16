//
//  ContentView.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import AppKit
import SwiftUI

enum MenuPanelLayout {
    static let width: CGFloat = 360
    static let maxListHeight: CGFloat = 360
    static let rowHeight: CGFloat = 52
    static let loadMoreHeight: CGFloat = 40
    static let loadMoreErrorHeight: CGFloat = 22

    static func listHeight(
        itemCount: Int,
        showsLoadMore: Bool,
        showsLoadMoreError: Bool
    ) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        var height = CGFloat(itemCount) * rowHeight
        if showsLoadMore {
            height += loadMoreHeight
        }
        if showsLoadMoreError {
            height += loadMoreErrorHeight
        }
        return min(height, maxListHeight)
    }
}

struct ContentView: View {
    @Environment(RuntimeData.self) private var runtimeData
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: MenuPanelLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            VisualEffectView(material: .menu, blendingMode: .withinWindow)
        }
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
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.headline)
                if let subtitleText {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            headerButton(systemName: "arrow.clockwise", help: "Refresh") {
                runtimeData.renewPullTask(interval: runtimeData.interval, force: true)
            }

            headerButton(systemName: "arrow.up.right", help: "Open in GitHub") {
                closeMenuWindowIfPossible()
                openURL(GitHubEndpoint.notificationsWeb)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings") {
                closeMenuWindowIfPossible()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var titleText: String {
        if !runtimeData.message.isEmpty && runtimeData.notifications.isEmpty {
            return "Error"
        }
        if runtimeData.notifications.isEmpty {
            return "All caught up"
        }
        if runtimeData.hasMoreNotifications {
            return "\(runtimeData.notifications.count)+ unread"
        }
        let count = runtimeData.notifications.count
        return count == 1 ? "1 unread" : "\(count) unread"
    }

    private var subtitleText: String? {
        guard runtimeData.message.isEmpty || !runtimeData.notifications.isEmpty else {
            return nil
        }
        guard let lastPull = runtimeData.lastPull else { return nil }
        return "Updated \(lastPull.formatted(.relative(presentation: .named)))"
    }

    private var errorStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(runtimeData.message)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry") {
                runtimeData.renewPullTask(interval: runtimeData.interval, force: true)
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if !runtimeData.message.isEmpty && runtimeData.notifications.isEmpty {
            errorStatus
        } else if runtimeData.notifications.isEmpty {
            Text("New notifications will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !runtimeData.message.isEmpty {
                    errorStatus
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(runtimeData.notifications) { thread in
                            NotificationRowView(
                                thread: thread,
                                details: runtimeData.subjectDetailsByThreadId[thread.id],
                                onOpen: { thread, url in
                                    closeMenuWindowIfPossible()
                                    openURL(runtimeData.urlForOpeningNotificationDetail(threadId: thread.id, baseURL: url))
                                    runtimeData.handleNotificationOpened(thread)
                                }
                            )
                        }

                        if runtimeData.isLoadingMoreNotifications {
                            HStack(spacing: 8) {
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
                            Text(runtimeData.loadMoreError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 6)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight)
            }
        }
    }

    private var listHeight: CGFloat {
        MenuPanelLayout.listHeight(
            itemCount: runtimeData.notifications.count,
            showsLoadMore: runtimeData.hasMoreNotifications || runtimeData.isLoadingMoreNotifications,
            showsLoadMoreError: !runtimeData.loadMoreError.isEmpty
        )
    }

    @ViewBuilder
    private func headerButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
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
        .environment(RuntimeData())
}
