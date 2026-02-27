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
    let showsForwardButton: Bool
    
    private var showsBackButton: Bool {
        currentStep > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if showsBackButton {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(
                        Circle()
                            .fill(.thinMaterial)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Step \(currentStep + 1) of \(stepCount)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                            Capsule()
                                .fill(.accent)
                                .frame(width: max(24, proxy.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsForwardButton {
                    Button(action: onForward) {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(width: 24, height: 24)
                        } else {
                            Text(forwardTitle)
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canProceed || isConnecting)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
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
        forwardTitle: "Next",
        showsForwardButton: true
    )
    .padding()
}
