//
//  ErrorView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//

import SwiftUI

struct ErrorView: View {
    let server: Server

    var body: some View {
        ScrollView(.horizontal) {
            HStack{
                ForEach(Array(server.errors), id: \.self) {error in
                    Button {
                        server.errors.remove(error)
                    } label: {
                        Text(String(describing: error))
                    }
                    .contextMenu{
                        Button("Copy", systemImage: "document.on.document") {
#if os(macOS)
                            NSPasteboard.general.setString(String(describing: error), forType: .string)
#else
                            UIPasteboard.general.string = String(describing: error)
#endif
                        }
                    }
                    .padding(5)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.red)
                }
            }
        }
    }
}
