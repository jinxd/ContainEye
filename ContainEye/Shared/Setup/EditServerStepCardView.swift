import SwiftUI

struct ServerFormStepCardView: View {
    let step: ServerFormStep

    var body: some View {
        VStack {
            Image(systemName: step.icon)
                .font(.title2)
                .foregroundStyle(.accent)
            Text(step.title)
                .font(.headline)
            Text(step.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }
}

#Preview(traits: .sampleData) {
    ServerFormStepCardView(
        step: ServerFormStep(
            icon: "globe",
            title: "Connection",
            description: "Modify hostname and port settings",
            field: .hostAndPort
        )
    )
    .padding()
}
