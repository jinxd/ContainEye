//
//  SetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI

struct SetupView: View {
    @AppStorage("setupScreen") private var setupScreen : Int = 0
    @AppStorage("screen") private var screen = ContentView.Screen.serverList

    var body: some View {
        TabView(selection: $setupScreen) {
            Tab(value: 0) {
                WelcomeView(setupScreen: $setupScreen)
            }
            Tab(value: 1) {
                AddServerView(screen: $setupScreen)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: setupScreen) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .animation(.spring(), value: setupScreen)
        .toolbar {
            if setupScreen > 0 {
                Button(role: .cancel) {
                    UserDefaults.standard.set(ContentView.Screen.serverList.rawValue, forKey: "screen")
                }
            }
        }
    }
}

#Preview(traits: .sampleData) {
    SetupView()
}

