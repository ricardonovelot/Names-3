import SwiftUI

struct QuizTextField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    let placeholder: String
    let isDisabled: Bool
    let onSubmit: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var isAccessibilityFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .regular, design: .default))
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .disabled(isDisabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isFocused ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
                .focused($isFocused)
                .accessibilityFocused($isAccessibilityFocused)
                .accessibilityLabel("Name input")
                .accessibilityHint("Type the name of the person shown")
                .onSubmit(onSubmit)
            
            SubmitButton(
                text: text,
                isDisabled: isDisabled,
                action: onSubmit
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

private struct SubmitButton: View {
    let text: String
    let isDisabled: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    private var canSubmit: Bool {
        !isDisabled && !text.isEmpty
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(
                    canSubmit ? Color.accentColor : Color.secondary.opacity(0.3)
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .disabled(!canSubmit)
        .accessibilityLabel("Submit answer")
        .accessibilityHint(canSubmit ? "Submit your answer" : "Enter a name first")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}