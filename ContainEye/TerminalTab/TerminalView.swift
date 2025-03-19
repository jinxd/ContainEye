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
    @State private var history = [String]()
    @AppStorage("useVolumeButtons") private var useVolumeButtons = false

    @State var view: SSHTerminalView?

    @State private var messageText = String?.none

    var body: some View {
        VStack(spacing: 0){
            if let credential {
                if let view{
                    view
                        .toolbarVisibility(.hidden, for: .navigationBar)
                        .toolbarVisibility(.hidden, for: .tabBar)
                        .overlay(alignment: .topTrailing){
                            VStack(alignment: .trailing) {
                                HStack{
                                    Button {
                                        useVolumeButtons.toggle()
                                        self.view?.useVolumeButtons = useVolumeButtons
                                        messageText = useVolumeButtons ? "Volume buttons now control terminal arrow keys" : "Volume buttons no longer control terminal"
                                    } label: {
                                        Image(systemName: useVolumeButtons ? "plusminus.circle.fill" : "plusminus.circle")
                                            .font(.title)
                                    }
                                    Button{self.credential = nil} label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .buttonBorderShape(.circle)
                                    .controlSize(.large)
                                }
                                if let messageText {
                                    Text(messageText)
                                        .task{
                                            try? await Task.sleep(for: .seconds(2))
                                            self.messageText = nil
                                        }
                                        .padding(2)
                                        .background(in: .capsule)
                                }
                            }
                        }
                        .onDisappear{
                            view.setCurrentInputLine("history -a\n")
                            self.view = nil
                        }


                    TimelineView(.periodic(from: .now, by: 0.3)) { ctx in
                        HStack{
                            let inputLine = view.currentInputLine.trimmingCharacters(in: .whitespaces)
                            let preitems = shortestStartingWith(inputLine, in: history, limit: 3)
                            let items = (preitems.isEmpty ? ["None"] : preitems)
                            ForEach(items, id: \.self) { suggestion in
                                Button{
                                    view.setCurrentInputLine(suggestion)
                                } label: {
                                    Text(suggestion)
                                        .frame(minWidth: 100)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.1)
                                        .font(.headline)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .tint(suggestion == inputLine ? Color.blue : Color.black)
                                .italic(suggestion == "None")
                                .disabled(suggestion == "None")
                            }
                        }
                        .padding(.horizontal)
                        .font(.title)
                        .minimumScaleFactor(0.3)
                    }
                } else {
                    Text("loading...")
                        .task{
                            do {
                                let command = #"(cat ~/.bash_history 2>/dev/null; [ -f ~/.bash_history ] && echo ""; cat ~/.zsh_history 2>/dev/null) | tail -n 200"#
                                let historyString = try await SSHClientActor.shared.execute(command, on: credential)
                                print(historyString)
                                self.history = Array(Set(historyString.components(separatedBy: "\n").reversed())).filter({$0.trimmingCharacters(in: .whitespaces).count > 1})
                                    .filter({$0 != command})
                            } catch {
                                print(error)
                            }
                            view = SSHTerminalView(credential: .init(key: credential.key, label: credential.label, host: credential.host, port: credential.port, username: credential.username, password: credential.password), useVolumeButtons: useVolumeButtons)
                        }
                }
            } else {
                VStack {
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
        .preferredColorScheme(view == nil ? .none : .dark)
    }
    func shortestStartingWith(_ prefix: String, in array: [String], limit: Int) -> [String] {
        return array
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
            .sorted { $0.count < $1.count }
            .prefix(limit)
            .map { $0 }
    }
}

#Preview {
    NavigationStack{
        RemoteTerminalView()
    }
}
