//
//  SSHClientActor.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/29/25.
//

import Foundation
@preconcurrency import Citadel

actor SSHClientActor {
    var clients = [String: SSHClient]()


    func execute(_ command: String, on credential: Credential) async throws -> String {
        if let client = clients[credential.key] {
            return try await client.execute(command)
        } else {
            let client = try await SSHClient.connect(host: credential.host, authenticationMethod: .passwordBased(username: credential.username, password: credential.password), hostKeyValidator: .acceptAnything(), reconnect: .always)
            clients[credential.username] = client
            return try await client.execute(command)
        }
    }

    func disconnect(_ credential: Credential) async throws {
        if let client = clients[credential.key] {
            try await client.close()
            clients[credential.key] = nil
        }
    }

    static let shared = SSHClientActor()
}
