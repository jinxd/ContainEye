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
    @BlackbirdLiveModels({ try await ServerTest.read(from: $0, orderBy: .descending(\.$state)) }) var test
    @Environment(\.scenePhase) var scenePhase
    @State private var notificationsAllowed = true

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
                                    NavigationLink(value: test) {
                                        VStack(alignment: .leading) {
                                            Text(test.title)
                                                .font(.headline)
                                            let host = keychain().getCredential(for: test.credentialKey)?.host ?? "???"
                                            Text(host)
                                            Text(test.state.localizedDescription)
                                        }
                                        .lineLimit(1)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background{
                                            let state = test.state
                                            let color = state == .failed ? Color.red : state == .success ? Color.green : Color.blue
                                            RoundedProgressRectangle(cornerRadius: 15)
                                                .trim(from: 0, to:
                                                        state == .notRun ? 1 : state == .running ? 0.5 : 1
                                                )
                                                .stroke(color, style: StrokeStyle(lineWidth: 5, dash: state == .running ? [0, 0.3, 4] : []))
                                                .animation(.smooth, value: state)
                                            
                                        }
                                    }
                                    .contextMenu {
                                        AsyncButton("Execute", systemImage: "testtube.2") {
                                            var test = test
                                            test.state = .running
                                            try await test.write(to: db!)
                                            test = await test.test()

#if !os(macOS)
                                            if test.state == .failed {
                                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                            } else {
                                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                            }
#endif
                                            try await test.write(to: db!)
                                        }
                                        .disabled(test.state == .running)
                                        AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                                            try await test.delete(from: db!)
                                        }
                                    }
                                    .padding(3)
#if !os(macOS)
                                    .drawingGroup()
#endif
                                }
                            }
                        }
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
