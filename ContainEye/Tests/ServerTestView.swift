//
//  ServerTestView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/23/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import UserNotifications
import KeychainAccess

struct ServerTestView: View {
    @Environment(\.blackbirdDatabase) var db
    @BlackbirdLiveModels({
        try await ServerTest.read(
            from: $0,
            matching: \.$credentialKey != "-",
            orderBy: .descending(\.$lastRun)
        )
    }) var activeTests
    @BlackbirdLiveModels({
        try await ServerTest.read(
            from: $0,
            matching: \.$credentialKey == "-",
            orderBy: .descending(\.$lastRun)
        )
    }) var suggestedTests
    @BlackbirdLiveModels({
        try await Snippet.read(
            from: $0,
            matching: .all,
            orderBy: .descending(\.$lastUse)
        )
    }) var snippets
    @Environment(\.scenePhase) var scenePhase
    @State private var notificationsAllowed = true
    @Environment(\.namespace) var namespace
    @State private var isRunningAllTests = false
    @State private var showingAddTest = false
    
    var overallStatus: ServerTest.TestStatus {
        let tests = activeTests.results
        if tests.isEmpty { return .notRun }
        if tests.contains(where: { $0.status == .running }) { return .running }
        if tests.contains(where: { $0.status == .failed }) { return .failed }
        if tests.allSatisfy({ $0.status == .success }) { return .success }
        return .notRun
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack {
                    if activeTests.didLoad {
                        // Header section with stats
                        testsHeaderSection
                        
                        // Quick actions
                        quickActionsSection
                        
                        // Tests grid
                        if activeTests.results.isEmpty {
                            emptyActiveTestsState
                        } else {
                            activeTestsGrid
                        }
                        
                        // Snippets section
                        snippetsSection

                        // Suggested tests section
                        if !suggestedTests.results.isEmpty {
                            suggestedTestsSection
                        }
                    } else {
                        loadingState
                    }
                }
                .padding()
                .padding(.top, 10)
            }
            .navigationTitle("Code")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddTest = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddTest) {
            NavigationView {
                AddTestFlowView()
                    .navigationTitle("Create Test")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(role: .cancel) {
                                showingAddTest = false
                            }
                        }
                    }
            }
            .confirmator()
        }
        .onAppear {
            checkNotificationPermissions()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                checkNotificationPermissions()
            }
        }
    }
    
    private var testsHeaderSection: some View {
        VStack {
            // Status indicator
            HStack {
                ZStack {
                    Circle()
                        .fill(overallStatus.color.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: overallStatus.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(overallStatus.color)
                }
                
                VStack(alignment: .leading) {
                    Text("Test Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(overallStatus.displayText)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(overallStatus.color)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Total Tests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(activeTests.results.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
            
            // Metrics row
            HStack {
                TestMetricCard(
                    title: "Passing",
                    count: activeTests.results.filter { $0.status == .success }.count,
                    color: .green,
                    icon: "checkmark.circle.fill"
                )
                
                TestMetricCard(
                    title: "Failing",
                    count: activeTests.results.filter { $0.status == .failed }.count,
                    color: .red,
                    icon: "xmark.circle.fill"
                )
                
                TestMetricCard(
                    title: "Running",
                    count: activeTests.results.filter { $0.status == .running }.count,
                    color: .orange,
                    icon: "clock.fill"
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var quickActionsSection: some View {
        HStack {
            // Run all tests button
            AsyncButton {
                await runAllTests()
            } label: {
                HStack {
                    if isRunningAllTests {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isRunningAllTests ? "Running..." : "Run All Tests")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(activeTests.results.isEmpty || isRunningAllTests)
            
            // Add test button
            Button {
                showingAddTest = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Test")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
    }
    
    private var activeTestsGrid: some View {
        VStack(alignment: .leading) {
            Text("Active Tests")
                .font(.headline)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
            ], spacing: 12) {
                ForEach(activeTests.results) { test in
                    TestCard(test: test)
                        .matchedTransitionSource(id: test.id, in: namespace!)
                }
            }
        }
    }

    private var snippetsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Snippets")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(snippets.results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snippets.results.isEmpty {
                Text("No snippets yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
                ], spacing: 12) {
                    ForEach(snippets.results) { snippet in
                        NavigationLink(value: snippet) {
                            SnippetCard(snippet: snippet)
                                .matchedTransitionSource(id: snippet.id, in: namespace!)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var suggestedTestsSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Suggested Tests")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(suggestedTests.results.count) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)
            ], spacing: 12) {
                ForEach(suggestedTests.results.prefix(6)) { test in
                    SuggestedTestCard(test: test)
                }
            }
        }
    }
    
    private var emptyActiveTestsState: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "testtube.2")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }
            
            VStack {
                Text("No Tests Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create your first test to monitor server health and performance")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showingAddTest = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Create Your First Test")
                        .fontWeight(.medium)
                }
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 40)
    }
    
    private var loadingState: some View {
        VStack {
            ProgressView()
                .controlSize(.large)
            
            Text("Loading Tests...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 60)
    }
    
    private func runAllTests() async {
        isRunningAllTests = true
        
        for test in activeTests.results {
            var test = test
            do {
                test.status = .running
                try await test.write(to: db!)
                test = await test.test()
                
#if !os(macOS)
                if test.status == .failed {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
#endif
                
                try await test.write(to: db!)
                try await test.testIntent().donate()
            } catch {
                if test.status == .running {
                    test.status = .failed
                    try? await test.write(to: db!)
                }
            }
        }
        
        isRunningAllTests = false
    }
    
    private func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
            Task{@MainActor in
                notificationsAllowed = allowed
            }
        }
    }
}

// MARK: - Supporting Views

struct TestMetricCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            VStack(alignment: .leading) {
                Text("\(count)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TestCard: View {
    let test: ServerTest
    @Environment(\.blackbirdDatabase) var db
    @State private var isRunning = false
    
    var body: some View {
        Menu {
            AsyncButton("Run Test", systemImage: "play.fill") {
                await runTest()
            }

            NavigationLink(value: test) {
                Label("Edit Test", systemImage: "pencil")
            }

            Divider()

            Button("Delete Test", systemImage: "trash", role: .destructive) {
                deleteTest()
            }
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(test.status.color.opacity(0.1))
                            .frame(width: 32, height: 32)

                        if test.status == .running || isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(test.status.color)
                        } else {
                            Image(systemName: test.status.icon)
                                .font(.caption)
                                .foregroundStyle(test.status.color)
                        }
                    }

                    Spacer()
                }

                VStack(alignment: .leading) {
                    Text(test.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(2)

                    if let lastRun = test.lastRun {
                        Text("Last run: \(lastRun, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never run")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .multilineTextAlignment(.leading)
        .buttonStyle(.plain)
    }
    
    private func runTest() async {
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
    
    private func deleteTest() {
        Task {
            try await test.delete(from: db!)
        }
    }
}

struct SnippetCard: View {
    let snippet: Snippet
    @Environment(\.blackbirdDatabase) var db
    @State private var isRunning = false
    @State private var terminalOutput = ""
    @State private var showTerminal = false

    var body: some View {
        Menu {
            AsyncButton("Run Snippet", systemImage: "play.fill") {
                await runSnippet()
            }

            NavigationLink(value: snippet) {
                Label("Edit Snippet", systemImage: "pencil")
            }

            Divider()

            Button("Delete Snippet", systemImage: "trash", role: .destructive) {
                deleteSnippet()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.12))
                            .frame(width: 32, height: 32)

                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "terminal")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Spacer()
                }

                Text(snippet.comment.isEmpty ? "Snippet" : snippet.comment)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(snippet.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(serverDisplayText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if showTerminal {
                    ScrollView {
                        Text(terminalOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 90)
                    .padding(8)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.green)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.blue.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .multilineTextAlignment(.leading)
        .buttonStyle(.plain)
    }

    private var serverDisplayText: String {
        let key = snippet.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return "Global snippet (no server)" }
        return keychain().getCredential(for: key)?.label ?? "Server key: \(key)"
    }

    private func runSnippet() async {
        let key = snippet.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            terminalOutput = "Snippet has no server assigned. Create it for a specific server first."
            showTerminal = true
            return
        }
        guard let credential = keychain().getCredential(for: key) else {
            terminalOutput = "Server not found for key \(key)."
            showTerminal = true
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            let output = try await SSHClientActor.shared.execute(snippet.command, on: credential)
            terminalOutput = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no output)" : output
            showTerminal = true

            var updated = snippet
            updated.lastUse = .now
            try? await updated.write(to: db!)
        } catch {
            terminalOutput = "Error: \(error.localizedDescription)"
            showTerminal = true
        }
    }

    private func deleteSnippet() {
        Task {
            try? await snippet.delete(from: db!)
        }
    }
}

struct SnippetDetailView: View {
    @BlackbirdLiveModel var snippet: Snippet?
    @Environment(\.blackbirdDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    @State private var contextStore = AgenticScreenContextStore.shared

    @State private var isEditing = false
    @State private var editCommand = ""
    @State private var editComment = ""
    @State private var editCredentialKey = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        if let snippet {
            ScrollView {
                VStack(spacing: 12) {
                    headerSection(snippet)
                    configurationSection(snippet)
                    actionsSection(snippet)
                }
                .padding()
            }
            .navigationTitle(isEditing ? "Edit Snippet" : (snippet.comment.isEmpty ? "Snippet" : snippet.comment))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            saveChanges(snippet)
                        } else {
                            startEditing(snippet)
                        }
                    }
                    .fontWeight(.medium)
                }
            }
            .onAppear {
                updateAgenticContext(snippet: snippet, useDraft: isEditing)
            }
            .onChange(of: isEditing) {
                updateAgenticContext(snippet: snippet, useDraft: isEditing)
            }
            .onChange(of: editCommand) {
                if isEditing { updateAgenticContext(snippet: snippet, useDraft: true) }
            }
            .onChange(of: editComment) {
                if isEditing { updateAgenticContext(snippet: snippet, useDraft: true) }
            }
            .onChange(of: editCredentialKey) {
                if isEditing { updateAgenticContext(snippet: snippet, useDraft: true) }
            }
            .safeAreaInset(edge: .bottom) {
                AgenticDetailFABInset()
            }
            .alert("Delete Snippet", isPresented: $showingDeleteConfirmation) {
                Button(role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteSnippet(snippet)
                }
            } message: {
                Text("Are you sure you want to delete this snippet?")
            }
        }
    }

    private func headerSection(_ snippet: Snippet) -> some View {
        VStack {
            HStack {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.12))
                        .frame(width: 60, height: 60)
                    Image(systemName: "terminal")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading) {
                    if isEditing {
                        TextField("Snippet title/comment", text: $editComment)
                            .textFieldStyle(EditFieldStyle())
                            .font(.title2)
                            .fontWeight(.semibold)
                    } else {
                        Text(snippet.comment.isEmpty ? "Snippet" : snippet.comment)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    Text(serverLabel(for: isEditing ? editCredentialKey : (snippet.credentialKey ?? "")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func configurationSection(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.headline)
                .fontWeight(.medium)

            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Picker("Server", selection: $editCredentialKey) {
                        Text("Global (no server)")
                            .tag("")
                        let credentials = keychain().allKeys().compactMap { keychain().getCredential(for: $0) }
                        ForEach(credentials, id: \.key) { credential in
                            Text(credential.label)
                                .tag(credential.key)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                if isEditing {
                    TextField("Enter command", text: $editCommand, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(EditFieldStyle())
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text(snippet.command)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if !isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Used")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text("\(snippet.lastUse, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionsSection(_ snippet: Snippet) -> some View {
        VStack(spacing: 12) {
            if !isEditing {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Snippet")
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

    private func startEditing(_ snippet: Snippet) {
        editComment = snippet.comment
        editCommand = snippet.command
        editCredentialKey = snippet.credentialKey ?? ""
        withAnimation(.easeInOut) {
            isEditing = true
        }
    }

    private func saveChanges(_ snippet: Snippet) {
        Task {
            var updated = snippet
            updated.comment = editComment
            updated.command = editCommand
            updated.credentialKey = editCredentialKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editCredentialKey
            try await updated.write(to: db!)
            await MainActor.run {
                withAnimation(.easeInOut) {
                    isEditing = false
                }
            }
        }
    }

    private func deleteSnippet(_ snippet: Snippet) {
        Task {
            try await snippet.delete(from: db!)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func serverLabel(for credentialKey: String) -> String {
        let key = credentialKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            return "Global (no server)"
        }
        return keychain().getCredential(for: key)?.label ?? "Unknown server"
    }

    private func updateAgenticContext(snippet: Snippet, useDraft: Bool) {
        let command = useDraft ? editCommand : snippet.command
        let comment = useDraft ? editComment : snippet.comment
        let credential = useDraft ? editCredentialKey : (snippet.credentialKey ?? "")
        let server = serverLabel(for: credential)
        contextStore.set(
            chatTitle: "Edit Snippet \(snippet.id)",
            draftMessage: """
            Edit this existing snippet.
            - id: \(snippet.id)
            - server: \(server)
            - command: \(command)
            - comment: \(comment.isEmpty ? "(none)" : comment)

            Requested changes:
            """
        )
    }
}




#Preview {
    let db = try! Blackbird.Database.inMemoryDatabase()
    let test1 = ServerTest(id: 1, title: "Disk Space Check", credentialKey: "server1", command: "df -h", expectedOutput: "Available", status: .success)
    let test2 = ServerTest(id: 2, title: "Memory Usage", credentialKey: "server1", command: "free -m", expectedOutput: "free", status: .failed)
    let test3 = ServerTest(id: 3, title: "Service Status", credentialKey: "server2", command: "systemctl status nginx", expectedOutput: "active", status: .running)
    let suggestion = ServerTest(id: 4, title: "HTTP Health Check", credentialKey: "-", command: "curl -f http://localhost", expectedOutput: "200", status: .notRun)
    
    Task {
        try await test1.write(to: db)
        try await test2.write(to: db)
        try await test3.write(to: db)
        try await suggestion.write(to: db)
    }
    
    return ServerTestView()
        .environment(\.blackbirdDatabase, db)
}
