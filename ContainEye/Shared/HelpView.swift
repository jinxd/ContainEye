//
//  HelpView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/6/25.
//

import SwiftUI

enum Help: String {
    case servers, tests
}

struct HelpView: View {
    let help: Help

    var body: some View {
        Group{
            switch help {
            case .servers:
                ServersHelp()
            case .tests:
                TestsHelp()
            }
        }
        .onAppear{
            Logger.telemetry("Opened \(help.rawValue) help view")
        }
    }
}

