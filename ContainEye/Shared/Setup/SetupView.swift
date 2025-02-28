//
//  SetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI

struct SetupView: View {
    @State private var screen : Int? = 0

    var body: some View {
        ScrollViewReader{scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Group {
                        StartSetupView(screen: $screen)
                            .id(0)
                        SecondSetupView(screen: $screen)
                            .id(1)
                    }
                    .containerRelativeFrame(.horizontal)
                    .background(
                        LinearGradient(
                            colors: [
                                .accent,
                                .clear
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .background()
                        .clipShape(.rect(cornerRadius: 15))
                        .ignoresSafeArea()
                    )
                    .scrollTransition{
                        content,
                        scroll in
                        content
                            .scaleEffect(
                                1-scroll.value.magnitude
                            )
                    }
                    .scrollTargetLayout()
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $screen)
            .animation(.default, value: screen)
        }
    }
}

#Preview {
    SetupView()
}
