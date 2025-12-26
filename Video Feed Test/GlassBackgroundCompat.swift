import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        liquidGlass(in: shape, stroke: true)
    }

    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, stroke: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
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
        self.glassEffect(.clear, in: shape)
    }
}
