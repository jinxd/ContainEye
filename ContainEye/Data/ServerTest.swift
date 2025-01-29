//
//  ServerTest.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/24/25.
//

import Foundation
import Blackbird
import KeychainAccess
import Citadel
import NIOSSH

struct ServerTest: BlackbirdModel {

    static let primaryKey: [BlackbirdColumnKeyPath] = [
        \.$id
    ]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [\.$state],
        [\.$lastRun]
    ]

    @BlackbirdColumn var id: Int
    @BlackbirdColumn var title: String
    @BlackbirdColumn var credentialKey: String
    @BlackbirdColumn var command: String
    @BlackbirdColumn var expectedOutput: String
    @BlackbirdColumn var lastRun: Date?
    @BlackbirdColumn var state: TestState
    @BlackbirdColumn var output: String?

    enum TestState: String , BlackbirdStringEnum {
        typealias RawValue = String

        case failed, success, running, notRun

        var localizedDescription: String {
            switch self {
            case .failed:
                return "failed"
            case .success:
                return "success"
            case .running:
                return "running"
            case .notRun:
                return "not run"
            }
        }
    }

    func fetchOutput() async -> String {
        guard let credential = keychain().getCredential(for: self.credentialKey) else {
            return "(Client Error) No credential in keychain"
        }
        do {
            let output = try await retry { try await SSHClientActor.shared.execute(self.command, on: credential) }
            return output
        } catch {
            do{
                let _ = try await URLSession.shared.data(from: URL(string: "https://connectivitycheck.gstatic.com/generate_204")!)
                if let message = (error as? TTYSTDError)?.message {
                    return String(buffer: message)
                }

                return error.localizedDescription
            } catch {
                return "Not connected to internet"
            }
        }
    }


    func test() async -> ServerTest {
        var test = self
        test.lastRun = .now

        let output = await fetchOutput()

        if (try? (Regex(test.expectedOutput)).wholeMatch(in: output)) != nil || output == test.expectedOutput {
            test.state = .success
        } else {
            test.state = .failed
        }
        test.output = output

        return test
    }
}

func retry<T>(count: Int = 6, _ block: () async throws -> T) async rethrows -> T {
    do {
        return try await block()
    } catch {
        if count > 0 {


            if let error = error as? NIOSSHError,
               error.type == .protocolViolation{

                return try await retry { try await block() }
            }

            let _ = try await URLSession.shared.data(from: URL(string: "https://connectivitycheck.gstatic.com/generate_204")!)
            try? await Task.sleep(for: .seconds(0.5))
            return try await retry(count: count - 1, block)
        } else {
            throw error
        }
    }
}
