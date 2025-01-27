//
//  SSHClient+execute.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/24/25.
//

import Citadel

extension SSHClient {
    public func execute(_ command: String) async throws -> String {
        
        let bytebuffer = try await executeCommand(command, maxResponseSize: .max, mergeStreams: false, inShell: false)
        return String(buffer: bytebuffer)
    }
}
