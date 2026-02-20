//
//  MoreView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/13/25.
//

import SwiftUI


struct MoreView: View {
    @Environment(\.namespace) var namespace
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            LazyVStack {
                // Header Section
                VStack {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)
                    
                    Text("More Options")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text("Get help, provide feedback, and explore ContainEye")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Help Section
                SectionCard(title: "Get Help", icon: "questionmark.circle.fill", color: .blue) {
                    CardRow(icon: "server.rack", title: "Learn about Servers", subtitle: "Server monitoring guide") {
                        NavigationLink(value: URL.servers) {
                            EmptyView()
                        }
                    }
                    
                    CardRow(icon: "testtube.2", title: "Automated Testing", subtitle: "Set up server health checks") {
                        NavigationLink(value: URL.automatedTests) {
                            EmptyView()
                        }
                    }
                    
                    CardRow(icon: "book.circle", title: "Documentation", subtitle: "Complete user guide") {
                        Button {
                            if let url = URL(string: "https://hannesnagel.com/containeye/") {
                                openURL(url)
                            }
                        } label: {
                            EmptyView()
                        }
                    }
                    
                    CardRow(icon: "envelope.circle", title: "Contact Support", subtitle: "Get personalized help") {
                        NavigationLink(value: Sheet.feedback) {
                            EmptyView()
                        }
                    }
                }
                
                // Community Section
                SectionCard(title: "Support ContainEye", icon: "heart.circle.fill", color: .red) {
                    CardRow(icon: "heart.fill", title: "Become a Supporter", subtitle: "Support development with a donation") {
                        NavigationLink(value: Sheet.supporter) {
                            EmptyView()
                        }
                    }

                    CardRow(icon: "square.and.arrow.up", title: "Share the App", subtitle: "Tell your friends about ContainEye") {
                        ShareLink(item: URL(string: "https://apps.apple.com/app/apple-store/id6741063706?pt=126452706&ct=containeye&mt=8")!) {
                            EmptyView()
                        }
                    }

                    CardRow(icon: "star.circle", title: "Leave a Review", subtitle: "Rate us on the App Store") {
                        Button {
                            if let url = URL(string: "https://apps.apple.com/de/app/containeye-terminal-docker/id6741063706?action=write-review") {
                                openURL(url)
                            }
                        } label: {
                            EmptyView()
                        }
                    }
                }
                
                // Development Section
                SectionCard(title: "Development", icon: "hammer.circle.fill", color: .orange) {
                    CardRow(icon: "exclamationmark.triangle", title: "Report a Bug", subtitle: "Open an issue on GitHub") {
                        Button {
                            if let url = URL(string: "https://github.com/hannesmnagel/ContainEye/issues") {
                                openURL(url)
                            }
                        } label: {
                            EmptyView()
                        }
                    }
                    
                    CardRow(icon: "envelope.badge", title: "Direct Feedback", subtitle: "Contact the developer") {
                        NavigationLink(value: Sheet.feedback) {
                            EmptyView()
                        }
                    }
                }
                
                // Open Source Section  
                SectionCard(title: "Open Source", icon: "chevron.left.forwardslash.chevron.right", color: .green) {
                    CardRow(icon: "ellipsis.curlybraces", title: "View Source Code", subtitle: "ContainEye is open source") {
                        Button {
                            if let url = URL(string: "https://github.com/hannesmnagel/ContainEye") {
                                openURL(url)
                            }
                        } label: {
                            EmptyView()
                        }
                    }
                    
                    CardRow(icon: "person.3.sequence", title: "Credits", subtitle: "See libraries used by this app") {
                        NavigationLink(value: Sheet.credits) {
                            EmptyView()
                        }
                    }
                }
                
                #if DEBUG
                // Debug Section
                SectionCard(title: "Debug", icon: "ladybug.circle.fill", color: .purple) {
                    CardRow(icon: "gearshape.arrow.triangle.2.circlepath", title: "Reset Setup", subtitle: "Show onboarding again") {
                        Button {
                            UserDefaults.standard.set("setup", forKey: "screen")
                            UserDefaults.standard.set(0, forKey: "setupScreen")
                        } label: {
                            EmptyView()
                        }
                    }

                    CardRow(icon: "info.circle", title: "Launch Tracking Info", subtitle: "View current tracking status") {
                        Button {
                            print(LaunchTracker.getDebugInfo())
                        } label: {
                            EmptyView()
                        }
                    }

                    CardRow(icon: "arrow.counterclockwise", title: "Reset Launch Tracking", subtitle: "Clear launch count and review history") {
                        Button {
                            LaunchTracker.resetTracking()
                        } label: {
                            EmptyView()
                        }
                    }

                    CardRow(icon: "star.bubble", title: "Force Review Prompt", subtitle: "Test review request UI") {
                        Button {
                            Task {
                                LaunchTracker.requestReview()
                            }
                        } label: {
                            EmptyView()
                        }
                    }
                }
                #endif
            }
            .padding()
        }
        .trackView("more")
        .navigationTitle("More")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

}

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.bottom)
            
            LazyVStack {
                content
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct CardRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .buttonStyle(CardRowButtonStyle(icon: icon, title: title, subtitle: subtitle))
    }
}

struct CardRowButtonStyle: ButtonStyle {
    let icon: String
    let title: String
    let subtitle: String
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .stroke(.blue.opacity(0.1), lineWidth: 1)
        )
        .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack{
        MoreView()
    }
}
