//
//  SSHClient+execute.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/24/25.
//

import Citadel
import NIOSSH
import NIO

extension SSHClient {
    public func execute(_ command: String) async throws -> String {
        let result = try await executeCommandPair(command)
        var exitCode = 0
        var stdout = ""
        do {
            for try await part in result.stdout {
                stdout.append(String(buffer: part))
            }
        } catch {
            if let error = error as? CommandFailed {
                exitCode = error.exitCode
            }
        }
        var stderr = ""
        do {
            for try await part in result.stderr {
                stderr.append(String(buffer: part))
            }
        } catch {print("stderr threw: \(error)")}

        print("stdout: ", "\"\(stdout)\"")
        if exitCode != 0 {
            print("stderr: ", "\"\(stderr)\"")
        }
        return exitCode == 0 ? stdout : stderr.appending("\n").appending(stdout)
    }
}
