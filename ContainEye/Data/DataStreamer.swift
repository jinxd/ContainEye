//
//  Data.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import Foundation
import Citadel
import KeychainAccess

@MainActor
@Observable
final class DataStreamer {
    static let shared = DataStreamer()
    var serversLoaded = false

    var servers = [Server]()
    var errors = Set<DataStreamerError>()

    private init() {
    }

    func initialize() async {
        serversLoaded = false
        servers.removeAll()
        errors.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for key in keychain().allKeys() {
                group.addTask {
                    do {
                        if let credential = keychain().getCredential(for: key) {
                            try await self.addServer(with: credential)
                        }
                    } catch {
                        await MainActor.run {
                            let _ = self.errors.insert(.failedToConnect(to: key, error: error.localizedDescription))
                        }
                    }
                }
            }
        }
        serversLoaded = true
    }

    // Initialize with credentials and connect to servers
    func addServer(with credential: Credential) async throws {
        let server = Server(credential: credential)
        try await server.connect()
        servers.append(
            server
        )

    }

    enum DataStreamerError: Error , Hashable {
        case failedToConnect(to: String, error: String)

        var localizedDescription: String {
            switch self {
            case .failedToConnect(to: let key, error: let error):
                let host = keychain().getCredential(for: key)?.host ?? "???"
                return "Failed to connect to \(host): \(error)"
            }
        }
    }



    func removeHost(_ key: String) async throws {
        let servers = servers.filter {
            $0.credential.key == key
        }
        self.servers.removeAll { $0.credential.key == key }


        for server in servers{
            try? await server.disconnect()
        }
        try keychain().remove(key)
    }
}
