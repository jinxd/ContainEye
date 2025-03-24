//
//  WouldYouLikeToAddAnotherTestView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/6/25.
//


import SwiftUI

struct WouldYouLikeToAddATestView: View {
    @Binding var screen: Int

    var body: some View {
        VStack {
            Spacer()
            ContentUnavailableView("Would you like to add a test for your server now?", systemImage: "testtube.2")
            Spacer()
            VStack {
                Group{
                    Button{
                        screen = 2
                    } label: {
                        Text("Yes, let's add one!")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button{
                        UserDefaults.standard.set(ContentView.Screen.terminal.rawValue, forKey: "screen")
                    } label: {
                        Text("Maybe later...")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .buttonBorderShape(.roundedRectangle(radius: 15))
            }
        }

        .frame(maxWidth: 700)
    }
}

#Preview {
    WouldYouLikeToAddATestView(screen: .constant(3))
}
