//
//  TestSummaryView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/27/25.
//

import Blackbird
import SwiftUI
import ButtonKit

struct TestSummaryView: View {
    @BlackbirdLiveModel var test: ServerTest?
    
    var body: some View {
        if let test {
            ModernTestSummaryView(test: test.liveModel)
        }
    }
}
