//
//  TerminalView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/13/25.
//

import SwiftUI
import SwiftTerm

struct RemoteTerminalView: View {
    @State private var credential: Credential?
    @State private var history = [String]()
    @AppStorage("useVolumeButtons") private var useVolumeButtons = false
    @State private var terminalManager = TerminalNavigationManager.shared

    @State var view: SSHTerminalView?

    @State private var messageText = String?.none
    @State private var showingSettings = false
    @State private var terminalTheme: TerminalTheme = .dark
    @AppStorage("terminalFontSize") private var fontSize: Double = 12.0
    
    // Completion state
    @State private var completionSuggestions = [String]()
    @State private var isLoadingCompletion = false

    var body: some View {
        VStack(spacing: 0){
            if let credential {
                if let view{
                    view
                        .toolbarVisibility(.hidden, for: .navigationBar)
                        .toolbarVisibility(.hidden, for: .tabBar)
                        .overlay(alignment: .topTrailing){
                            VStack(alignment: .trailing) {
                                HStack{
                                    Button {
                                        useVolumeButtons.toggle()
                                        self.view?.useVolumeButtons = useVolumeButtons
                                        messageText = useVolumeButtons ? "Volume buttons now control terminal arrow keys" : "Volume buttons no longer control terminal"
                                    } label: {
                                        Image(systemName: useVolumeButtons ? "plusminus.circle.fill" : "plusminus.circle")
                                            .font(.title)
                                    }
                                    Button{
                                        view.cleanup()
                                        self.view = nil
                                        self.credential = nil
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .buttonBorderShape(.circle)
                                    .controlSize(.large)
                                }
                                if let messageText {
                                    Text(messageText)
                                        .task{
                                            try? await Task.sleep(for: .seconds(2))
                                            self.messageText = nil
                                        }
                                        .padding(2)
                                        .background(in: .capsule)
                                }
                            }
                        }
                        .onDisappear{
                            view.setCurrentInputLine("history -a\n")
                            view.cleanup()
                            self.view = nil
                        }
                        .trackView("terminal/connected")


                    TimelineView(.periodic(from: .now, by: 0.3)) { ctx in

                            let inputLine = view.currentInputLine.trimmingCharacters(in: .whitespaces)
                            let preitems = shortestStartingWith(inputLine, in: history, limit: 3)
                            let items = (preitems.isEmpty ? ["None"] : preitems)
                        HStack{
                            ForEach(items, id: \.self) { suggestion in
                                Button{
                                    view.setCurrentInputLine(suggestion)
                                } label: {
                                    Text(suggestion)
                                        .frame(minWidth: 100)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.1)
                                        .font(.headline)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .tint(suggestion == inputLine ? Color.blue : Color.black)
                                .italic(suggestion == "None")
                                .disabled(suggestion == "None")
                            }
                        }
                        .onChange(of: inputLine){
                            if !inputLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty{
                                // Terminal typing detected
                            }
                        }
                        .padding(.horizontal)
                        .font(.title)
                        .minimumScaleFactor(0.3)
                    }
                } else {
                    Text("loading...")
                        .task{
                            do {
                                let command = #"(cat ~/.bash_history 2>/dev/null; [ -f ~/.bash_history ] && echo ""; cat ~/.zsh_history 2>/dev/null) | tail -n 200"#
                                let historyString = try await SSHClientActor.shared.execute(command, on: credential)
                                print(historyString)
                                self.history = Array(Set(historyString.components(separatedBy: "\n").reversed())).filter({$0.trimmingCharacters(in: .whitespaces).count > 1})
                                    .filter({$0 != command})
                            } catch {
                                print(error)
                            }
                            view = SSHTerminalView(credential: .init(key: credential.key, label: credential.label, host: credential.host, port: credential.port, username: credential.username, password: credential.password), useVolumeButtons: useVolumeButtons)
                        }
                        .trackView("terminal/connecting")
                }
            } else {
                VStack {
                    Text("Select a server to connect to").monospaced()
                    Picker(selection: $credential) {
                        let keychain = keychain()
                        let credentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
                        Text("None")
                            .tag(Credential?.none)
                        ForEach(credentials, id: \.key) { credential in
                            Text(credential.label)
                                .tag(credential)
                        }
                    } label: {
                    }
                    .pickerStyle(.inline)
                }
                .trackView("terminal/select-server")
            }
        }
        .preferredColorScheme(view == nil ? .none : .dark)
        .onChange(of: credential) { oldValue, newValue in
            if let oldView = view, oldValue != newValue {
                oldView.cleanup()
                view = nil
            }
        }
        .onAppear {
            // Check for pending credential from navigation
            if let pendingCredential = terminalManager.pendingCredential {
                credential = pendingCredential
                terminalManager.pendingCredential = nil
                
                // Show confirmation message
                if terminalManager.showingDeeplinkConfirmation {
                    messageText = "Connected to \(pendingCredential.label)"
                    terminalManager.showingDeeplinkConfirmation = false
                }
            }
        }
    }
    func shortestStartingWith(_ prefix: String, in array: [String], limit: Int) -> [String] {
        return array
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
            .sorted { $0.count < $1.count }
            .prefix(limit)
            .map { $0 }
    }
    
    private func getSmartCompletions(for input: String) -> [String] {
        let trimmedInput = input.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.isEmpty else { return [] }
        
        let parts = trimmedInput.split(separator: " ")
        guard let command = parts.first else { return [] }
        
        // Smart completion based on command
        switch String(command) {
        case "cd":
            return getDirectoryCompletions(for: trimmedInput)
        case "mv", "cp", "rm", "cat", "less", "more", "nano", "vim", "emacs":
            return getFileCompletions(for: trimmedInput)
        case "ls":
            return getDirectoryCompletions(for: trimmedInput)
        default:
            return getHistoryCompletions(for: trimmedInput)
        }
    }
    
    private func getDirectoryCompletions(for input: String) -> [String] {
        // Combine completion suggestions with history
        let historyMatches = shortestStartingWith(input, in: history, limit: 2)
        let completionMatches = Array(completionSuggestions.prefix(3))
        
        var combined = Set<String>()
        combined.formUnion(historyMatches)
        combined.formUnion(completionMatches)
        
        return Array(combined).sorted()
    }
    
    private func getFileCompletions(for input: String) -> [String] {
        // Similar to directory completions but for files
        let historyMatches = shortestStartingWith(input, in: history, limit: 2)
        let completionMatches = Array(completionSuggestions.prefix(3))
        
        var combined = Set<String>()
        combined.formUnion(historyMatches)
        combined.formUnion(completionMatches)
        
        return Array(combined).sorted()
    }
    
    private func getHistoryCompletions(for input: String) -> [String] {
        return shortestStartingWith(input, in: history, limit: 3)
    }
    
    private func loadCompletionSuggestions(for input: String) async {
        guard let credential = credential, !isLoadingCompletion else { return }
        
        isLoadingCompletion = true
        defer { isLoadingCompletion = false }
        
        do {
            let parts = input.split(separator: " ")
            guard let command = parts.first else { return }
            
            var completionCommand = ""
            
            switch String(command) {
            case "cd":
                let path = parts.count > 1 ? String(parts[1]) : ""
                let dirPath = path.isEmpty ? "." : path.hasSuffix("/") ? path : (path.contains("/") ? String(path.split(separator: "/").dropLast().joined(separator: "/")) + "/" : ".")
                completionCommand = "ls -1 \"\(dirPath)\" 2>/dev/null | head -10"
                
            case "mv", "cp", "rm", "cat", "less", "more", "nano", "vim", "emacs":
                let path = parts.count > 1 ? String(parts.last!) : ""
                let dirPath = path.isEmpty ? "." : path.hasSuffix("/") ? path : (path.contains("/") ? String(path.split(separator: "/").dropLast().joined(separator: "/")) + "/" : ".")
                completionCommand = "ls -1 \"\(dirPath)\" 2>/dev/null | head -10"
                
            case "ls":
                let path = parts.count > 1 ? String(parts.last!) : ""
                let dirPath = path.isEmpty ? "." : path.hasSuffix("/") ? path : (path.contains("/") ? String(path.split(separator: "/").dropLast().joined(separator: "/")) + "/" : ".")
                completionCommand = "ls -1 \"\(dirPath)\" 2>/dev/null | head -10"
                
            default:
                return
            }
            
            let result = try await SSHClientActor.shared.execute(completionCommand, on: credential)
            let suggestions = result.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { suggestion in
                    // Reconstruct full command with suggestion
                    if parts.count > 1 {
                        let basePath = String(parts.dropLast().joined(separator: " "))
                        let currentPath = String(parts.last!)
                        if currentPath.contains("/") {
                            let pathComponents = currentPath.split(separator: "/")
                            let basePathPart = pathComponents.dropLast().joined(separator: "/")
                            return "\(basePath) \(basePathPart)/\(suggestion)"
                        } else {
                            return "\(basePath) \(suggestion)"
                        }
                    } else {
                        return "\(command) \(suggestion)"
                    }
                }
            
            await MainActor.run {
                self.completionSuggestions = suggestions
            }
        } catch {
            print("Completion error: \(error)")
        }
    }
}

enum TerminalTheme: String, CaseIterable {
    case dark = "Dark"
    case light = "Light"
    case green = "Matrix"
    case blue = "Ocean"
    
    var backgroundColor: SwiftUI.Color {
        switch self {
        case .dark: return .black
        case .light: return .white
        case .green: return SwiftUI.Color.black
        case .blue: return SwiftUI.Color.blue.opacity(0.1)
        }
    }
    
    var foregroundColor: SwiftUI.Color {
        switch self {
        case .dark: return .white
        case .light: return .black
        case .green: return .green
        case .blue: return .blue
        }
    }
}

struct TerminalSettingsView: View {
    @Binding var useVolumeButtons: Bool
    @Binding var terminalTheme: TerminalTheme
    @Binding var fontSize: Double
    var view: SSHTerminalView?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $terminalTheme) {
                        ForEach(TerminalTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 8...24, step: 1) {
                            Text("Font Size")
                        }
                    }
                }
                
                Section("Controls") {
                    Toggle("Volume Button Control", isOn: $useVolumeButtons)
                    
                    Text("When enabled, volume buttons control terminal arrow keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("About") {
                    HStack {
                        Text("Terminal Engine")
                        Spacer()
                        Text("SwiftTerm")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Completion")
                        Spacer()
                        Text("Smart Context-Aware")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Terminal Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack{
        RemoteTerminalView()
    }
}
