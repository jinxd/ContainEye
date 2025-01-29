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
    @Binding var sheet : ContentView.Sheet?
    @Environment(\.blackbirdDatabase) var db
    @BlackbirdLiveModels({ try await ServerTest.read(from: $0, orderBy: .descending(\.$lastRun)) }) var test
    @Environment(\.scenePhase) var scenePhase
    @State private var notificationsAllowed = true
    @Namespace private var namespace

    var body: some View {
        ScrollView {
            VStack{
                if test.didLoad {
                    if test.results.isEmpty {
                        ContentUnavailableView("You don't have any tests yet.", systemImage: "testtube.2")
                    } else {
                        VStack {
                            if !notificationsAllowed {
                                HStack {
                                    Text("Notifications not allowed")
                                    Spacer()
                                    Button("Change") {
                                        UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
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
                        .animation(.smooth, value: test.results)
                        .padding(.vertical)
                    }
                }
            }
            .padding()
            .containerRelativeFrame(test.results.isEmpty ? .vertical : [])
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add Test", systemImage: "plus") {
                sheet = .addTest
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}



#Preview {
    let db = try! Blackbird.Database.inMemoryDatabase()
    let serverTest = ServerTest(id: 17891, title: "Test", credentialKey: UUID().uuidString, command: "echo test", expectedOutput: "test", state: .success)
    let _ = Task{try await serverTest.write(to: db) }
    let serverTest2 = ServerTest(id: 19311, title: "Test", credentialKey: UUID().uuidString, command: "echo test", expectedOutput: "test", state: .success)
    let _ = Task{try await serverTest2.write(to: db) }
    ServerTestView(sheet: .constant(nil))
        .environment(\.blackbirdDatabase, db)
}
