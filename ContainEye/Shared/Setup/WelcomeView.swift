//
//  WelcomeView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI

struct WelcomeView: View {
    @Binding var setupScreen: Int
    @State private var animationPhase = 0
    
    let features = [
        WelcomeFeature(
            icon: "server.rack",
            title: "Monitor Servers",
            description: "Track CPU, memory, disk usage and system health in real-time",
            color: .blue
        ),
        WelcomeFeature(
            icon: "terminal.fill",
            title: "SSH Terminal",
            description: "Full terminal access with smart command completion",
            color: .green
        ),
        WelcomeFeature(
            icon: "folder.fill",
            title: "SFTP Files",
            description: "Browse, edit, and manage files remotely with ease",
            color: .orange
        ),
        WelcomeFeature(
            icon: "testtube.2",
            title: "Automated Tests",
            description: "Set up health checks and monitoring alerts",
            color: .purple
        )
    ]
    
    var body: some View {
        VStack {
            Spacer()
            
            // App Icon and Title
            VStack {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(animationPhase >= 1 ? 1.0 : 0.8)
                        .opacity(animationPhase >= 1 ? 1.0 : 0.0)
                    
                    Image(systemName: "eye.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                        .scaleEffect(animationPhase >= 2 ? 1.0 : 0.5)
                        .rotationEffect(.degrees(animationPhase >= 2 ? 0 : 180))
                }
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: animationPhase)
                
                VStack {
                    Text("Welcome to")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .opacity(animationPhase >= 3 ? 1.0 : 0.0)
                    
                    Text("ContainEye")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .opacity(animationPhase >= 3 ? 1.0 : 0.0)
                }
                .animation(.easeInOut(duration: 0.6).delay(0.4), value: animationPhase)
            }
            
            Spacer()
            
            // Features Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    FeatureCard(feature: feature)
                        .opacity(animationPhase >= 4 ? 1.0 : 0.0)
                        .offset(y: animationPhase >= 4 ? 0 : 20)
                        .animation(.easeInOut(duration: 0.4).delay(Double(index) * 0.1 + 0.8), value: animationPhase)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Get Started Button
            VStack {
                Text("Let's set up your first server")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(animationPhase >= 5 ? 1.0 : 0.0)
                
                Button {
                    withAnimation(.spring()) {
                        setupScreen = 1
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                        Text("Get Started")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(animationPhase >= 5 ? 1.0 : 0.9)
                .opacity(animationPhase >= 5 ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.2), value: animationPhase)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onAppear {
            // Staggered animation sequence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { animationPhase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { animationPhase = 2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { animationPhase = 3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { animationPhase = 4 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { animationPhase = 5 }
        }
    }
}

struct WelcomeFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct FeatureCard: View {
    let feature: WelcomeFeature
    
    var body: some View {
        VStack {
            Image(systemName: feature.icon)
                .font(.title)
                .foregroundStyle(feature.color)
                .frame(width: 44, height: 44)
            
            Text(feature.title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            
            Text(feature.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .stroke(feature.color.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview(traits: .sampleData) {
    WelcomeView(setupScreen: .constant(0))
}
