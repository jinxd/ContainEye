//
//  SheetView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/15/25.
//

import SwiftUI

struct SheetView: View {
    let sheet: ContentView.Sheet

    var body: some View {
        NavigationStack {
            switch sheet {
            case .addServer:
                AddServerView()
            case .addTest:
                AddTestView()
            }
        }
    }
}



#Preview {
    SheetView(sheet: .addServer)
}
