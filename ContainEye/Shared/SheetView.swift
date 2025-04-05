//
//  SheetView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/15/25.
//

import SwiftUI

enum Sheet: Identifiable {
    case feedback, credits

    var id: String {
        switch self {
        case .feedback:
            "feedback"
        case .credits:
            "credits"
        }
    }
}

struct SheetView: View {
    let sheet: Sheet
    @Environment(\.namespace) var namespace

    var body: some View {
        Group{
            switch sheet {
            case .feedback:
                SubmitFeedbackView()
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: sheet, in: namespace!))
#endif
            case .credits:
                CreditsView()
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: sheet, in: namespace!))
#endif
            }
        }
    }
}



#Preview {
    SheetView(sheet: .feedback)
}
