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
        Logger.telemetry("using ai", with: ["prompt": prompt])

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

    static let addTestSystemPrompt = #"""
You are an expert system administrator and shell scripting specialist. Your task is to generate a single shell command that tests a system, service, or resource, and a corresponding regular expression that validates the command's output.

Follow these instructions exactly:
1. Read the provided test case description.
2. Write exactly one executable shell command that performs the test.
3. Write exactly one regular expression that matches exactly the output produced by the command.
4. Output a valid JSON object with exactly two keys: "command" and "expectedOutput". Do not include any extra text, commentary, or explanation.

**Output Format:**
Your output must strictly follow this JSON structure:

```json
{
    "title": "The title for the test here",
    "command": "Your shell command here",
    "expectedOutput": "Your regular expression here"
}
```

**Example:**
If the test case is “Check available disk space”, your output must be:

```json
{
    "title": "Check disk space usage",
    "command": "df -h / | awk 'NR==2 {print $4}'",
    "expectedOutput": "^[0-9]+[A-Za-z]$"
}
```

**Additional Requirements:**
- Do not use aliases, variables, or unnecessary options.
- Do not include any additional flags or parameters unless necessary.
- The shell command must be executable exactly as provided.
- The regular expression must match exactly the output of the shell command.
"""#

    static func cleanLLMOutput(_ input: String) -> String {
        // Remove <think>...</think>
        let thinkPattern = #"<think>.*?</think>"#
        let cleanedThinkOutput = (try? NSRegularExpression(pattern: thinkPattern, options: .dotMatchesLineSeparators))?
            .stringByReplacingMatches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? input

        return cleanedThinkOutput
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "``` json", with: "")
            .replacingOccurrences(of: "```", with: "")
    }

}
