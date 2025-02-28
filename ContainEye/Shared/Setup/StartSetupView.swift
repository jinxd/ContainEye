//
//  StartSetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI

struct StartSetupView: View {
    @Binding var screen: Int?
    let date = Date()

    var body: some View {
        VStack {
            Spacer()
            VStack {
                Text("Welcome to")
                TimelineView(.animation){con in
                    Text("ContainEye")
                        .textRenderer(OnboardingAppearanceEffectRenderer(elapsedTime: con.date.timeIntervalSince(date), totalDuration: 2))

                }
            }
            .font(.largeTitle.bold())
            .padding(.horizontal)
            Spacer()
            TimelineView(.animation) { con in
                let timeinterval = max(0, con.date.timeIntervalSince(date) - 3)
                let isServer = Int(timeinterval/6) % 2 == 0
                ContentUnavailableView(
                    isServer ? "First we'll add a server" : "Next we'll add a few tests",
                    systemImage: isServer ? "server.rack" : "testtube.2",
                    description: Text(isServer ? "You have to add a server to monitor it's status and test it." : "These can help you keep your servers in great shape.")
                )
                .font(.largeTitle.bold())
                .imageScale(.large)
                .symbolEffect(.rotate, value: isServer)
                .animation(.smooth, value: isServer)
                .textRenderer(OnboardingAppearanceEffectRenderer(elapsedTime: timeinterval.truncatingRemainder(dividingBy: 6), totalDuration: 2))
            }
            Spacer()
            Button("Get started") {
                Logger.telemetry("setup started")
                screen = 1
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            Spacer()
        }
    }
}
