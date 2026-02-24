//
//  CreditsView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 4/5/25.
//

import SwiftUI

struct CreditsView: View {
    @Environment(\.openURL) private var openURL
    
    let dependencies = [
        Dependency(
            name: "Blackbird",
            description: "High-performance SQLite toolkit",
            author: "Marco Arment",
            url: "https://github.com/marcoarment/Blackbird",
            icon: "cylinder.fill",
            color: .blue
        ),
        Dependency(
            name: "Citadel",
            description: "SSH and SFTP client library",
            author: "Orlandos",
            url: "https://github.com/orlandos-nl/Citadel",
            icon: "lock.shield.fill",
            color: .green
        ),
        Dependency(
            name: "ButtonKit",
            description: "Async button components",
            author: "Dean151",
            url: "https://github.com/Dean151/ButtonKit",
            icon: "button.horizontal.fill",
            color: .orange
        ),
        Dependency(
            name: "KeychainAccess",
            description: "Simple keychain wrapper",
            author: "Kishikawa Katsumi",
            url: "https://github.com/kishikawakatsumi/KeychainAccess",
            icon: "key.fill",
            color: .purple
        ),
        Dependency(
            name: "SwiftSH",
            description: "Interactive SSH shell streaming",
            author: "Miguel de Icaza",
            url: "https://github.com/migueldeicaza/SwiftSH",
            icon: "terminal.fill",
            color: .indigo
        ),
        Dependency(
            name: "xterm.js",
            description: "Web terminal emulator",
            author: "xterm.js contributors",
            url: "https://github.com/xtermjs/xterm.js",
            icon: "terminal.fill",
            color: .indigo
        )
    ]
    
    var body: some View {
        ScrollView {
            VStack {
                // Header Section
                VStack {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    
                    Text("Credits & Thanks")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text("ContainEye is built with these amazing open source libraries")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()

                // Thank You Section
                VStack {
                    Text("Thank You! 🙏")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("ContainEye wouldn't be possible without these incredible open source projects and their maintainers. Their dedication to the developer community makes apps like this possible.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    Button {
                        if let url = URL(string: "https://github.com/hannesmnagel/ContainEye") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Star ContainEye on GitHub")
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding()
                        .background(.blue)
                        .clipShape(Capsule())
                    }
                    .padding(.top)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.green.opacity(0.05))
                        .stroke(.green.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

                // Open Source Statement
                VStack {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        
                        Text("Open Source")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.bottom)
                    
                    VStack(alignment: .leading) {
                        Label("All dependencies are MIT Licensed", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                        
                        Label("ContainEye source code is available on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(.blue)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .stroke(.blue.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // Dependencies Section
                VStack {
                    HStack {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        
                        Text("Dependencies")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.bottom)
                    
                    LazyVStack {
                        ForEach(dependencies, id: \.name) { dependency in
                            DependencyRow(dependency: dependency, openURL: openURL)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .stroke(.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
        .trackView("credits")
    }
}

struct Dependency {
    let name: String
    let description: String
    let author: String
    let url: String
    let icon: String
    let color: Color
}

struct DependencyRow: View {
    let dependency: Dependency
    let openURL: OpenURLAction
    
    var body: some View {
        Button {
            if let url = URL(string: dependency.url) {
                openURL(url)
            }
        } label: {
            HStack {
                // Icon
                Image(systemName: dependency.icon)
                    .font(.title2)
                    .foregroundStyle(dependency.color)
                    .frame(width: 32, height: 32)
                
                // Content
                VStack(alignment: .leading) {
                    HStack {
                        Text(dependency.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(dependency.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("by \(dependency.author)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(dependency.color.opacity(0.05))
                    .stroke(dependency.color.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        CreditsView()
    }
}
