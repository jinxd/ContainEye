//
//  RoundedProgressRectangle.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/17/25.
//

import SwiftUI

struct RoundedProgressRectangle: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = rect.size.width
            let height = rect.size.height
            let radius = min(cornerRadius, width / 2, height / 2)

            // Start at the bottom center
            path.move(to: CGPoint(x: width / 2, y: height))

            // Move left to the bottom left corner
            path.addLine(to: CGPoint(x: radius, y: height))

            // Bottom left corner curve
            path.addArc(center: CGPoint(x: radius, y: height - radius),
                        radius: radius,
                        startAngle: .degrees(90),
                        endAngle: .degrees(180),
                        clockwise: false)

            // Move up to the top left corner
            path.addLine(to: CGPoint(x: 0, y: radius))

            // Top left corner curve
            path.addArc(center: CGPoint(x: radius, y: radius),
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(270),
                        clockwise: false)

            // Move right to the top right corner
            path.addLine(to: CGPoint(x: width - radius, y: 0))

            // Top right corner curve
            path.addArc(center: CGPoint(x: width - radius, y: radius),
                        radius: radius,
                        startAngle: .degrees(270),
                        endAngle: .degrees(360),
                        clockwise: false)

            // Move down to the bottom right corner
            path.addLine(to: CGPoint(x: width, y: height - radius))

            // Bottom right corner curve
            path.addArc(center: CGPoint(x: width - radius, y: height - radius),
                        radius: radius,
                        startAngle: .degrees(0),
                        endAngle: .degrees(90),
                        clockwise: false)

            // Return to the bottom center
            path.addLine(to: CGPoint(x: width / 2, y: height))
        }
    }
}
