//
//  SheetView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/15/25.
//

import SwiftUI

struct SheetView: View {
    let sheet: ContentView.Sheet
    @Environment(\.namespace) var namespace

    var body: some View {
        NavigationStack {
            Group{
                switch sheet {
                case .addServer:
                    AddServerView()
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: sheet, in: namespace!))
#endif
                case .addTest:
                    AddTestView()
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: sheet, in: namespace!))
#endif
                case .feedback:
                    SubmitFeedbackView()
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: sheet, in: namespace!))
#endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color.accentColor.opacity(0.2), location: 0),
                        .init(color: Color.gray.opacity(0.2), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                ), ignoresSafeAreaEdges: .all
            )
        }
    }
}



#Preview {
    SheetView(sheet: .addServer)
}
