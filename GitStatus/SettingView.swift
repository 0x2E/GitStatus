//
//  SettingView.swift
//  GitStatus
//
//  Created by rook1e on 2023/10/6.
//

import SwiftUI

struct SettingView: View {
    var body: some View {
        TabView {
            GeneralSettingView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("general")

            TokenSettingView()
                .tabItem {
                    Label("Token", systemImage: "key.horizontal")
                }
                .tag("token")
        }
        .frame(minHeight: 200, maxHeight: 400)
        .padding(20)
    }
}

struct GeneralSettingView: View {
    @EnvironmentObject var runtimeData: RuntimeData
    
    var body: some View {
        ScrollView {
            VStack {
                Form {
                    TextField("List length:", value: $runtimeData.listLength, format: .number)
                    
                    TextField("Fetch interval in seconds:", value: $runtimeData.interval, format: .number)
                    Text("Note: GitHub API limits 5000 calls per hour per user.")
                        .foregroundColor(.secondary)
                        // .lineLimit(nil) not work
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())

                Spacer()
            }
        }
    }
}

struct TokenSettingView: View {
    @EnvironmentObject var runtimeData: RuntimeData
    @State private var tokenChecking = false
    @State private var showTokenAlert = false
    @State private var tokenAlertTitle = ""
    @State private var tokenAlertContent = ""
    
    var body: some View {
        ScrollView {
            VStack {
                Form {
                    SecureField("GitHub Token", text: $runtimeData.githubToken)
                        .disabled(tokenChecking)
                    Button(action: {
                        tokenChecking = true
                        Task {
                            let (ok, err) = await runtimeData.testGithubToken()
                            tokenChecking = false
                            showTokenAlert = true
                            
                            tokenAlertTitle = ok ? "Successfully verified token" : "Fail to verify token"
                            tokenAlertContent = err
                        }
                    }){
                        if tokenChecking {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(height: 5)
                        } else {
                            Text("Verify")
                        }
                    }
                    .disabled(tokenChecking)
                    .alert(isPresented: $showTokenAlert) {
                        Alert(title: Text(tokenAlertTitle), message: Text(tokenAlertContent))
                    }
                    
                    Text("Generate a Personal access token [here](https://github.com/settings/tokens). Note: Only **notifications** permissions are required.")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
    }
}

#Preview {
    SettingView()
}
