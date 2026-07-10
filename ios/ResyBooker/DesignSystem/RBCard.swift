import SwiftUI

extension View {
    /// Standard card chrome: a filled rounded rectangle with the hairline border.
    /// One definition so radius/border/fill stay consistent across every card.
    func rbCard(
        radius: CGFloat = RBRadius.card,
        fill: Color = RBColor.surface,
        bordered: Bool = true
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(bordered ? RBColor.border : Color.clear, lineWidth: 1)
                )
        )
    }
}
