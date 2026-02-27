import SwiftUI

struct ServerFormStepCardView: View {
    let step: ServerFormStep
    var isPrimaryStep: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: step.icon)
                    .font(isPrimaryStep ? .title2.weight(.semibold) : .headline.weight(.semibold))
                    .foregroundStyle(isPrimaryStep ? .white : .accent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isPrimaryStep ? .accent : Color.accentColor.opacity(0.14))
                    )
                Spacer()
            }

            Text(step.title)
                .font(isPrimaryStep ? .title2.weight(.bold) : .title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text(step.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

#Preview(traits: .sampleData) {
    ServerFormStepCardView(
        step: ServerFormStep(
            icon: "globe",
            title: "Connection",
            description: "Modify hostname and port settings",
            field: .hostAndPort
        ),
        isPrimaryStep: true
    )
    .padding()
}
