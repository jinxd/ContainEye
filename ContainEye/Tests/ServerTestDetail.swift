//
//  ServerTestDetail.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/23/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import KeychainAccess

struct ServerTestDetail: View {
    @BlackbirdLiveModel var test: ServerTest?
    
    var body: some View {
        if let test {
            if test.credentialKey == "-" {
                ConfigureDisabledTestView(test: test.liveModel)
            } else {
                ModernServerTestDetail(test: test.liveModel)
            }
        }
    }
}