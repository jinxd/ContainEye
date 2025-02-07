//
//  TestsHelp.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/6/25.
//


import SwiftUI

struct TestsHelp: View {
    var body: some View {
        GenericHelpView(
            title: "How do Tests work?",
            image: Image(systemName: "testtube.2"),
            contents: [
                .init(
                    sectionTitle: "What are Tests?",
                    text: Text("Tests allow you to monitor the health and functionality of your servers by running predefined commands and checking their output.")
                ),
                .init(
                    sectionTitle: "How do I add a Test?",
                    text: Text("In the Tests tab, click the 'Add Test' button. Enter a title, host, command, and expected output.")
                ),
                .init(
                    sectionTitle: "What is the Command?",
                    text: Text("The command is the actual shell command that will be executed on your server. For example: `df -h` to check disk space.")
                ),
                .init(
                    sectionTitle: "What is the Expected Output?",
                    text: Text("This is what you expect the command to return. It can be a fixed value or a regular expression pattern for flexible matching.")
                ),
                .init(
                    sectionTitle: "How can I check the current output?",
                    text: Text("Use the 'Fetch Current Output' button to run the command and see its actual result before setting the expected output.")
                ),
                .init(
                    sectionTitle: "How do I know if a Test fails?",
                    text: Text("If the command output does not match the expected output (or regex), the test will fail, indicating a potential issue.")
                ),
                .init(
                    sectionTitle: "Can I run tests automatically?",
                    text: Text("Yes! Tests run automatically at regular intervals, ensuring continuous monitoring of your servers.")
                ),
                .init(
                    sectionTitle: "Is there shortcuts support?",
                    text: Text("Yes! You can fetch the available tests, sort and filter them, and run them directly from the shortcuts app.")
                )
            ]
        ) {
            NavigationLink("Learn about Servers", value: Help.servers)
        }
    }
}

#Preview{
    NavigationStack(path: .constant([Help.servers])) {
        VStack {}
            .navigationDestination(for: Help.self) { help in
                TestsHelp()
            }
    }
}
