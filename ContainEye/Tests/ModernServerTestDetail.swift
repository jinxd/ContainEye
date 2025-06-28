//
//  ModernServerTestDetail.swift
//  ContainEye
//
//  Created by Claude on 6/26/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import KeychainAccess

struct ModernServerTestDetail: View {
    @BlackbirdLiveModel var test: ServerTest?
    @Environment(\.blackbirdDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    @Environment(\.namespace) var namespace
    
    @State private var isEditing = false
    @State private var isRunning = false
    @State private var showingDeleteConfirmation = false
    
    // Edit states
    @State private var editTitle = ""
    @State private var editCommand = ""
    @State private var editExpectedOutput = ""
    @State private var editNotes = ""
    @State private var editCredentialKey = ""
    
    // AI assistance
    @State private var showingAIAssistant = false
    @State private var aiPrompt = ""
    
    var body: some View {
        if let test {
                ScrollView {
                    LazyVStack {
                        // Header section
                        testHeaderSection(test: test)
                        
                        // Status section
                        testStatusSection(test: test)
                        
                        // Configuration section
                        testConfigurationSection(test: test)
                        
                        // Output section
                        if let output = test.output {
                            testOutputSection(output: output, test: test)
                        }
                        
                        // Actions section
                        testActionsSection(test: test)
                    }
                    .padding()
                }
                .navigationTitle(isEditing ? "Edit Test" : test.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            if !isEditing {
                                Button {
                                    showingAIAssistant = true
                                } label: {
                                    Image(systemName: "wand.and.sparkles")
                                        .foregroundStyle(.blue)
                                }
                            }
                            
                            Button(isEditing ? "Save" : "Edit") {
                                if isEditing {
                                    saveChanges(test: test)
                                } else {
                                    startEditing(test: test)
                                }
                            }
                            .fontWeight(.medium)
                        }
                    }
                }
            .sheet(isPresented: $showingAIAssistant) {
                AIAssistantView(test: test, prompt: $aiPrompt)
                    .confirmator()
            }
            .alert("Delete Test", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTest(test: test)
                }
            } message: {
                Text("Are you sure you want to delete \"\(test.title)\"? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Header Section
    
    private func testHeaderSection(test: ServerTest) -> some View {
        VStack {
            HStack {
                ZStack {
                    Circle()
                        .fill(test.status.color.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    if test.status == .running || isRunning {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(test.status.color)
                    } else {
                        Image(systemName: test.status.icon)
                            .font(.system(size: 24))
                            .foregroundStyle(test.status.color)
                    }
                }
                
                VStack(alignment: .leading) {
                    if isEditing {
                        TextField("Test Name", text: $editTitle)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .textFieldStyle(ModernEditFieldStyle())
                    } else {
                        Text(test.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack {
                        Image(systemName: "server.rack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(serverDisplayName(for: test.credentialKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            if let lastRun = test.lastRun {
                HStack {
                    Text("Last run:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(lastRun, style: .relative)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text("ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(lastRun, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Status Section
    
    private func testStatusSection(test: ServerTest) -> some View {
        VStack(alignment: .leading) {
            Text("Status")
                .font(.headline)
                .fontWeight(.medium)
            
            HStack {
                VStack(alignment: .leading) {
                    Text(test.status.displayText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(test.status.color)
                    
                    Text("Current test status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                AsyncButton {
                    await runTest(test: test)
                } label: {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.caption)
                        }
                        Text("Run Test")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(isRunning || test.status == .running || isEditing)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Configuration Section
    
    private func testConfigurationSection(test: ServerTest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack {
                // Server selection (only in edit mode)
                if isEditing {
                    VStack(alignment: .leading) {
                        Text("Server")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Picker("Server", selection: $editCredentialKey) {
                            Text("Do not execute")
                                .tag("-")
                            
                            let allKeys = keychain().allKeys()
                            let credentials = allKeys.compactMap { keychain().getCredential(for: $0) }
                            ForEach(credentials, id: \.key) { credential in
                                Text(credential.label)
                                    .tag(credential.key)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.blue)
                    }
                }
                
                // Command
                VStack(alignment: .leading) {
                    Text("Command")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    if isEditing {
                        TextField("Enter command to execute", text: $editCommand, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(ModernEditFieldStyle())
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text(test.command)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = test.command
                                }
                            }
                    }
                }
                
                // Expected Output
                VStack(alignment: .leading) {
                    Text("Expected Output")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    if isEditing {
                        TextField("Expected output or regex pattern", text: $editExpectedOutput, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(ModernEditFieldStyle())
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text(test.expectedOutput)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = test.expectedOutput
                                }
                            }
                    }
                }
                
                // Notes
                VStack(alignment: .leading) {
                    Text("Notes")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    if isEditing {
                        TextField("Add notes about this test", text: $editNotes, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(ModernEditFieldStyle())
                    } else {
                        Text(test.notes?.isEmpty == false ? test.notes! : "No notes")
                            .font(.body)
                            .foregroundStyle(test.notes?.isEmpty == false ? .primary : .secondary)
                            .italic(test.notes?.isEmpty != false)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Output Section
    
    private func testOutputSection(output: String, test: ServerTest) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Last Output")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = output
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            
            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(test.status == .success ? .green.opacity(0.05) : test.status == .failed ? .red.opacity(0.05) : .blue.opacity(0.05))
                    .stroke(test.status == .success ? .green.opacity(0.3) : test.status == .failed ? .red.opacity(0.3) : .blue.opacity(0.3), lineWidth: 1)
            )
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Actions Section
    
    private func testActionsSection(test: ServerTest) -> some View {
        VStack(spacing: 12) {
            if !isEditing {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Test")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func serverDisplayName(for credentialKey: String) -> String {
        if credentialKey == "-" {
            return "Do not execute"
        } else if credentialKey.isEmpty {
            return "Local (URLs only)"
        } else {
            let credential = keychain().getCredential(for: credentialKey)
            return credential?.label ?? "Unknown Server"
        }
    }
    
    private func startEditing(test: ServerTest) {
        editTitle = test.title
        editCommand = test.command
        editExpectedOutput = test.expectedOutput
        editNotes = test.notes ?? ""
        editCredentialKey = test.credentialKey
        
        withAnimation(.easeInOut) {
            isEditing = true
        }
    }
    
    private func saveChanges(test: ServerTest) {
        Task {
            var updatedTest = test
            updatedTest.title = editTitle
            updatedTest.command = editCommand
            updatedTest.expectedOutput = editExpectedOutput
            updatedTest.notes = editNotes.isEmpty ? nil : editNotes
            updatedTest.credentialKey = editCredentialKey
            
            try await updatedTest.write(to: db!)
            
            await MainActor.run {
                withAnimation(.easeInOut) {
                    isEditing = false
                }
            }
        }
    }
    
    private func runTest(test: ServerTest) async {
        isRunning = true
        var updatedTest = test
        
        do {
            updatedTest.status = .running
            try await updatedTest.write(to: db!)
            updatedTest = await updatedTest.test()
            
            #if !os(macOS)
            if updatedTest.status == .failed {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            #endif
            
            try await updatedTest.write(to: db!)
            try await updatedTest.testIntent().donate()
        } catch {
            if updatedTest.status == .running {
                updatedTest.status = .failed
                try? await updatedTest.write(to: db!)
            }
        }
        
        isRunning = false
    }
    
    private func deleteTest(test: ServerTest) {
        Task {
            try await test.delete(from: db!)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Supporting Views

struct ModernEditFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue.opacity(0.3), lineWidth: 1)
            )
    }
}

struct AIAssistantView: View {
    let test: ServerTest
    @Binding var prompt: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blackbirdDatabase) private var db
    @FocusState private var isTextFieldFocused: Bool
    @State private var isGenerating = false
    @State private var currentHistory = [[String: String]]()
    @State private var improvedTest: ServerTest?
    @State private var showingPreview = false
    
    var body: some View {
        NavigationView {
            VStack {
                if let improvedTest, showingPreview {
                    testPreviewSection(improvedTest)
                } else {
                    promptInputSection
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if showingPreview {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        AsyncButton("Apply Changes") {
                            await applyImprovedTest()
                        }
                        .fontWeight(.medium)
                    }
                }
            }
        }
    }
    
    private var promptInputSection: some View {
        VStack {
            // Header
            VStack {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                
                Text("AI Test Improvement")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Ask AI to help improve your test configuration")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            Spacer()
            
            // Current test info
            VStack(alignment: .leading) {
                Text("Current Test")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text(test.title)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text(test.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Prompt input
            VStack(alignment: .leading) {
                Text("How would you like to improve this test?")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                HStack {
                    TextField("e.g. Make it more reliable, add error handling, optimize performance...", text: $prompt, axis: .vertical)
                        .textFieldStyle(ModernEditFieldStyle())
                        .focused($isTextFieldFocused)
                        .lineLimit(2...4)
                    
                    AsyncButton {
                        await generateImprovedTest()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    private func testPreviewSection(_ improvedTest: ServerTest) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                // Header
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    
                    Text("Test Improved!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Review the AI's improvements below")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Comparison sections
                comparisonSection(
                    title: "Test Name",
                    original: test.title,
                    improved: improvedTest.title
                )
                
                comparisonSection(
                    title: "Command",
                    original: test.command,
                    improved: improvedTest.command
                )
                
                comparisonSection(
                    title: "Expected Output",
                    original: test.expectedOutput,
                    improved: improvedTest.expectedOutput
                )
                
                if let improvedNotes = improvedTest.notes, !improvedNotes.isEmpty {
                    comparisonSection(
                        title: "Notes",
                        original: test.notes ?? "No notes",
                        improved: improvedNotes
                    )
                }
            }
            .padding()
        }
    }
    
    private func comparisonSection(title: String, original: String, improved: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading) {
                if original != improved {
                    // Show changes
                    VStack(alignment: .leading) {
                        Text("Original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(original)
                            .font(title == "Command" || title == "Expected Output" ? .system(.body, design: .monospaced) : .body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.red.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Improved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(improved)
                            .font(title == "Command" || title == "Expected Output" ? .system(.body, design: .monospaced) : .body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.green.opacity(0.3), lineWidth: 1)
                            )
                    }
                } else {
                    // No changes
                    VStack(alignment: .leading) {
                        Text("Unchanged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(original)
                            .font(title == "Command" || title == "Expected Output" ? .system(.body, design: .monospaced) : .body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(.bottom)
    }
    
    private func generateImprovedTest() async {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isGenerating = true
        
        let improvePrompt = """
        I need to improve this existing test:
        
        Title: \(test.title)
        Command: \(test.command)
        Expected Output: \(test.expectedOutput)
        Notes: \(test.notes ?? "No notes")
        
        Improvement request: \(prompt)
        
        Please provide an improved version of this test. Make sure the command is reliable and the expected output pattern will work correctly.
        """
        
        let dirtyLlmOutput = await LLM.generate(
            prompt: improvePrompt,
            systemPrompt: LLM.addTestSystemPrompt,
            history: currentHistory
        )
        
        let llmOutput = LLM.cleanLLMOutput(dirtyLlmOutput.output)
        
        do {
            let output = try JSONDecoder().decode(
                LLM.Output.self,
                from: Data(llmOutput.utf8)
            )
            
            var improved = test
            improved.title = output.content.title
            improved.command = output.content.command
            improved.expectedOutput = output.content.expectedOutput
            improved.notes = (test.notes ?? "") + "\n\nAI Improvement: " + prompt
            
            currentHistory = dirtyLlmOutput.history
            improvedTest = improved
            showingPreview = true
        } catch {
            print("Failed to decode LLM output: \(error)")
        }
        
        isGenerating = false
    }
    
    private func applyImprovedTest() async {
        guard let improvedTest else { return }
        
        do {
            try await improvedTest.write(to: db!)
            dismiss()
        } catch {
            print("Failed to save improved test: \(error)")
        }
    }
}

#Preview {
    let db = try! Blackbird.Database.inMemoryDatabase()
    let test = ServerTest(
        id: 1,
        title: "Disk Space Check",
        notes: "Monitor available disk space on the root partition",
        credentialKey: "server1",
        command: "df -h / | grep -E '^/' | awk '{print $5}' | sed 's/%//'",
        expectedOutput: "^[0-9]{1,2}$",
        lastRun: Date().addingTimeInterval(-3600),
        status: .success,
        output: "15"
    )
    
    Task {
        try await test.write(to: db)
    }
    
    return ModernServerTestDetail(test: test.liveModel)
        .environment(\.blackbirdDatabase, db)
}
