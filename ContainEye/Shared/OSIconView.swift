//
//  OSIconView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI

struct OSIconView: View {
    let server: Server
    let size: CGFloat
    
    init(server: Server, size: CGFloat = 24) {
        self.server = server
        self.size = size
    }
    
    var body: some View {
        Group {
            if let iconData = server.iconData,
               let uiImage = UIImage(data: iconData) {
                // Show downloaded OS icon
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                // Fallback to SF Symbol with color
                Image(systemName: server.osIconName)
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(colorForOS(server.osIconColor))
                    .frame(width: size, height: size)
            }
        }
    }
    
    private func colorForOS(_ colorName: String) -> Color {
        switch colorName {
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        default: return .blue
        }
    }
}

#Preview(traits: .sampleData) {
    VStack {
        // Example with Ubuntu
        OSIconView(server: Server(credentialKey: "test"))
        
        // Example with different sizes
        HStack {
            OSIconView(server: Server(credentialKey: "test"), size: 16)
            OSIconView(server: Server(credentialKey: "test"), size: 24)
            OSIconView(server: Server(credentialKey: "test"), size: 32)
            OSIconView(server: Server(credentialKey: "test"), size: 48)
        }
    }
}