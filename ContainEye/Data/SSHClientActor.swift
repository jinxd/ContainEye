//
//  SSHClientActor.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/29/25.
//

import Foundation
@preconcurrency import Citadel
import NIO

actor SSHClientActor {
    private var clients = [String: SSHClient]()


    func log(_ message: String) {
        print("\(Date().formatted(date: .omitted, time: .complete)) - \(message)")
    }

    func execute(_ command: String, on credential: Credential) async throws -> String {
        if let client = clients[credential.key], client.isConnected {
            do {
                return try await client.execute(command)
            } catch{
                throw error
            }
        } else {
            let client: SSHClient
            do {
                try await clients[credential.key]?.close()
            } catch {
                log("client closing error in \(#function): \(error.generateDescription()) \(String(describing: error))")
            }
            do{
                client = try await SSHClient.connect(using: credential)
            } catch {
                log("client connection error in \(#function): \(error.generateDescription()) \(String(describing: error))")
                throw error
            }
            clients[credential.key] = client
            do {
                return try await client.execute(command)
            } catch {
                log("client execution error in \(#function): \(error.generateDescription()) \(String(describing: error))")
                throw error
            }
        }
    }

    func disconnect(_ credential: Credential) async throws {
        if let client = clients[credential.key] {
            do{
                try await client.close()
            } catch {
                log("client disconnection error in \(#function): \(error.generateDescription()) \(String(describing: error))")
            }
            clients[credential.key] = nil
        }
    }

    func onDisconnect(of credential: Credential, perform action:@Sendable @escaping ()->Void) {
        clients[credential.key]?.onDisconnect{
            action()
        }
    }

    static let shared = SSHClientActor()
}


extension SSHClient {
    static func connect(using credential: Credential, reconnect: SSHReconnectMode = .always, connectTimeout: TimeAmount = .seconds(30)) async throws -> SSHClient {
        switch credential.effectiveAuthMethod {
        case .password:
            try await Self.connect(host: credential.host, port: Int(credential.port), authenticationMethod: .passwordBased(username: credential.username, password: credential.password), hostKeyValidator: .acceptAnything(), reconnect: reconnect, connectTimeout: connectTimeout)
        case .privateKey:
            try await Self.connect(
                host: credential.host,
                port: Int(credential.port),
                authenticationMethod:
                        .ed25519(username: credential.username, privateKey: .init(sshEd25519: (credential.privateKey?.data(using: .utf8)!)!)),
                hostKeyValidator: .acceptAnything(),
                reconnect: reconnect,
                connectTimeout: connectTimeout
            )
        case .privateKeyWithPassphrase:
            try await Self.connect(
                host: credential.host,
                port: Int(credential.port),
                authenticationMethod: 
                        .ed25519(username: credential.username, privateKey: .init(sshEd25519: (credential.privateKey?.data(using: .utf8)!)!, decryptionKey: credential.password.data(using: .utf8)!)),
                hostKeyValidator: .acceptAnything(),
                reconnect: reconnect,
                connectTimeout: connectTimeout
            )
        }
    }
}
