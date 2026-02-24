//
//  SuggestedTestCard.swift
//  ContainEye
//
//  Created by Hannes Nagel on 6/27/25.
//


import SwiftUI
import Blackbird
import ButtonKit

struct SuggestedTestCard: View {
    let test: ServerTest
    @State private var isAdding = false
    @State private var isPresentingServerSelection = false
    @State private var selectedServerKey: String?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)

                Spacer()

                Text("Suggested")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.1), in: .capsule)
            }
            .foregroundStyle(.orange)

            VStack(alignment: .leading) {
                Text(test.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(test.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Add Test", systemImage: "plus") {
                isPresentingServerSelection = true
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.green)
            .disabled(isAdding)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        }
        .sheet(isPresented: $isPresentingServerSelection) {
            ServerSelectionView(
                test: test,
                selectedServer: $selectedServerKey,
                isAdding: $isAdding,
                isPresented: $isPresentingServerSelection
            )
            .confirmator()
        }
    }
}

#Preview(traits: .sampleData) {
    SuggestedTestCard(
        test: ServerTest(
            id: 9010,
            title: "Check API health endpoint",
            notes: nil,
            credentialKey: "-",
            command: "curl -sf http://localhost:8080/health",
            expectedOutput: "ok",
            lastRun: nil,
            status: .notRun,
            output: nil
        )
    )
    .padding()
}
