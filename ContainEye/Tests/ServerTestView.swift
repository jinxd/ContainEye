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

struct ServerTestView: View {
    @Environment(\.blackbirdDatabase) var db
    @BlackbirdLiveModels({
        try await ServerTest.read(
            from: $0,
            matching: \.$credentialKey != "-",
            orderBy: .descending(\.$lastRun)
        )
    }) var test
    @BlackbirdLiveModels({
        try await ServerTest.read(
            from: $0,
            matching: \.$credentialKey == "-",
            orderBy: .descending(\.$lastRun)
        )
    }) var suggestions
    @Environment(\.scenePhase) var scenePhase
    @State private var notificationsAllowed = true
    @Environment(\.namespace) var namespace

    var body: some View {
        ScrollView {
            VStack{
                if test.didLoad {
                    VStack {

                        HStack {
                            Button {
                                UserDefaults.standard.set(2, forKey: "setupScreen")
                                UserDefaults.standard.set(ContentView.Screen.setup.rawValue, forKey: "screen")
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)

                            Spacer()

                            Text("Active Tests")
                                .font(.title.bold())
                                .frame(maxWidth: .infinity)

                            Spacer()

                            if test.results.count > 2 {
                                AsyncButton("Test all") {
                                    for test in test.results {
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
                                }
                                .buttonBorderShape(.capsule)
                                .buttonStyle(.bordered)
                                .padding(2)
                            }
                        }
                        .padding(5)
                        .background(test.results.contains(where: {$0.status == .failed}) ? .red.opacity(0.2) : .green.opacity(0.2), in: .capsule)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.top, 30)
                        .visualEffect { content, geo in
                            content.offset(y: geo.safeAreaInsets.top - min(0,geo.frame(in: .scrollView).midY))
                        }
                        .zIndex(1)
                        .padding(.bottom, 30)
                        if test.results.isEmpty {
                            ContentUnavailableView("You don't have any tests yet.", systemImage: "testtube.2")
                                .containerRelativeFrame(.vertical){len, axis in
                                    len*0.4
                                }
                        } else {
                            if !notificationsAllowed {
                                HStack {
                                    Text("Notifications not allowed")
                                    Spacer()

                                    Button("Change") {
#if !os(macOS)
                                        UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
#else
#warning("fix this for macOS")
#endif
                                    }
                                }
                                .padding()
                                .background(.orange, in: .capsule)
                                .padding(.vertical)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 250))], spacing: 15){
                                ForEach(test.results) { test in
                                    TestSummaryView(test: test.liveModel)
                                }
                            }
                        }
                        Text("Suggested")
                            .font(.title.bold())
                            .frame(maxWidth: .infinity)
                            .padding(5)
                            .background(.regularMaterial, in: .capsule)
                            .padding(.top, 30)
                            .visualEffect { content, geo in
                                content.offset(y: geo.safeAreaInsets.top - min(0,geo.frame(in: .scrollView).midY))
                            }
                            .zIndex(2)
                            .padding(.bottom, 30)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 250))], spacing: 15){
                            ForEach(suggestions.results) { test in
                                TestSummaryView(test: test.liveModel)
                            }
                        }
                    }
                    .animation(.smooth, value: test.results)
                    .padding(.vertical)
                }
                NavigationLink("Learn more", value: URL.automatedTests)


            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}



#Preview {
    let db = try! Blackbird.Database.inMemoryDatabase()
    let serverTest = ServerTest(id: 17891, title: "Test", credentialKey: UUID().uuidString, command: "echo test", expectedOutput: "test", status: .success)
    let _ = Task{try await serverTest.write(to: db) }
    let serverTest2 = ServerTest(id: 19311, title: "Test", credentialKey: UUID().uuidString, command: "echo test", expectedOutput: "test", status: .success)
    let _ = Task{try await serverTest2.write(to: db) }
    ServerTestView()
        .environment(\.blackbirdDatabase, db)
}
