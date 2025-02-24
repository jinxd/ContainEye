//
//  LLMEvaluator.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/8/25.
//


import SwiftUI

enum LLMEvaluatorError: Error {
    case modelNotFound(String)
}

enum LLM {
    static func generate(prompt: String, systemPrompt: String) async -> String {
        Logger.telemetry("using ai")

        do {
            var urlRequest = URLRequest(url: URL(string: "https://containeye.hannesnagel.com/text-generation")!)
            urlRequest.httpMethod = "PUT"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization
                .data(
                    withJSONObject:
                        [
                            ["role": "system",
                             "content": systemPrompt],
                            ["role": "user",
                             "content": prompt],
                        ]
                )
            let (data, _) = try await URLSession.shared.data(for: urlRequest)

            return String(data: data, encoding: .utf8) ?? "Failed to parse response"

        } catch {
            return "Failed: \(error)"
        }
    }
}
