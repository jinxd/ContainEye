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
                    let host = keychain()
                        .getCredential(for: test.credentialKey)?.host
                    let hostText = host ?? (test.credentialKey.isEmpty ? "Local (urls only)" : "Do not run")
                    Text(hostText)
                    Text(test.status.localizedDescription)
                }
                .lineLimit(1)
                .padding()
                .frame(maxWidth: .infinity)
                .background {
                    let status = test.status
                    let color = status == .failed ? Color.red : status == .success ? Color.green : Color.blue

                    TimelineView(.animation(paused: status != .running)) { context in
                        let trimTo = status == .notRun ? 1 : status == .running ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) / 2 : 1

                        let trimFrom: Double =
                        if status == .running {
                            max(0, trimTo - pow((1 - trimTo), 2))
                        } else {
                            0
                        }

                        RoundedProgressRectangle(cornerRadius: 15)
                            .trim(from: trimFrom, to: trimTo)
                            .stroke(color, style: StrokeStyle(
                                lineWidth: 5,
                                dash: status == .running ? [0, 0.3, 4] : []
                            ))
                    }
                }
            }
            .contextMenu {
                if test.credentialKey != "-" {
                    AsyncButton("Execute", systemImage: "testtube.2") {
                        var test = test
                        test.status = .running
                        try await test.write(to: db!)
                        test = await test.test()
                        
#if !os(macOS)
                        if test.status == .failed {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
#endif
                        try await test.write(to: db!)
                        try await test.testIntent().donate()
                    }
                    Menu{
                        AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                            try await test.delete(from: db!)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .padding(3)
#if !os(macOS)
            .drawingGroup()
#endif
        }
    }
}
