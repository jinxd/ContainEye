//
//  CreditsView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 4/5/25.
//

import SwiftUI

struct CreditsView: View {
    var body: some View {
        Grid{
            Group{
                VStack{
                    Text("All packages are open source and licensed under the MIT License")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Thank you for supporting me")
                        .font(.caption)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial, in: .rect(cornerRadius: 15))
                GridRow{
                    MoreView.Link("Blackbird", destination: "https://github.com/marcoarment/Blackbird")
                    MoreView.Link("Citadel", destination: "https://github.com/orlandos-nl/Citadel")
                    MoreView.Link("ButtonKit", destination: "https://github.com/Dean151/ButtonKit")
                }
                .gridCellColumns(2)
                GridRow{
                    MoreView.Link("KeychainAccess", destination: "https://github.com/kishikawakatsumi/KeychainAccess")
                    MoreView.Link("SwiftTerm", destination: "https://github.com/migueldeicaza/SwiftTerm")
                }
                .gridCellColumns(3)
            }
        }
        .navigationTitle("Credits")
        .trackView("credits")
    }
}

#Preview {
    CreditsView()
}
