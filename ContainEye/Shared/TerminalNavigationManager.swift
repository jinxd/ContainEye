//
//  TerminalNavigationManager.swift
//  ContainEye
//
//  Created by Claude on 6/22/25.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class TerminalNavigationManager {
    static let shared = TerminalNavigationManager()
    
    var pendingCredential: Credential?
    var showingDeeplinkConfirmation = false
    
    private init() {}
    
    func navigateToTerminal(with credential: Credential) {
        pendingCredential = credential
        showingDeeplinkConfirmation = true
        // Switch to terminal tab
        UserDefaults.standard.set(ContentView.Screen.terminal.rawValue, forKey: "screen")
    }
}