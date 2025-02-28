//
//  GenericHelpView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/6/25.
//


import SwiftUI

struct GenericHelpView<Footer: View>: View {
    let title : LocalizedStringKey
    let image : Image
    let contents : [HelpContent]

    struct HelpContent: Identifiable {
        var id = UUID()
        let sectionTitle : LocalizedStringKey?
        let text : Text
        var footerTitle : LocalizedStringKey? = nil
    }

    @ViewBuilder let footer: Footer

    var body: some View {
        ScrollView{
            Section{
                image
                    .resizable()
                    .scaledToFit()
                    .padding(100)
                    .scrollTransition { effect, phase in
                        effect
                            .rotationEffect(.degrees(phase.value * 180))
                    }
            }
            ForEach(contents) { content in
                VStack(alignment: .leading){
                    DisclosureGroup {
                        content.text
                            .onAppear{
                                if let sectionTitle = Mirror(reflecting: content.sectionTitle ?? "").children.first(where: { $0.label == "key" })?.value as? String {
                                    Logger.telemetry(
                                        "Opened help section",
                                        with: [
                                            "section" : sectionTitle
                                        ]
                                    )
                                }
                            }
                        if let footerTitle = content.footerTitle {
                            Text(footerTitle)
                                .font(.footnote)
                                .padding(.vertical, 5)
                        }
                    } label: {
                        Text(content.sectionTitle ?? "")
                            .font(.headline)
                            .padding(.vertical, 5)
                    }
                    .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor.quinary, in: .rect(cornerRadius: 15))
                .background(in: .rect(cornerRadius: 15))
                .padding()
            }
            footer
        }
        .navigationTitle(title)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}


#Preview{
    NavigationStack(path: .constant([Help.servers])) {
        VStack {}
            .navigationDestination(for: Help.self) { help in
                HelpView(help: help)
            }
    }
}
