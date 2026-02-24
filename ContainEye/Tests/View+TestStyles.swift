import SwiftUI

extension View {
    func testSectionCard() -> some View {
        padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    func testContentBlock() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    func testCardShadow() -> some View {
        shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    func capsuleProminentButton(tint: Color = .accent) -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(tint)
    }

    func destructiveBorderedAction() -> some View {
        frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .tint(.red)
    }

    @ViewBuilder
    func matchedTransitionIfAvailable<ID: Hashable>(id: ID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

extension Text {
    func testFieldLabelStyle() -> some View {
        font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}
