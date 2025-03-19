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
        var stdout = ""
        do {
            for try await part in result.stdout {
                stdout.append(String(buffer: part))
            }
        } catch {print("threw: \(error)")}
        var stderr = ""
        do {
            for try await part in result.stderr {
                stderr.append(String(buffer: part))
            }
        } catch {print("stderr threw: \(error)")}
        print("stdout: ", stdout)
        print("stderr: ", stderr)
        return stderr.isEmpty ? stdout : stderr.appending("\n").appending(stdout)
    }
}
