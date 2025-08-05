//
//  TerminalView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/13/25.
//

import SwiftUI
import SwiftTerm
import Blackbird

struct RemoteTerminalView: View {
    @BlackbirdLiveModels({try await Server.read(from: $0, matching: .all)}) var servers
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


                    // Real-time completion suggestions without polling
                    CompletionView(
                        terminalView: view,
                        history: history,
                        completionSuggestions: completionSuggestions,
                        isLoadingCompletion: isLoadingCompletion,
                        credential: credential,
                        loadCompletionSuggestions: loadCompletionSuggestions
                    )
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
                                ConfirmatorManager.shared.showError(error, title: "Terminal Connection Failed")
                            }
                            let terminalView = SSHTerminalView(
                                credential: credential.toSwiftTermCredential(),
                                useVolumeButtons: useVolumeButtons
                            )
                            
                            // Set up directory tracking callback
                            terminalView.setDirectoryChangeCallback { command, swiftTermCred in
                                do {
                                    // Convert SwiftTerm.Credential back to ContainEye.Credential
                                    let containEyeCred = swiftTermCred.toContainEyeCredential()
                                    return try await SSHClientActor.shared.execute(command, on: containEyeCred)
                                } catch {
                                    return nil
                                }
                            }
                            
                            view = terminalView
                        }
                        .trackView("terminal/connecting")
                }
            } else {
                let keychain = keychain()
                let credentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
                
                if credentials.isEmpty {
                    ContentUnavailableView("You don't have any servers yet.", systemImage: "terminal")
                        .trackView("terminal/no-servers")
                } else {
                    VStack {
                        VStack {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.green)
                                .symbolEffect(.pulse)
                            
                            Text("Connect to Terminal")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Text("Select a server to open an SSH terminal session")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ]) {
                            ForEach(credentials, id: \.key) { credential in
                                Button {
                                    self.credential = credential
                                } label: {
                                    VStack {
                                        if let server = servers.results.first(where: { $0.credentialKey == credential.key }) {
                                            OSIconView(server: server, size: 32)
                                        } else {
                                            Image(systemName: "terminal")
                                                .font(.title)
                                                .foregroundStyle(.green)
                                        }
                                        
                                        Text(credential.label)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                        
                                        Text(credential.host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.green.opacity(0.05))
                                            .stroke(.green.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .trackView("terminal/select-server")
                }
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
        guard let credential = credential, 
              let terminalView = view,
              !isLoadingCompletion else { return }
        
        isLoadingCompletion = true
        defer { isLoadingCompletion = false }
        
        do {
            let parts = input.split(separator: " ")
            guard let command = parts.first else { return }
            
            // Get current directory from terminal for context-aware completions
            let currentDir = terminalView.currentDirectory
            var completionCommand = ""
            
            switch String(command) {
            case "cd":
                let path = parts.count > 1 ? String(parts[1]) : ""
                let (searchDir, prefix) = resolveCompletionPath(path: path, currentDir: currentDir)
                print("  CD Path Resolution: '\(path)' -> searchDir: '\(searchDir)', prefix: '\(prefix)'")
                if prefix.isEmpty {
                    completionCommand = "ls -1d \"\(searchDir)\"/*/ 2>/dev/null | xargs -n1 basename | head -15"
                } else {
                    completionCommand = "ls -1d \"\(searchDir)\"/\(prefix)*/ 2>/dev/null | xargs -n1 basename | head -15"
                }
                
            case "mv", "cp", "rm", "cat", "less", "more", "nano", "vim", "emacs", "tail", "head":
                let path = parts.count > 1 ? String(parts.last!) : ""
                let (searchDir, prefix) = resolveCompletionPath(path: path, currentDir: currentDir)
                print("  File Path Resolution: '\(path)' -> searchDir: '\(searchDir)', prefix: '\(prefix)'")
                if prefix.isEmpty {
                    completionCommand = "ls -1a \"\(searchDir)\" 2>/dev/null | grep -v '^\\.$' | grep -v '^\\.\\.$' | head -15"
                } else {
                    completionCommand = "ls -1a \"\(searchDir)\" 2>/dev/null | grep '^\\(\(prefix)\\)' | head -15"
                }
                
            case "ls":
                let path = parts.count > 1 ? String(parts.last!) : ""
                let (searchDir, prefix) = resolveCompletionPath(path: path, currentDir: currentDir)
                print("  LS Path Resolution: '\(path)' -> searchDir: '\(searchDir)', prefix: '\(prefix)'")
                if prefix.isEmpty {
                    completionCommand = "ls -1a \"\(searchDir)\" 2>/dev/null | grep -v '^\\.$' | grep -v '^\\.\\.$' | head -15"
                } else {
                    completionCommand = "ls -1a \"\(searchDir)\" 2>/dev/null | grep '^\\(\(prefix)\\)' | head -15"
                }
                
            case "grep", "find":
                // For search commands, suggest recently used files
                completionCommand = "ls -1 \"\(currentDir)\" 2>/dev/null | head -10"
                
            case "chmod", "chown":
                // For permission commands, show files and directories
                let path = parts.count > 1 ? String(parts.last!) : ""
                let (searchDir, prefix) = resolveCompletionPath(path: path, currentDir: currentDir)
                print("  Permission Path Resolution: '\(path)' -> searchDir: '\(searchDir)', prefix: '\(prefix)'")
                if prefix.isEmpty {
                    completionCommand = "ls -1a \"\(searchDir)\" 2>/dev/null | grep -v '^\\.$' | grep -v '^\\.\\.$' | head -10"
                } else {
                    completionCommand = "ls -1a \"\(searchDir)\" 2>/dev/null | grep '^\\(prefix)' | head -10"
                }
                
            default:
                // For unknown commands, show files in current directory
                completionCommand = "ls -1 \"\(currentDir)\" 2>/dev/null | head -5"
            }
            
            print("🔍 COMPLETION DEBUG:")
            print("  Input: '\(input)'")
            print("  Command: '\(command)'")
            print("  Current Dir: '\(currentDir)'")
            print("  Completion Command: '\(completionCommand)'")
            
            let result = try await SSHClientActor.shared.execute(completionCommand, on: credential)
            print("  Raw Result: '\(result)'")
            
            let suggestions = result.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
                .map { suggestion in
                    // Reconstruct full command with suggestion
                    let reconstructed = reconstructCommand(originalInput: input, suggestion: suggestion, command: String(command))
                    print("  Suggestion: '\(suggestion)' -> '\(reconstructed)'")
                    return reconstructed
                }
            
            print("  Final Suggestions: \(suggestions)")
            
            await MainActor.run {
                self.completionSuggestions = suggestions
            }
        } catch {
            // Fallback: try simple directory listing
            do {
                let result = try await SSHClientActor.shared.execute("ls -1a 2>/dev/null | head -10", on: credential)
                let fallbackSuggestions = result.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
                    .map { "\(input) \($0)" }
                
                await MainActor.run {
                    self.completionSuggestions = fallbackSuggestions
                }
            } catch {
                print("Completion error: \(error)")
            }
        }
    }
    
    /// Resolve the completion path and extract the search directory and filename prefix
    private func resolveCompletionPath(path: String, currentDir: String) -> (searchDir: String, prefix: String) {
        if path.isEmpty {
            // No path specified, search in current directory
            return (currentDir, "")
        }
        
        if path.hasPrefix("/") {
            // Absolute path
            if path.hasSuffix("/") {
                // Path ends with /, search in that directory
                return (path, "")
            } else if path.contains("/") {
                // Path contains /, extract directory and prefix
                let components = path.split(separator: "/")
                let dirComponents = components.dropLast()
                let prefix = String(components.last ?? "")
                let searchDir = "/" + dirComponents.joined(separator: "/")
                return (searchDir.isEmpty ? "/" : searchDir, prefix)
            } else {
                // Single item in root
                return ("/", path)
            }
        } else {
            // Relative path
            if path.hasSuffix("/") {
                // Relative path ends with /, search in that subdirectory
                let fullPath = currentDir.hasSuffix("/") ? currentDir + path : currentDir + "/" + path
                return (fullPath, "")
            } else if path.contains("/") {
                // Relative path with /, extract directory and prefix
                let components = path.split(separator: "/")
                let dirComponents = components.dropLast()
                let prefix = String(components.last ?? "")
                let subPath = dirComponents.joined(separator: "/")
                let fullPath = currentDir.hasSuffix("/") ? currentDir + subPath : currentDir + "/" + subPath
                return (fullPath, prefix)
            } else {
                // Simple filename prefix in current directory
                return (currentDir, path)
            }
        }
    }
    
    /// Reconstruct the command with the completion suggestion
    private func reconstructCommand(originalInput: String, suggestion: String, command: String) -> String {
        let parts = originalInput.split(separator: " ")
        
        if parts.count == 1 {
            // Just the command, add suggestion
            return "\(command) \(suggestion)"
        } else {
            // Replace the last part with the suggestion
            let commandWithArgs = parts.dropLast().joined(separator: " ")
            let lastPart = String(parts.last ?? "")
            
            if lastPart.contains("/") {
                // Path completion - replace filename part
                let pathComponents = lastPart.split(separator: "/")
                if pathComponents.count > 1 {
                    let pathBase = pathComponents.dropLast().joined(separator: "/")
                    return "\(commandWithArgs) \(pathBase)/\(suggestion)"
                }
            }
            
            return "\(commandWithArgs) \(suggestion)"
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

struct CompletionView: View {
    let terminalView: SSHTerminalView
    let history: [String]
    let completionSuggestions: [String]
    let isLoadingCompletion: Bool
    let credential: Credential
    let loadCompletionSuggestions: (String) async -> Void
    
    @State private var currentInput = ""
    @State private var suggestions: [String] = []
    
    var body: some View {
        HStack {
            ForEach(suggestions.isEmpty ? ["None"] : suggestions, id: \.self) { suggestion in
                Button {
                    terminalView.setCurrentInputLine(suggestion)
                } label: {
                    Text(suggestion)
                        .frame(minWidth: 100)
                        .lineLimit(1)
                        .minimumScaleFactor(0.1)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(suggestion == currentInput ? Color.blue : Color.black)
                .italic(suggestion == "None")
                .disabled(suggestion == "None")
            }
        }
        .padding(.horizontal)
        .font(.title)
        .minimumScaleFactor(0.3)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Check for input changes more frequently but efficiently
            let newInput = terminalView.currentInputLine.trimmingCharacters(in: .whitespaces)
            if newInput != currentInput {
                currentInput = newInput
                updateSuggestions()
            }
        }
    }
    
    private func updateSuggestions() {
        if currentInput.isEmpty {
            suggestions = []
            return
        }
        
        // Get smart completions based on current directory context
        let smartSuggestions = getSmartCompletions(for: currentInput)
        
        if !smartSuggestions.isEmpty {
            suggestions = Array(smartSuggestions.prefix(3))
        } else {
            // Fallback to history-based completions
            let historyMatches = shortestStartingWith(currentInput, in: history, limit: 3)
            suggestions = historyMatches
        }
        
        // Load additional completions asynchronously if needed
        if !isLoadingCompletion {
            Task {
                await loadCompletionSuggestions(currentInput)
            }
        }
    }
    
    private func getSmartCompletions(for input: String) -> [String] {
        let trimmedInput = input.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.isEmpty else { return [] }
        
        let parts = trimmedInput.split(separator: " ")
        guard let command = parts.first else { return [] }
        
        // Smart completion based on command and current directory
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
    
    private func shortestStartingWith(_ prefix: String, in array: [String], limit: Int) -> [String] {
        return array
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
            .sorted { $0.count < $1.count }
            .prefix(limit)
            .map { $0 }
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

// MARK: - Credential Conversion Extensions

extension SwiftTerm.AuthenticationMethod {
    func toContainEyeAuthMethod() -> ContainEye.AuthenticationMethod {
        switch self {
        case .password:
            return .password
        case .privateKey:
            return .privateKey
        case .privateKeyWithPassphrase:
            return .privateKeyWithPassphrase
        }
    }
}

extension ContainEye.AuthenticationMethod {
    func toSwiftTermAuthMethod() -> SwiftTerm.AuthenticationMethod {
        switch self {
        case .password:
            return .password
        case .privateKey:
            return .privateKey
        case .privateKeyWithPassphrase:
            return .privateKeyWithPassphrase
        }
    }
}

extension SwiftTerm.Credential {
    func toContainEyeCredential() -> ContainEye.Credential {
        return ContainEye.Credential(
            key: self.key,
            label: self.label,
            host: self.host,
            port: self.port,
            username: self.username,
            password: self.password,
            authMethod: self.effectiveAuthMethod.toContainEyeAuthMethod(),
            privateKey: self.privateKey,
            passphrase: self.passphrase
        )
    }
}

extension ContainEye.Credential {
    func toSwiftTermCredential() -> SwiftTerm.Credential {
        return SwiftTerm.Credential(
            key: self.key,
            label: self.label,
            host: self.host,
            port: self.port,
            username: self.username,
            password: self.password,
            authMethod: self.effectiveAuthMethod.toSwiftTermAuthMethod(),
            privateKey: self.privateKey,
            passphrase: self.passphrase
        )
    }
}

