import AppKit
import SwiftUI

func githubAvatarPixelSize(pointSize: CGFloat = 18, scale: CGFloat) -> Int {
    let safeScale = scale > 0 ? scale : 2
    let raw = Int((pointSize * safeScale).rounded(.up))
    return max(10, ((raw + 9) / 10) * 10)
}

func sizedGitHubAvatarURL(_ url: URL, pixelSize: Int) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var items = components?.queryItems ?? []
    if !items.contains(where: { $0.name == "s" }) {
        items.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components?.queryItems = items
    }
    return components?.url ?? url
}

enum NotificationTime {
    static func compact(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 {
            return "now"
        }
        if seconds < 3600 {
            return "\(max(1, Int(seconds / 60)))m"
        }
        if seconds < 86_400 {
            return "\(max(1, Int(seconds / 3600)))h"
        }
        if seconds < 86_400 * 7 {
            return "\(max(1, Int(seconds / 86_400)))d"
        }

        let timeZone = calendar.timeZone
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                    .month(.abbreviated)
                    .day()
            )
        }
        return date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .year()
                .month(.abbreviated)
                .day()
        )
    }
}

struct NotificationRowView: View {
    let thread: GitHubNotificationThread
    let details: GitHubSubjectDetails?
    let onOpen: (GitHubNotificationThread, URL) -> Void

    @State private var isHovering = false

    var body: some View {
        let url = details?.htmlUrl ?? thread.subject.preferredWebURL()

        Button {
            guard let url else { return }
            onOpen(thread, url)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: subjectTypeIconName(thread.subject.type))
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12))
                    .frame(width: 18, height: 16)
                    .padding(.top, 1)
                    .foregroundStyle(thread.unread ? .primary : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(thread.subject.title)
                            .font(.body)
                            .fontWeight(thread.unread ? .medium : .regular)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(NotificationTime.compact(thread.updatedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    }

                    HStack(spacing: 8) {
                        Text(thread.repository.fullName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        if !participants.isEmpty {
                            AvatarStackView(users: participants)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(thread.unread ? 1 : 0.65)
            .background {
                Color.primary.opacity(isHovering ? 0.08 : 0)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .background(HoverTrackingView(isHovering: $isHovering))
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var participants: [GitHubUser] {
        if let details, !details.participants.isEmpty {
            return Array(details.participants.prefix(5))
        }
        if let owner = thread.repository.owner {
            return [owner]
        }
        return []
    }

    private func subjectTypeIconName(_ type: String) -> String {
        switch type {
        case "PullRequest":
            return "arrow.triangle.branch"
        case "Issue":
            return "exclamationmark.circle"
        case "Commit":
            return "chevron.left.slash.chevron.right"
        case "Release":
            return "tag"
        case "Discussion":
            return "text.bubble"
        case "CheckSuite":
            return "checkmark.seal"
        case "RepositoryInvitation":
            return "person.crop.circle.badge.plus"
        default:
            return "bell"
        }
    }
}

struct AvatarStackView: View {
    let users: [GitHubUser]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(users) { user in
                AvatarImageView(url: user.avatarUrl, login: user.login)
            }
        }
    }
}

private struct AvatarImageView: View {
    let url: URL
    let login: String

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        AsyncImage(url: sizedGitHubAvatarURL(url, pixelSize: githubAvatarPixelSize(pointSize: 16, scale: displayScale))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(.circle)
        .overlay(
            Circle()
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        )
        .help(login)
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onHoverChanged = { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onHoverChanged = { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
        nsView.updateHoverState()
    }

    final class TrackingNSView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private var trackingAreaRef: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }

            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingAreaRef = area

            updateHoverState()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task { @MainActor in
                await Task.yield()
                updateHoverState()
            }
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onHoverChanged?(false)
        }

        func updateHoverState() {
            guard let window else { return }

            let mouseOnScreen = NSEvent.mouseLocation
            let mouseInWindow = window.convertPoint(fromScreen: mouseOnScreen)
            let mouseInView = convert(mouseInWindow, from: nil)
            onHoverChanged?(bounds.contains(mouseInView))
        }
    }
}
