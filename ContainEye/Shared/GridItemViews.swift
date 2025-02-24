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
                text
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background{
                RoundedProgressRectangle(cornerRadius: 15)
                    .fill(.background)
                RoundedProgressRectangle(cornerRadius: 15)
                    .trim(from: 0, to: trim)
                    .stroke(.accent, style: .init(lineWidth: 10, lineCap: .round))
                    .padding(3)
            }
            .redacted(reason: redacted ? .placeholder : [])
            .padding(5)
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
                text: SwiftUI.Text(percentage ?? 0, format: .percent.precision(.fractionLength(2))),
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
