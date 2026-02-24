//
//  AddTestFlowView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 6/26/25.
//


import SwiftUI

struct AddTestFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var setupScreen = 2 // Start at AddTestView
    
    var body: some View {
        AddTestView(screen: $setupScreen)
            .onAppear {
                setupScreen = 2
            }
            .onChange(of: setupScreen) {
                if setupScreen != 2 {
                    dismiss()
                }
            }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        AddTestFlowView()
    }
}
