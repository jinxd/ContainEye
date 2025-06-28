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
    var body: some View {
        ModernServerTestView()
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
