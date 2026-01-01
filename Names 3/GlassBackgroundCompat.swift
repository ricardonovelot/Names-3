import SwiftUI

enum LiquidGlassStyle {
    case regular
    case clear
}

extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        liquidGlass(in: shape, stroke: true)
    }

    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, stroke: Bool) -> some View {
        liquidGlass(in: shape, stroke: stroke, style: .regular)
    }

    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, stroke: Bool = true, style: LiquidGlassStyle) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .regular:
                self.glassEffect(.regular, in: shape)
            case .clear:
                self.glassEffect(.clear, in: shape)
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    if stroke {
                        shape.stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                }
        }
    }
}

@available(iOS 26.0, *)
private extension View {
    func _liquidGlass18<S: InsettableShape>(in shape: S) -> some View {
        self.glassEffect(.regular, in: shape)
    }
}