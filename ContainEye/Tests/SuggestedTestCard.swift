//
//  SuggestedTestCard.swift
//  ContainEye
//
//  Created by Hannes Nagel on 6/27/25.
//


import SwiftUI
import Blackbird
import ButtonKit

struct SuggestedTestCard: View {
    let test: ServerTest
    @Environment(\.blackbirdDatabase) var db
    @State private var isAdding = false
    @State private var showingServerSelection = false
    @State private var selectedServer: String?
    @BlackbirdLiveModels({
        try await Server.read(from: $0, matching: .all)
    }) var servers
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                
                Spacer()
                
                Text("Suggested")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            
            VStack(alignment: .leading) {
                Text(test.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(test.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                showingServerSelection = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption2)
                    Text("Add Test")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(isAdding)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showingServerSelection) {
            ServerSelectionView(
                test: test,
                selectedServer: $selectedServer,
                isAdding: $isAdding,
                onAdd: { serverKey in
                    await addTest(to: serverKey)
                }
            )
            .confirmator()
        }
    }
    
    private func addTest(to serverKey: String) async {
        isAdding = true
        
        var newTest = test
        newTest.id = Int.random(in: 1000...999999)
        newTest.credentialKey = serverKey
        
        try? await newTest.write(to: db!)
        isAdding = false
        showingServerSelection = false
    }
}