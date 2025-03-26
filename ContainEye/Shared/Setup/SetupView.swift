//
//  SetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI

struct SetupView: View {
    @Binding var sheet: ContentView.Sheet?
    @AppStorage("setupScreen") private var setupScreen : Int = 0
    @AppStorage("screen") private var screen = ContentView.Screen.testList

    var body: some View {

        TabView(selection: $setupScreen) {
            Tab(value: 1){
                SecondSetupView(screen: $setupScreen)
            }
            Tab(value: 3){
                WouldYouLikeToAddATestView(screen: $setupScreen)
            }
            Tab(value: 2){
                AddServerSetupView(screen: $setupScreen)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: setupScreen) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .animation(.default, value: setupScreen)
        .toolbar{
            Button("Cancel") {
                UserDefaults.standard.set(setupScreen == 1 ? ContentView.Screen.serverList.rawValue : ContentView.Screen.testList.rawValue, forKey: "screen")
            }
        }
        .onChange(of: setupScreen, initial: true) {
            Logger.telemetry("viewing screen \(setupScreen == 1 ? "server" : setupScreen == 2 ? "ask test setup" : "test setup")")
        }
    }
}

#Preview {
    SetupView(sheet: .constant(.none))
}




