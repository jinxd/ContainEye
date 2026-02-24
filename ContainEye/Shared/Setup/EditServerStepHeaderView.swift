import SwiftUI

struct ServerFormStepHeaderView: View {
    let currentStep: Int
    let stepCount: Int
    let progress: Double
    let statusText: String?
    let canProceed: Bool
    let isConnecting: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let forwardTitle: String

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .opacity(currentStep > 0 ? 1 : 0)
            .disabled(currentStep == 0)

            VStack(alignment: .leading) {
                HStack {
                    Text("Step \(currentStep + 1) of \(stepCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: progress)
                    .tint(.accent)
            }

            Button(forwardTitle, action: onForward)
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || isConnecting)
        }
    }
}

#Preview(traits: .sampleData) {
    ServerFormStepHeaderView(
        currentStep: 2,
        stepCount: 5,
        progress: 0.6,
        statusText: "Modified",
        canProceed: true,
        isConnecting: false,
        onBack: {},
        onForward: {},
        forwardTitle: "Next"
    )
    .padding()
}
