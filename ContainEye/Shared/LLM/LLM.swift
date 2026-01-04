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

import Foundation

enum LLM {
    static func generate(prompt: String, systemPrompt: String, history: [[String: String]] = []) async -> (output: String, history: [[String:String]]) {

        do {
            // Prepare the conversation history, ensuring the system prompt is always at the start
            var conversation = [["role": "system", "content": systemPrompt]] + history
            conversation.append(["role": "user", "content": prompt])

            var urlRequest = URLRequest(url: URL(string: "https://containeye.hannesnagel.com/text-generation")!)
            urlRequest.httpMethod = "PUT"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: conversation)

            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let responseString = String(data: data, encoding: .utf8) ?? "Failed to parse response"

            // Append AI response to the conversation history
            conversation.append(["role": "assistant", "content": responseString])

            var newInputs: [[String: String]] = []

            // Try to parse as JSON to handle questions and execute commands
            struct AIResponse: Decodable {
                let type: String
                let content: String
            }

            // Check if response is valid JSON
            if let jsonData = responseString.data(using: .utf8),
               let aiResponse = try? JSONDecoder().decode(AIResponse.self, from: jsonData) {

                switch aiResponse.type {
                case "question":
                    let answer = try await ConfirmatorManager.shared.ask(aiResponse.content)
                    // Properly encode JSON to handle quotes, newlines, etc.
                    if let jsonData = try? JSONSerialization.data(withJSONObject: ["type": "answer", "content": answer]),
                       let jsonResponse = String(data: jsonData, encoding: .utf8) {
                        newInputs.append(["role": "user", "content": jsonResponse])
                    }

                case "execute":
                    let result = try await ConfirmatorManager.shared.execute(aiResponse.content)
                    // Properly encode JSON to handle quotes, newlines, etc.
                    if let jsonData = try? JSONSerialization.data(withJSONObject: ["type": "command_output", "content": result]),
                       let jsonResponse = String(data: jsonData, encoding: .utf8) {
                        newInputs.append(["role": "user", "content": jsonResponse])
                    }

                default:
                    break
                }
            }

            // If new input exists, recurse with updated history
            if !newInputs.isEmpty {
                return await generate(prompt: "", systemPrompt: systemPrompt, history: conversation + newInputs)
            }

            return (responseString, conversation)

        } catch {
            // Log error for debugging
            print("LLM generation error: \(error)")
            // Return error message instead of infinite retry
            return ("Error: Failed to generate response - \(error.localizedDescription)", history)
        }
    }


    static let addTestSystemPrompt = #"""
Your final task is to generate a test for a server the user already has chosen. The test works by executing the command you provide via ssh on a remote server and then validate the output using a regular expression repeatedly to make sure the server is healthy. The test must test something and can't just always succeed.
These tests are usually used to make sure the system will be in the future in the same condition as it currently is.
 
### **Response Options**
You have **three options** for responding:
1. **Provide a JSON response** with a shell command and a regular expression or plain string that matches exactly the entire output of the shell command but only when the test succeeds.
2. **Ask a question** to clarify the test case before proceeding.
3. **Execute a shell command** to retrieve necessary information before generating the response.

---
### **Important Rules**
- **Always ask a question first** if you lack the required details. You can ask questions using JSON:
    ```json
    {
        "type": "question",
        "content": "Your question here"
    }
    ```
- **Only provide a JSON response** if you have all necessary information:
    ```json
    {
        "type": "response",
        "content": {
            "title": "The title for the test here",
            "command": "Your shell command here",
            "expectedOutput": "Your regular expression or plain string here"
        }
    }
    ```
- **Execute a shell command** if you need system information before generating the response:
    ```json
    {
        "type": "execute",
        "content": "Your shell command here"
    }
    ```

---
### **Final Instructions**
- **Never assume missing information**—use `question` first.
- **Use only one response type at a time** (`JSON`, `question`, or `execute`).
- **The test must verify what the user describes
- **If the request is vague, clarify before proceeding.**
- **Before giving a test you must first execute the command and look at the output to make sure the test will work**
- When giving a test you should in most cases use grep to only return the important parts of the result that need to be validated, so that it only checks for the actual requested information

### **Example**
The user asks you to generate a test to verify that the right amount of docker containers are running:
You should then execute a command to check how many there are currently running and then create a test that checks whether later that exact same amount of containers will be running.
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
    struct Output: Decodable {
        let type: String
        let content: Content

        struct Content: Decodable {
            let title: String
            let command: String
            let expectedOutput: String
        }
    }
}
