//
//  WouldYouLikeToAddAnotherTestView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/6/25.
//


import SwiftUI

struct WouldYouLikeToAddAnotherTestView: View {
    @Binding var screen: Int?

    var body: some View {
        VStack {
            Spacer()
            ContentUnavailableView("Would you like to add another test?", systemImage: "testtube.2")
            Spacer()
            VStack {
                Group{
                    Button{
                        screen = 2
                    } label: {
                        Text("Yes, add another one!")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button{
                        UserDefaults.standard.set(ContentView.Screen.testList.rawValue, forKey: "screen")
                    } label: {
                        Text("Nope")
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
    WouldYouLikeToAddAnotherTestView(screen: .constant(3))
}
