//
//  GridItemViews.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//

import SwiftUI
import ButtonKit


enum GridItemView {
    private struct GridItemView: View {
        let title: String
        let text: SwiftUI.Text
        let trim: Double
        let redacted: Bool

        var body: some View {
            VStack {
                SwiftUI.Text(title)
                    .bold()
                    .font(.caption2)
                VStack {
                    text
                        .lineLimit(1)
                        .contentTransition(.numericText(value: trim))
                }
                .padding(20)
                .background{
                    Circle()
                        .fill(.background)
                    Circle()
                        .trim(from: 0, to: trim)
                        .stroke(.accent, style: .init(lineWidth: 5, lineCap: .round))
                        .padding(1)
                }
                .redacted(reason: redacted ? .placeholder : [])
                .minimumScaleFactor(0.3)
            }
            .animation(.smooth, value: trim)
        }
    }

    struct Date: View {
        let title: String
        let value: Foundation.Date?

        var body: some View {
            GridItemView(
                title: title,
                text: SwiftUI.Text(value ?? .now, style: .relative)
                    .monospacedDigit()
                ,
                trim: 1,
                redacted: value == nil
            )
        }
    }

    struct Text: View {
        let title: String
        let text: String?

        var body: some View {
            GridItemView(
                title: title,
                text: SwiftUI.Text(text ?? ""),
                trim: 1,
                redacted: text == nil
            )
        }
    }

    struct Percentage: View {
        let title: String
        let percentage: Double?

        var body: some View {
            GridItemView(
                title: title,
                text: SwiftUI.Text(percentage ?? 0, format: .percent.precision(.fractionLength(1))),
                trim: percentage ?? 1,
                redacted: percentage == nil
            )
        }
    }

    struct AsyncProgressButtonStyle: AsyncButtonStyle {
        let title: String

        func makeLabel(configuration: LabelConfiguration) -> some View {
            if configuration.isLoading {
                Percentage(title: title, percentage: configuration.fractionCompleted)
            } else {
                configuration.label
            }
        }
    }
}

#Preview("Grid Items", traits: .sampleData) {
    HStack {
        GridItemView.Date(title: "Updated", value: .now.addingTimeInterval(-120))
        GridItemView.Text(title: "Status", text: "Healthy")
        GridItemView.Percentage(title: "CPU", percentage: 0.36)
    }
    .padding()
}
