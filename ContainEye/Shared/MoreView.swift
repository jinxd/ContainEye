//
//  MoreView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/13/25.
//

import SwiftUI

struct MoreView: View {
    @Environment(\.namespace) var namespace

    var body: some View {
        ScrollView {
            Grid {
                Text("Get Help")
                GridRow{
                    NavigationLink("Learn about servers", value: URL.servers)
                    NavigationLink("Learn about testing them", value: URL.automatedTests)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial, in: .rect(cornerRadius: 15))


                GridRow{

                    Link("Learn about everything else", destination: "https://hannesnagel.com/containeye/")
                    NavigationLink("Haven't found help?", value: Sheet.feedback)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial, in: .rect(cornerRadius: 15))
                        .matchedTransitionSource(id: Sheet.feedback.id, in: namespace!)
                }

                Divider()
                    .padding(.top)

                Text("Help me")
                GridRow {
                    ShareLink(item: URL(string: "https://apps.apple.com/app/apple-store/id6741063706?pt=126452706&ct=containeye&mt=8")!)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial, in: .rect(cornerRadius: 15))
                    Link("Please leave a review", destination: "https://apps.apple.com/de/app/containeye-terminal-docker/id6741063706?action=write-review", openExternally: true)
                }

                Divider()
                    .padding(.top)

                Text("Found a Bug?")
                Link("Please open a new Issue on GitHub", destination: "https://github.com/hannesmnagel/ContainEye/issues", openExternally: true)
                NavigationLink("Or contact me directly", value: Sheet.feedback)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial, in: .rect(cornerRadius: 15))


                Divider()
                    .padding(.top)

                Text("Open Source")
                Link("ContainEye is open source", destination: "https://github.com/hannesmnagel/ContainEye")

                NavigationLink(value: Sheet.credits){
                    Text("Credits")
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial, in: .rect(cornerRadius: 15))
                }

#if DEBUG

                Divider()
                    .padding(.top)

                Text("Other")
                Button("Show setup again") {
                    UserDefaults.standard.set("setup", forKey: "screen")
                    UserDefaults.standard.set(0, forKey: "setupScreen")
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial, in: .rect(cornerRadius: 15))
#endif

            }
            .trackView("more")
            .padding()
            .navigationTitle("More")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }

    struct Link: View {
        let text: LocalizedStringKey
        let destination: URL
        let openExternally: Bool
        @Environment(\.openURL) var openURL

        init(_ text: LocalizedStringKey, destination: String, openExternally: Bool = false) {
            self.text = text
            self.destination = URL(string: destination)!
            self.openExternally = openExternally
        }

        var body: some View {
            Group{
                if openExternally {
                    Button(text) {openURL(destination)}
                } else {
                    NavigationLink(text, value: destination)
                        .contextMenu{
                            SwiftUI.Link(destination: destination){
                                Label("Open in Safari", systemImage: "safari")
                            }
                        }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thinMaterial, in: .rect(cornerRadius: 15))
        }
    }
}

#Preview {
    NavigationStack{
        MoreView()
    }
}
