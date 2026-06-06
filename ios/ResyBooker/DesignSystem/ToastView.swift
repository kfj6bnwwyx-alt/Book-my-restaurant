import SwiftUI

enum RBToastStyle {
    case success, error, info

    var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success: return RBColor.success
        case .error: return RBColor.red
        case .info: return RBColor.textSecondary
        }
    }
}

/// Transient confirmation pill. Pair with `.rbToast(...)` to present over content.
struct ToastView: View {
    let style: RBToastStyle
    let text: String

    var body: some View {
        HStack(spacing: RBSpacing.sm + 2) {
            Image(systemName: style.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(style.tint)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(RBColor.textPrimary)
        }
        .padding(.horizontal, RBSpacing.lg)
        .padding(.vertical, RBSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(RBColor.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RBColor.border, lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.33), radius: 24, x: 0, y: 8)
    }
}

private struct RBToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let style: RBToastStyle
    let text: String
    var duration: TimeInterval = 2.5

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                ToastView(style: style, text: text)
                    .padding(.top, RBSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(duration))
                        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: isPresented)
    }
}

extension View {
    /// Presents a toast over the top edge while `isPresented` is true, then auto-dismisses.
    func rbToast(isPresented: Binding<Bool>,
                 style: RBToastStyle = .success,
                 text: String,
                 duration: TimeInterval = 2.5) -> some View {
        modifier(RBToastModifier(isPresented: isPresented, style: style, text: text, duration: duration))
    }
}

#Preview {
    ZStack {
        RBColor.bg.ignoresSafeArea()
        ToastView(style: .success, text: "Auto-book reserved your table")
    }
}
