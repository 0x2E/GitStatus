//
//  GitStatusApp.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import SwiftUI

@main
struct GitStatusApp: App {
    init() {
        AppLog.bootstrap()
        AppLog.info("App launch")
        Task { @MainActor in
            RuntimeData.shared.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(RuntimeData.shared)
                .frame(width: 420, height: 520)
        } label: {
            MenuBarLabelView()
                .environmentObject(RuntimeData.shared)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "settings") {
            SettingView()
                .environmentObject(RuntimeData.shared)
        }
        .defaultSize(width: 720, height: 520)
    }
}

private struct MenuBarLabelView: View {
    @EnvironmentObject private var runtimeData: RuntimeData

    var body: some View {
        let count = runtimeData.notifications.count
        let hasError = !runtimeData.message.isEmpty

        HStack(spacing: 4) {
            Image("MenubarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            if count > 0 {
                Text("\(count)")
                    .monospacedDigit()
            }

            if hasError {
                Text("!")
            }
        }
    }
}
