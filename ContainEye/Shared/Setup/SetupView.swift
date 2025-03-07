//
//  SetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI

struct SetupView: View {
    @Binding var sheet: ContentView.Sheet?
    @State private var setupScreen : Int? = 0
    @AppStorage("screen") private var screen = ContentView.Screen.testList

    var body: some View {
        ScrollViewReader{scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Group {
                        StartSetupView(screen: $setupScreen)
                            .id(0)
                        SecondSetupView(screen: $setupScreen)
                            .id(1)
                        AddServerSetupView(screen: $setupScreen)
                            .id(2)
                        WouldYouLikeToAddAnotherTestView(screen: $setupScreen)
                            .id(3)
                    }
                    .frame(maxHeight: .infinity)
                    .containerRelativeFrame(.horizontal)
                    .background(
                        LinearGradient(
                            colors: [
                                .accent.opacity(0.2),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .background()
                        .clipShape(.rect(cornerRadius: 15))
                        .ignoresSafeArea()
                    )
                    .scrollTransition{
                        content,
                        scroll in
                        content
                            .scaleEffect(
                                1-scroll.value.magnitude
                            )
                    }
                    .scrollTargetLayout()
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $setupScreen)
            .animation(.default, value: setupScreen)
            .scrollDismissesKeyboard(.immediately)
        }
        .toolbar{
            Button("Cancel") {
                UserDefaults.standard.set(setupScreen == 1 ? ContentView.Screen.serverList.rawValue : ContentView.Screen.testList.rawValue, forKey: "screen")
            }
        }
        .onChange(of: screen, initial: true) {
            setupScreen = UserDefaults.standard.integer(forKey: "setupScreen")
        }
    }
}

#Preview {
    SetupView(sheet: .constant(.none))
}




