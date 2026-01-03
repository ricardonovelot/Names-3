import SwiftUI
import UIKit

struct DeletableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var onDeleteWhenEmpty: (() -> Void)?
    var onReturn: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFirstResponder: $isFirstResponder, onReturn: onReturn, onHeightChange: onHeightChange)
    }

    func makeUIView(context: Context) -> BackspaceAwareTextView {
        let tv = BackspaceAwareTextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        tv.textContainer.lineFragmentPadding = 0
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no

        tv.onDeleteWhenEmpty = { onDeleteWhenEmpty?() }
        tv.text = text
        if isFirstResponder {
            tv.becomeFirstResponder()
        }
        context.coordinator.recalculateHeight(for: tv)
        return tv
    }

    func updateUIView(_ uiView: BackspaceAwareTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        context.coordinator.recalculateHeight(for: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFirstResponder: Binding<Bool>
        var onReturn: (() -> Void)?
        var onHeightChange: ((CGFloat) -> Void)?

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, onReturn: (() -> Void)?, onHeightChange: ((CGFloat) -> Void)?) {
            self.text = text
            self.isFirstResponder = isFirstResponder
            self.onReturn = onReturn
            self.onHeightChange = onHeightChange
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text ?? ""
            recalculateHeight(for: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFirstResponder.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFirstResponder.wrappedValue = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                onReturn?()
                return false
            }
            return true
        }

        func recalculateHeight(for textView: UITextView) {
            let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width > 0 ? textView.bounds.width : UIScreen.main.bounds.width, height: .greatestFiniteMagnitude))
            let height = max(22, fitting.height)
            onHeightChange?(height)
        }
    }
}

final class BackspaceAwareTextView: UITextView {
    var onDeleteWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onDeleteWhenEmpty?()
        }
        super.deleteBackward()
    }
}