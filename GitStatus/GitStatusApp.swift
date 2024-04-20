//
//  GitStatusApp.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import SwiftUI

@main
struct GitStatusApp: App {
    @ObservedObject var runtimeData = RuntimeData().run()
    
    var body: some Scene {
        Settings{
            SettingView()
                .environmentObject(runtimeData)
        }
        
        MenuBarExtra {
            ContentView()
                .environmentObject(runtimeData)
        } label: {
            // https://mirzoyan.dev/mirzoyan%20dev%20d62e6ab9344e4ab8a9c14205257ea2cc/Blog%20208f3509a5b74655b973d4dbaaf500e6/Custom%20icon%20for%20SwiftUI%20MenuBarExtra%20fdd31ec3e0af46adb3f7f69129bd6172
            let image: NSImage = {
                    let ratio = $0.size.height / $0.size.width
                    $0.size.height = 20
                    $0.size.width = 20 / ratio
                    return $0
                }(NSImage(named: "MenubarIcon")!)

                Image(nsImage: image)
            
            if runtimeData.notifications.count > 0 {
                Text(runtimeData.notifications.count, format: .number)
            }
            
            if !runtimeData.message.isEmpty {
                Text("!")
            }
        }
    }
}
