//
//  DataStreamerErrorView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/26/25.
//

import SwiftUI
import ButtonKit

struct DataStreamerErrorView: View {
    @State private var dataStreamer = DataStreamer.shared
    
    var body: some View {
        VStack{
            ForEach(Array(dataStreamer.errors), id: \.self) {error in
                VStack{
                    if case let .failedToConnect(host, _) = error{
                        Text(host)
                            .font(.headline)
                    }
                    Text(error.localizedDescription)

                    HStack {
                        if case let .failedToConnect(key, _) = error{
                            AsyncButton("Remove Server", systemImage: "trash", role: .destructive) {
                                try await dataStreamer.removeHost(key)
                                dataStreamer.errors.remove(error)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Copy Error", systemImage: "document.on.document") {
#if os(macOS)
                            NSPasteboard.general.setString(String(describing: error), forType: .string)
#else
                            UIPasteboard.general.string = String(describing: error)
#endif
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.red.tertiary, in: .rect(cornerRadius: 15))
                .buttonBorderShape(.capsule)
            }
        }
    }
}
