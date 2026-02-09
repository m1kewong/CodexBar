import AppKit
import SwiftUI

private enum LiquidGlassTokens {
    static let defaultCornerRadius: CGFloat = 14
    static let cardPadding = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
}

private struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    if self.reduceTransparency {
                        shape
                            .fill(Color(nsColor: .windowBackgroundColor)
                                .opacity(self.colorScheme == .dark ? 0.95 : 0.92))
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }

                    shape
                        .strokeBorder(self.strokeGradient, lineWidth: 1)

                    if !self.reduceTransparency {
                        shape
                            .fill(self.sheenGradient)
                            .padding(1)
                            .blendMode(.plusLighter)
                    }
                }
            }
            .clipShape(shape)
            .shadow(
                color: Color.black.opacity(self.colorScheme == .dark ? 0.34 : 0.14),
                radius: self.colorScheme == .dark ? 14 : 10,
                x: 0,
                y: self.colorScheme == .dark ? 8 : 6)
    }

    private var strokeGradient: LinearGradient {
        if self.colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.28),
                    Color.white.opacity(0.08),
                    Color.black.opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.65),
                Color.white.opacity(0.24),
                Color.black.opacity(0.1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }

    private var sheenGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(self.colorScheme == .dark ? 0.18 : 0.34),
                Color.white.opacity(self.colorScheme == .dark ? 0.04 : 0.1),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom)
    }
}

private struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let contentPadding: EdgeInsets

    func body(content: Content) -> some View {
        content
            .padding(self.contentPadding)
            .liquidGlassPanel(cornerRadius: self.cornerRadius)
    }
}

struct LiquidGlassWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            if !self.reduceTransparency {
                RadialGradient(
                    colors: [
                        Color.white.opacity(self.colorScheme == .dark ? 0.08 : 0.18),
                        .clear,
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 460)
                    .blendMode(.screen)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = LiquidGlassTokens.defaultCornerRadius) -> some View {
        self.modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassCard(
        cornerRadius: CGFloat = LiquidGlassTokens.defaultCornerRadius,
        contentPadding: EdgeInsets = LiquidGlassTokens.cardPadding) -> some View
    {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, contentPadding: contentPadding))
    }
}
