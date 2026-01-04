//
//  Confirmator.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/6/25.
//

import SwiftUI
import ButtonKit
import Blackbird

@MainActor @Observable
final class ConfirmatorManager {
    static let shared = ConfirmatorManager()

    var continuation: CheckedContinuation<String, any Error>?
    var question: String?
    var command: String?
    var errorMessage: String?
    var errorTitle: String?

    func ask(_ question: String) async throws -> String {
        self.question = question
        return try await withCheckedThrowingContinuation { con in
            self.continuation = con
        }
    }
    func execute(_ command: String) async throws -> String {
        self.command = command
        return try await withCheckedThrowingContinuation { con in
            self.continuation = con
        }
    }
    
    /// Show error message globally, filtering out CancellationError
    func showError(_ error: Error, title: String = "Error") {
        // Skip showing CancellationError and similar cancellation-related errors
        if error is CancellationError {
            return
        }
        
        let nsError = error as NSError
        // Skip various cancellation error codes
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return
        }
        
        // Check for string-based cancellation indicators
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("cancel") || errorDescription.contains("cancelled") {
            return
        }
        
        self.errorTitle = title
        self.errorMessage = error.localizedDescription
    }
    
    /// Show custom error message
    func showError(_ message: String, title: String = "Error") {
        self.errorTitle = title
        self.errorMessage = message
    }
    
    /// Clear error state
    func clearError() {
        self.errorMessage = nil
        self.errorTitle = nil
    }
}

// MARK: - Global Error Reporting
extension ConfirmatorManager {
    /// Global error reporting function - use anywhere in the app
    static func reportError(_ error: Error, title: String = "Error") {
        Task { @MainActor in
            shared.showError(error, title: title)
        }
    }
    
    /// Global error reporting function for custom messages
    static func reportError(_ message: String, title: String = "Error") {
        Task { @MainActor in
            shared.showError(message, title: title)
        }
    }
}

// MARK: - Modern Confirmator View

extension View {
    public func confirmator() -> some View {
        overlay(Confirmator())
    }
}

private struct Confirmator: View {
    @State private var confirmator = ConfirmatorManager.shared
    @State private var answer = ""
    @State private var server: Server?
    @BlackbirdLiveModels({
        try await Server.read(
            from: $0,
            matching: .all
        )
    }) var servers
    @Environment(\.blackbirdDatabase) var db
    @FocusState private var focused: Bool
    @State private var commandOutput: String?
    @State private var isAnimatingIn = false
    
    var body: some View {
        Group {
            if confirmator.question != nil || confirmator.command != nil || confirmator.errorMessage != nil {
                ZStack {
                    // Background overlay
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissCurrentDialog()
                        }
                    
                    // Main dialog content
                    VStack(spacing: 0) {
                        if let question = confirmator.question {
                            questionDialog
                        } else if let command = confirmator.command {
                            commandDialog
                        } else if confirmator.errorMessage != nil {
                            errorDialog
                        }
                    }
                    .frame(maxWidth: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                    .scaleEffect(isAnimatingIn ? 1 : 0.95)
                    .opacity(isAnimatingIn ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAnimatingIn)
                    .padding()
                }
                .onAppear {
                    hideKeyboard()
                    withAnimation {
                        isAnimatingIn = true
                    }
                    focused = true
                }
                .onDisappear {
                    isAnimatingIn = false
                }
            }
        }
    }
    
    // MARK: - Question Dialog
    
    private var questionDialog: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                
                Text("Question")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(.top, 20)
            
            // Question content
            VStack(spacing: 16) {
                Text(.init(confirmator.question ?? ""))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .padding()
                    .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .minimumScaleFactor(0.3)

                // Answer input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Response")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        TextField("Type your answer here...", text: $answer, axis: .vertical)
                            .textFieldStyle(ModernDialogTextFieldStyle())
                            .focused($focused)
                            .lineLimit(1...4)
                        
                        Button {
                            submitAnswer()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    cancelDialog()
                }
                .buttonStyle(ModernSecondaryButtonStyle())
                
                Button("Submit") {
                    submitAnswer()
                }
                .buttonStyle(ModernPrimaryButtonStyle())
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Command Dialog
    
    private var commandDialog: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.orange.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                }
                
