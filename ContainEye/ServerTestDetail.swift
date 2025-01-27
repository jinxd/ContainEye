//
//  ServerTestDetail.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/23/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import KeychainAccess

struct ServerTestDetail: View {
    @BlackbirdLiveModel var test: ServerTest?
    @Environment(\.blackbirdDatabase) private var db
    @State private var expandedElement = ExpandableElement?.none
    @Environment(\.dismiss) private var dismiss

    enum ExpandableElement {
        case expectedOutput, actualOutput
    }

    var body: some View {
        if let test {
            Form {
                let host = keychain()
                    .getCredential(for: test.credentialKey)?.host ?? ""

                LabeledContent("Host", value: host)
                LabeledContent("Command", value: test.command)
                LabeledContent("Last run", value: test.lastRun?.formatted(.dateTime) ?? "Never")
                Section("Expected output") {
                    Text(test.expectedOutput)
                        .lineLimit(expandedElement == .expectedOutput ? nil : 2)
                        .onTapGesture {
                            expandedElement = expandedElement == .expectedOutput ? .none : .expectedOutput
                        }
                }
                Section("Actual output") {
                    Text(test.output ?? "No output")
                        .italic(test.output == nil)
                        .lineLimit(expandedElement == .actualOutput ? nil : 2)
                        .onTapGesture {
                            expandedElement = expandedElement == .actualOutput ? .none : .actualOutput
                        }
                }


                let color = switch test.state {
                case .failed:
                    Color.red
                case .success:
                    Color.green
                default:
                    Color.gray
                }
                Section {
                    AsyncButton("Test Now") {
                        self.test?.state = .running
                        let test = await test.test()
#if !os(macOS)
                        if test.state == .failed {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
#endif
                        try await test.write(to: db!)
                    }
                    .asyncButtonStyle(.pulse)
                    .listRowBackground(
                        RoundedProgressRectangle(cornerRadius: 10)
                            .stroke(color, lineWidth: 5)
                            .fill(color.tertiary.tertiary)
                    )
                }
                Section{
                    AsyncButton(role: .destructive) {
                        try await test.delete(from: db!)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .textSelection(.enabled)
            .animation(.spring, value: expandedElement)
            .navigationTitle(test.title)
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "questionmark.circle")
        }
    }
}

#Preview {
    ServerTestDetail(test: BlackbirdLiveModel<ServerTest>(ServerTest(id: Int.random(in: (.min)...(Int.max)), title: "Title", credentialKey: UUID().uuidString, command: "curl localhost", expectedOutput: ".+", state: .notRun)))
}
