//
//  SubmitFeedbackView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/12/25.
//

import SwiftUI
import PhotosUI
import ButtonKit

struct SubmitFeedbackView: View {
    @State private var title = ""
    @State private var message = ""
    @State private var feedbackType = FeedbackType.opinion
    @Environment(\.dismiss) var dismiss

    enum FeedbackType: String, CaseIterable {
        case opinion = "Opinion"
        case bug = "Bug"
        case request = "Request"
        case criticalbug = "Critical Bug"
    }
    @State private var isPickingPhotos = false
    var body: some View {
        Form {
            Section{
                TextField("Feedback title", text: $title)
                    .font(.headline)
            }
            Section {
                Picker("What is this feedback about?", selection: $feedbackType) {
                    ForEach(FeedbackType.allCases, id: \.self) { fbType in
                        Text(fbType.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                TextField("Feedback message", text: $message, axis: .vertical)
                    .lineLimit(3...10)
            }
            #warning("currently aptabase event parameters are not working...")
//            Section("Directly"){
//                AsyncButton("Submit Feedback") {
//                    Logger.telemetry(
//                        "Submit Feedback",
//                        with:
//                            [
//                                "title" : title,
//                                "message" : message
//                            ]
//                    )
//                    await Logger.flushTelemetry()
//                    dismiss()
//                }
//            }
            Section("Currently Mail only") {
                if let url = URL(string: "mailto:contact@hannesnagel.com?subject=Feedback (\(feedbackType.rawValue)): \(title)&body=\(message)") {
                    Link("Submit Feedback", destination: url)
                }
            }
        }
        .navigationTitle("Submit Feedback")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview {
    SubmitFeedbackView()
}
