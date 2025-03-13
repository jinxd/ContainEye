//
//  TerminalView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/13/25.
//

import SwiftUI
import SwiftTerm

struct RemoteTerminalView: View {
    @State private var credential: Credential?
    var body: some View {
        VStack{
            if let credential {
                SSHTerminalView(credential: .init(key: credential.key, label: credential.label, host: credential.host, port: credential.port, username: credential.username, password: credential.password))
                    .toolbarVisibility(.hidden, for: .navigationBar)
                    .toolbarVisibility(.hidden, for: .tabBar)
                    .overlay(alignment: .topTrailing){
                        Button{self.credential = nil} label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    }
            } else {
                Text("Select a server to connect to").monospaced()
                Picker(selection: $credential) {
                    let keychain = keychain()
                    let credentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
                    Text("None")
                        .tag(Credential?.none)
                    ForEach(credentials, id: \.key) { credential in
                        Text(credential.label)
                            .tag(credential)
                    }
                } label: {
                }
                .pickerStyle(.inline)

            }
        }
    }
}

#Preview {
    NavigationStack{
        RemoteTerminalView()
    }
}
