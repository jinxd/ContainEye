//
//  ServersHelp.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/6/25.
//


import SwiftUI

struct ServersHelp: View {
    var body: some View {
        GenericHelpView(
            title: "Wait, what am I supposed to do?",
            image: Image(systemName: "server.rack"),
            contents: [
                .init(
                    sectionTitle: "Why should I add a server?",
                    text: Text("This app is for managing these servers and monitoring their status and health."),
                    footerTitle: "You can use ContainEye to some degree without servers. Learn more how to do that in the tests section."
                ),
                .init(
                    sectionTitle: "How do I add a server?",
                    text: Text("In the main Servers tab, click the add server button to add a new server.\nThen enter your server's details there.")
                ),
                .init(
                    sectionTitle: "What is the label?",
                    text: Text("You can use a label to identify your server easily. This can be anything you like.")
                ),
                .init(
                    sectionTitle: "What is the Host?",
                    text: Text("Enter here the public ip address or web address where you can reach your server. For example: example.com, or 8.8.8.8")
                ),
                .init(
                    sectionTitle: "What is the Port?",
                    text: Text("The port is a number identifying where your server accepts ssh connections. Usually this is 22, but it can be different.")
                ),
                .init(
                    sectionTitle: "What is the User?",
                    text: Text("In the User field enter the username you want to use to sign into your server. This user should be in the docker group.")
                ),
                .init(
                    sectionTitle: "What is my password?",
                    text: Text("I don't know your password. And I don't want to know it (;. This password is used to authenticate the user on your server.")
                ),
                .init(
                    sectionTitle: "Is my data secure?",
                    text: Text("Yes! Absolutely. **All** server credentials are stored **securely** in Keychain and synced with iCloud **with end-to-end encryption**.")
                )
            ]
        ) {
            NavigationLink("Learn about Tests", value: Help.tests)
        }
    }
}


#Preview{
    NavigationStack(path: .constant([Help.servers])) {
        VStack {}
            .navigationDestination(for: Help.self) { help in
                ServersHelp()
            }
    }
}
