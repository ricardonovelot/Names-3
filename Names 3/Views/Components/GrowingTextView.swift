import SwiftUI
import UIKit

struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    var minHeight: CGFloat = 22
    var maxHeight: CGFloat = 140
    var onDeleteWhenEmpty: (() -> Void)?
    var onReturn: (() -> Void)?

    func makeUIView(context: Context) -> AutoSizingTextView {
        let tv = AutoSizingTextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = .preferredFont(forTextStyle: .body)
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.returnKeyType = .send
        tv.minHeight = minHeight
        tv.maxHeight = maxHeight
        tv.onBackspaceOnEmpty = { onDeleteWhenEmpty?() }

        tv.text = text
        tv.invalidateIntrinsicContentSize()

        if isFirstResponder {
            DispatchQueue.main.async {
                tv.becomeFirstResponder()
            }
        }
        return tv
    }

    func updateUIView(_ uiView: AutoSizingTextView, context: Context) {
        // Keep text in sync without bouncing focus
        if uiView.text != text {
            uiView.text = text
            uiView.invalidateIntrinsicContentSize()
        }
        uiView.minHeight = minHeight
        uiView.maxHeight = maxHeight
        uiView.onBackspaceOnEmpty = { onDeleteWhenEmpty?() }

        // Focus-sticky: only acquire focus when requested; do not resign here.
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFirstResponder: $isFirstResponder,
            onDeleteWhenEmpty: onDeleteWhenEmpty,
            onReturn: onReturn
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFirstResponder: Binding<Bool>
        var onDeleteWhenEmpty: (() -> Void)?
        var onReturn: (() -> Void)?

        init(
            text: Binding<String>,
            isFirstResponder: Binding<Bool>,
            onDeleteWhenEmpty: (() -> Void)?,
            onReturn: (() -> Void)?
        ) {
            self.text = text
            self.isFirstResponder = isFirstResponder
            self.onDeleteWhenEmpty = onDeleteWhenEmpty
            self.onReturn = onReturn
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            // Do not trigger chip deletion here; handled by deleteBackward override when empty.
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if isFirstResponder.wrappedValue == false {
                isFirstResponder.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFirstResponder.wrappedValue == true {
                isFirstResponder.wrappedValue = false
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                onReturn?()
                return false
            }
            return true
        }
    }
}

final class AutoSizingTextView: UITextView {
    var minHeight: CGFloat = 22
    var maxHeight: CGFloat = 140
    var onBackspaceOnEmpty: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        let target = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width, height: CGFloat.greatestFiniteMagnitude))
        let clampedH = max(minHeight, min(maxHeight, target.height))
        isScrollEnabled = target.height > maxHeight
        return CGSize(width: UIView.noIntrinsicMetric, height: clampedH)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }

    override var contentSize: CGSize {
        didSet {
            if oldValue != contentSize {
                invalidateIntrinsicContentSize()
            }
        }
    }

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onBackspaceOnEmpty?()
            // Do not call super; nothing to delete; keep focus
        } else {
            super.deleteBackward()
        }
    }
}