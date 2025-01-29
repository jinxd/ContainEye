//
//  TestSummaryView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/27/25.
//

import Blackbird
import SwiftUI
import ButtonKit

struct TestSummaryView: View {
    @BlackbirdLiveModel var test: ServerTest?
    @Environment(\.blackbirdDatabase) var db

    var body: some View {
        if let test {
            NavigationLink(value: test) {
                VStack(alignment: .leading) {
                    Text(test.title)
                        .font(.headline)
                    let host = keychain().getCredential(for: test.credentialKey)?.host ?? "???"
                    Text(host)
                    Text(test.state.localizedDescription)
                }
                .lineLimit(1)
                .padding()
                .frame(maxWidth: .infinity)
                .background {
                    let state = test.state
                    let color = state == .failed ? Color.red : state == .success ? Color.green : Color.blue

                    TimelineView(.animation(paused: state != .running)) { context in
                        let trimTo = state == .notRun ? 1 : state == .running ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) / 2 : 1

                        let trimFrom: Double =
                        if state == .running {
                            max(0, trimTo - pow((1 - trimTo), 2))
                        } else {
                            0
                        }

                        RoundedProgressRectangle(cornerRadius: 15)
                            .trim(from: trimFrom, to: trimTo)
                            .stroke(color, style: StrokeStyle(
                                lineWidth: 5,
                                dash: state == .running ? [0, 0.3, 4] : []
                            ))
                    }
                }
            }
            .contextMenu {
                AsyncButton("Execute", systemImage: "testtube.2") {
                    var test = test
                    test.state = .running
                    try await test.write(to: db!)
                    test = await test.test()

#if !os(macOS)
                    if test.state == .failed {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
#endif
                    try await test.write(to: db!)
                }
                AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                    try await test.delete(from: db!)
                }
            }
            .padding(3)
#if !os(macOS)
            .drawingGroup()
#endif
        }
    }
}
