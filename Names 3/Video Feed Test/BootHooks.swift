import SwiftUI

private struct FirstFrameReporter: ViewModifier {
    @State private var posted = false
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .onAppear {
                        if !posted {
                            Task { await PhaseGate.shared.mark(.firstFrame) }
                            Diagnostics.log("Boot: firstFrame")
                            posted = true
                        }
                    }
            )
    }
}

extension View {
    func reportFirstFrame() -> some View { modifier(FirstFrameReporter()) }
}