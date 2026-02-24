//
//  IntentReturnView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/3/25.
//

import SwiftUI


struct IntentReturnView: View {
    let tests: [ServerTest]
    let retryIntent: TestServers?

    var body: some View {

        VStack{
            ForEach(tests) { test in
                HStack {
                    Text(test.title)
                    Spacer()
                    test.status.image
                        .foregroundStyle(test.status == .failed ? .red : test.status == .success ? .green : .gray)
                }
                .foregroundStyle(.white)
                if test != tests.last {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 2)
                }
            }
            if let retryIntent = retryIntent {
                Button("Retry (in background)", intent: retryIntent)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .padding(5)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.2), in: .rect(cornerRadius: 15))
        .padding()
    }
}

#Preview(traits: .sampleData) {
    IntentReturnView(
        tests: [
            PreviewSamples.test,
            ServerTest(
                id: 9002,
                title: "Disk Usage",
                notes: nil,
                credentialKey: PreviewSamples.credential.key,
                command: "df -h",
                expectedOutput: "Avail",
                lastRun: .now.addingTimeInterval(-60),
                status: .failed,
                output: "Filesystem full"
            )
        ],
        retryIntent: nil
    )
}
