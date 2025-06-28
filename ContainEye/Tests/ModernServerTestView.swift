//
//  ModernServerTestView.swift
//  ContainEye
//
//  Created by Claude on 6/26/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import UserNotifications

struct ModernServerTestView: View {
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
    @Environment(\.scenePhase) var scenePhase
    @State private var notificationsAllowed = true
    @Environment(\.namespace) var namespace
    @State private var isRunningAllTests = false
    @State private var selectedFilter: TestFilter = .all
    @State private var showingAddTest = false
    
    enum TestFilter: String, CaseIterable {
        case all = "All"
        case passing = "Passing"
        case failing = "Failing"
        case running = "Running"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .passing: return "checkmark.circle.fill"
            case .failing: return "xmark.circle.fill"
            case .running: return "clock.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .blue
            case .passing: return .green
            case .failing: return .red
            case .running: return .orange
            }
        }
    }
    
    var filteredTests: [ServerTest] {
        switch selectedFilter {
        case .all:
            return activeTests.results
        case .passing:
            return activeTests.results.filter { $0.status == .success }
        case .failing:
            return activeTests.results.filter { $0.status == .failed }
        case .running:
            return activeTests.results.filter { $0.status == .running }
        }
    }
    
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
                        
                        // Filter section
                        if !activeTests.results.isEmpty {
                            filterSection
                        }
                        
                        // Tests grid
                        if filteredTests.isEmpty && selectedFilter != .all {
                            emptyFilteredState
                        } else if activeTests.results.isEmpty {
                            emptyActiveTestsState
                        } else {
                            activeTestsGrid
                        }
                        
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
            .navigationTitle("Tests")
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
                            Button("Cancel") {
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
    
    private var filterSection: some View {
        VStack(alignment: .leading) {
            Text("Filter Tests")
                .font(.headline)
                .foregroundStyle(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(TestFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            filter: filter,
                            isSelected: selectedFilter == filter,
                            count: countForFilter(filter)
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 2)
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
                ForEach(filteredTests) { test in
                    ModernTestCard(test: test)
                        .matchedTransitionSource(id: test.id, in: namespace!)
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
                    ModernSuggestedTestCard(test: test)
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
                
                Image(systemName: "testtube.2.fill")
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
    
    private var emptyFilteredState: some View {
        VStack {
            Image(systemName: selectedFilter.icon)
                .font(.system(size: 32))
                .foregroundStyle(selectedFilter.color)
            
            Text("No \(selectedFilter.rawValue) Tests")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text("Try adjusting your filter or run some tests")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
    
    private func countForFilter(_ filter: TestFilter) -> Int {
        switch filter {
        case .all: return activeTests.results.count
        case .passing: return activeTests.results.filter { $0.status == .success }.count
        case .failing: return activeTests.results.filter { $0.status == .failed }.count
        case .running: return activeTests.results.filter { $0.status == .running }.count
        }
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

struct FilterChip: View {
    let filter: ModernServerTestView.TestFilter
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? filter.color : .secondary.opacity(0.1),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct ModernTestCard: View {
    let test: ServerTest
    @Environment(\.blackbirdDatabase) var db
    @State private var isRunning = false
    
    var body: some View {
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
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
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
            
            HStack {
                AsyncButton {
                    await runTest()
                } label: {
                    HStack(spacing: 4) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                        }
                        Text("Run")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(isRunning)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
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
    
    return ModernServerTestView()
        .environment(\.blackbirdDatabase, db)
}
