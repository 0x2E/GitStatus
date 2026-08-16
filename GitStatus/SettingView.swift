//
//  SettingView.swift
//  GitStatus
//

import AppKit
import ServiceManagement
import SwiftUI

private enum AppVersion {
    static func formatted(versionPrefix: String, buildPrefix: String) -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (v, b) {
        case let (v?, b?):
            return "\(versionPrefix)\(v) (\(b))"
        case let (v?, nil):
            return "\(versionPrefix)\(v)"
        case let (nil, b?):
            return "\(buildPrefix)\(b)"
        default:
            return ""
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case token
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .token: return "GitHub"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .token: return "key.horizontal"
        case .about: return "info.circle"
        }
    }
}

struct SettingView: View {
    @Environment(RuntimeData.self) private var runtimeData
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .withinWindow)

                VStack(alignment: .leading, spacing: 12) {
                    header

                    List(SettingsSection.allCases, selection: $selection) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ZStack {
                VisualEffectView(material: .contentBackground, blendingMode: .withinWindow)

                switch selection {
                case .general:
                    GeneralSettingsView()
                        .environment(runtimeData)
                case .token:
                    TokenSettingsView()
                        .environment(runtimeData)
                case .about:
                    AboutSettingsView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            SettingsAppIconView(size: 28, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text("GitStatus")
                    .font(.headline)
                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
    }

    private var versionString: String {
        AppVersion.formatted(versionPrefix: "v", buildPrefix: "Build ")
    }
}

private struct GeneralSettingsView: View {
    @Environment(RuntimeData.self) private var runtimeData
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var listLengthBinding: Binding<Int> {
        Binding(
            get: { runtimeData.listLength },
            set: { runtimeData.listLength = min(max($0, 1), 50) }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { runtimeData.interval },
            set: { runtimeData.interval = min(max($0, PollTiming.minimumInterval), 3600) }
        )
    }

    var body: some View {
        ScrollView {
            Form {
                Section {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)

                    LabeledContent("Items per page") {
                        HStack(spacing: 10) {
                            TextField("", value: listLengthBinding, format: .number)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                .textFieldStyle(.roundedBorder)
                                .help("How many notifications to fetch per page")

                            Stepper(value: listLengthBinding, in: 1...50, step: 1) {
                                EmptyView()
                            }
                            .labelsHidden()
                        }
                    }

                    LabeledContent("Refresh interval") {
                        HStack(spacing: 10) {
                            TextField("", value: intervalBinding, format: .number)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                .textFieldStyle(.roundedBorder)
                                .help("How often to refresh GitHub notifications")

                            Text("s")
                                .foregroundStyle(.secondary)

                            Stepper(value: intervalBinding, in: PollTiming.minimumInterval...3600, step: 30) {
                                EmptyView()
                            }
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("GitHub recommends polling at most once per minute. Unchanged inboxes can return 304 and do not count against the rate limit.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(20)
        }
        .navigationTitle("General")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    AppLog.warning("Launch at login failed: \(error.localizedDescription)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }
}

private struct TokenSettingsView: View {
    @Environment(RuntimeData.self) private var runtimeData
    @State private var tokenDraft = ""
    @State private var tokenChecking = false
    @State private var showTokenAlert = false
    @State private var tokenAlertTitle = ""
    @State private var tokenAlertContent = ""

    var body: some View {
        ScrollView {
            Form {
                Section {
                    SecureField("Personal access token", text: $tokenDraft)
                        .textContentType(.password)
                        .disabled(tokenChecking)
                        .onSubmit {
                            persistTokenIfNeeded()
                        }

                    HStack(spacing: 10) {
                        Button("Verify token") {
                            let draft = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            tokenChecking = true
                            Task {
                                let (ok, err) = await runtimeData.testGithubToken(draft)
                                tokenChecking = false
                                showTokenAlert = true
                                tokenAlertTitle = ok ? "Token verified" : "Token verification failed"
                                tokenAlertContent = ok
                                    ? "This token can access GitHub notifications."
                                    : err

                                if ok {
                                    persistTokenIfNeeded()
                                    AppLog.info("Token verification succeeded")
                                } else {
                                    AppLog.warning("Token verification failed: \(err)")
                                }
                            }
                        }
                        .disabled(tokenChecking || tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if tokenChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .alert(isPresented: $showTokenAlert) {
                        Alert(title: Text(tokenAlertTitle), message: Text(tokenAlertContent))
                    }
                } header: {
                    Text("Access Token")
                } footer: {
                    Text("Only the Notifications permission is required. The token is saved when you leave this page, or when verification succeeds.")
                }

                Section("Help") {
                    Link("Open token settings", destination: URL(string: "https://github.com/settings/tokens")!)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(20)
        }
        .navigationTitle("GitHub")
        .onAppear {
            tokenDraft = runtimeData.githubToken
        }
        .onDisappear {
            persistTokenIfNeeded()
        }
    }

    private func persistTokenIfNeeded() {
        let trimmed = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != runtimeData.githubToken {
            runtimeData.githubToken = trimmed
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingsAppIconView(size: 56, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("GitStatus")
                        .font(.title2)
                    Text(versionString)
                        .foregroundStyle(.secondary)
                }
            }

            Text("A lightweight menubar app for GitHub notifications.")
                .foregroundStyle(.secondary)

            Divider()

            Form {
                Section("Links") {
                    Link("GitHub repository", destination: URL(string: "https://github.com/0x2E/GitStatus")!)
                    Link("Report an issue", destination: URL(string: "https://github.com/0x2E/GitStatus/issues")!)
                }

                Section {
                    LabeledContent("Logs") {
                        HStack(spacing: 10) {
                            Button("Show in Finder") {
                                AppLog.revealLogFileInFinder()
                            }
                            Button("Copy path") {
                                AppLog.copyLogFilePathToPasteboard()
                            }
                        }
                    }

                    Text(AppLog.logFileURL.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospaced()
                        .textSelection(.enabled)
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("When reporting an issue, attach the log file if possible.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .navigationTitle("About")
    }

    private var versionString: String {
        AppVersion.formatted(versionPrefix: "Version ", buildPrefix: "Build ")
    }
}

private struct SettingsAppIconView: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image(nsImage: appIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private var appIconImage: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        return NSApp.applicationIconImage
    }
}

#Preview {
    SettingView()
        .environment(RuntimeData())
}