                Text("Execute Command")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(.top, 20)
            
            // Command content
            VStack(spacing: 16) {
                Text("AI wants to execute this command:")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                // Command display
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Command")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            UIPasteboard.general.string = confirmator.command
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                    }
                    
                    Text(confirmator.command ?? "")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.orange.opacity(0.2), lineWidth: 1)
                        )
                }
                
                // Command output display
                if let commandOutput {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        ScrollView {
                            Text(commandOutput)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .padding()
                        .background(.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.green.opacity(0.2), lineWidth: 1)
                        )
                    }
                } else {
                    // Server selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Server")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Menu {
                            ForEach(servers.results) { server in
                                Button(server.credential?.label ?? "Unknown Server") {
                                    self.server = server
                                }
                            }
                        } label: {
                            HStack {
                                Text(server?.credential?.label ?? "Choose a server")
                                    .foregroundStyle(server != nil ? .primary : .secondary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .task {
                            if server == nil && !servers.results.isEmpty {
                                server = servers.results.first
                            }
                        }
                    }
                }
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    cancelDialog()
                }
                .buttonStyle(ModernSecondaryButtonStyle())
                
                AsyncButton {
                    await executeCommand()
                } label: {
                    Text(commandOutput == nil ? "Execute" : "Submit")
                        .fontWeight(.medium)
                }
                .buttonStyle(ModernPrimaryButtonStyle())
                .disabled(server == nil && commandOutput == nil)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Error Dialog
    
    private var errorDialog: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse.byLayer, options: .repeat(.continuous))
                }
                
                Text(confirmator.errorTitle ?? "Error")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .padding(.top, 20)
            
            // Error content
            VStack(spacing: 16) {
                if let errorMessage = confirmator.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Details")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = errorMessage
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy")
                                }
                                .font(.caption2)
                                .foregroundStyle(.red)
                            }
                        }

                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.red.opacity(0.2), lineWidth: 1)
                    )
                }
            }

            // Actions
            Button("Dismiss") {
                confirmator.clearError()
            }
            .buttonStyle(ModernPrimaryButtonStyle())
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Actions
    
    private func submitAnswer() {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return }
        
        confirmator.continuation?.resume(returning: trimmedAnswer)
        confirmator.continuation = nil
        confirmator.question = nil
        answer.removeAll()
    }
    
    private func cancelDialog() {
        confirmator.continuation?.resume(throwing: CancellationError())
        confirmator.continuation = nil
        confirmator.question = nil
        confirmator.command = nil
        answer.removeAll()
        commandOutput = nil
    }
    
    private func dismissCurrentDialog() {
        if confirmator.errorMessage != nil {
            confirmator.clearError()
        } else {
            cancelDialog()
        }
    }
    
    private func executeCommand() async {
        if let commandOutput {
            // Submit the output
            confirmator.continuation?.resume(returning: commandOutput)
            confirmator.continuation = nil
            confirmator.command = nil
            self.commandOutput = nil
        } else {
            // Execute the command
            guard let server = server,
                  let command = confirmator.command else { return }
            
            do {
                let output = try await server.execute(command).trimmingFromEnd(character: "\n", upto: 2)
                commandOutput = output
            } catch {
                commandOutput = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Custom Button Styles

struct ModernPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.quaternary)
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernDialogTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.blue.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Extension to use Modern Confirmator

extension View {
    public func modernConfirmator() -> some View {
        overlay(Confirmator())
    }
}

#Preview("Question") {
    let _ = ConfirmatorManager.shared.question = "I've detected some Docker containers that aren't running efficiently. Would you like me to help optimize their resource allocation and restart them with better configurations?"
    Confirmator()
}

#Preview("Command") {
    let _ = ConfirmatorManager.shared.command = "docker ps -a --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"
    Confirmator()
}

#Preview("Error") {
    let _ = {
        ConfirmatorManager.shared.errorTitle = "Connection Failed"
        ConfirmatorManager.shared.errorMessage = "Unable to connect to the SSH server. Please check your credentials and network connection, then try again."
    }()
    Confirmator()
}
