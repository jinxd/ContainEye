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
    static func generate(prompt: String, systemPrompt: String, history: [[String: String]] = []) async -> String {
        Logger.telemetry("using ai", with: ["prompt": prompt])

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

            // Define regex patterns for JSON syntax
            let questionPattern = /"type":\s*"question".*?"content":\s*"([^"]+)"/.dotMatchesNewlines()
            let executePattern = /"type":\s*"execute",.*?"content":\s*"([^"]+)"/.dotMatchesNewlines()

            var newInputs: [[String: String]] = []


            print(responseString, responseString.matches(of: questionPattern).count, responseString.matches(of: executePattern).count)
            // Process questions
            for match in responseString.matches(of: questionPattern) {
                let question = match.1
                let answer = try await ConfirmatorManager.shared.ask(String(question))
                let jsonResponse = """
                {
                    "type": "answer",
                    "content": "\(answer)"
                }
                """
                newInputs.append(["role": "user", "content": jsonResponse])
            }

            // Process commands
            for match in responseString.matches(of: executePattern) {
                let command = match.1
                let result = try await ConfirmatorManager.shared.execute(String(command))
                let jsonResponse = """
                {
                    "type": "command_output",
                    "content": "\(result)"
                }	
                """
                newInputs.append(["role": "user", "content": jsonResponse])
            }

            // If new input exists, recurse with updated history
            if !newInputs.isEmpty {
                return await generate(prompt: "", systemPrompt: systemPrompt, history: conversation + newInputs)
            }

            return responseString

        } catch {
            return "Failed: \(error)"
        }
    }


    static let addTestSystemPrompt = #"""
Your final task is to generate a test for a server the user already has chosen. The test works by executing the command you provide via ssh on a remote server and then validate the output using a regular expression repeatedly to make sure the server is healthy. The test must test something and can't just always succeed.
These tests are usually used to make sure the system will be in the future in the same condition as it currently is.
 
### **Response Options**
You have **three options** for responding:
1. **Provide a JSON response** with a shell command and a regular expression that matches exactly the output of the shell command but only when it succeeds.
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
            "expectedOutput": "Your regular expression here"
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
