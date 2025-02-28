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
                case .feedback:
                    SubmitFeedbackView()
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: sheet, in: namespace!))
#endif
                }
            }
        }
    }
}



#Preview {
    SheetView(sheet: .feedback)
}
