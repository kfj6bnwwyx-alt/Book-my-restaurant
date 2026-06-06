import SwiftUI

/// Sweeping highlight for loading placeholders. Respects Reduce Motion (falls
/// back to a static block).
private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var move = false

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.07), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: move ? geo.size.width : -geo.size.width * 0.6)
                }
                .clipped()
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                        move = true
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func rbShimmer() -> some View { modifier(ShimmerModifier()) }
}

/// A single skeleton block. Compose several to mirror a real row or card.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(RBColor.surface2)
            .frame(width: width, height: height)
            .rbShimmer()
    }
}

/// Example: a skeleton placeholder matching a venue availability card.
struct SkeletonVenueCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RBSpacing.md) {
            SkeletonBlock(width: 150, height: 16)
            SkeletonBlock(width: 70, height: 12)
            HStack(spacing: RBSpacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(width: 56, height: 32, cornerRadius: 10)
                }
            }
        }
        .padding(RBSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous)
                .fill(RBColor.surface)
                .overlay(RoundedRectangle(cornerRadius: RBRadius.card, style: .continuous).stroke(RBColor.border, lineWidth: 1))
        )
    }
}

#Preview {
    ZStack {
        RBColor.bg.ignoresSafeArea()
        VStack(spacing: 12) {
            SkeletonVenueCard()
            SkeletonVenueCard()
        }
        .padding()
    }
}
