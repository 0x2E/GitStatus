import AppKit
import SwiftUI

func sizedGitHubAvatarURL(_ url: URL, pixelSize: Int = 64) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var items = components?.queryItems ?? []
    if !items.contains(where: { $0.name == "s" }) {
        items.append(URLQueryItem(name: "s", value: String(pixelSize)))
        components?.queryItems = items
    }
    return components?.url ?? url
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ZStack {
                        Image(systemName: subjectTypeIconName(thread.subject.type))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 18)
                            .foregroundStyle(thread.unread ? .primary : .secondary)
                    }

                    Text(thread.repository.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(thread.subject.title)
                    .font(.body)
                    .fontWeight(thread.unread ? .semibold : .regular)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !participants.isEmpty {
                    AvatarStackView(users: participants)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isHovering {
                    VisualEffectView(material: .selection, blendingMode: .withinWindow)
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        .opacity(0.55)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
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
            ForEach(users.prefix(5)) { user in
                AvatarImageView(url: user.avatarUrl)
            }
        }
    }
}

private struct AvatarImageView: View {
    let url: URL

    var body: some View {
        AsyncImage(url: sizedGitHubAvatarURL(url)) { phase in
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
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
        )
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
