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
        tv.textContentType = .none  // Avoid OTP/autofill completion list positioning errors
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
        // Record the latest desired state in the coordinator so deferred closures can re-check it
        // after the AttributeGraph has settled (avoids stale-render focus drops).
        context.coordinator.desiredFirstResponder = isFirstResponder

        // Keep text in sync without bouncing focus
        if uiView.text != text {
            uiView.text = text
            uiView.invalidateIntrinsicContentSize()
        }
        uiView.minHeight = minHeight
        uiView.maxHeight = maxHeight
        uiView.onBackspaceOnEmpty = { onDeleteWhenEmpty?() }

        // Focus: acquire when requested; resign when explicitly cleared (enables animated keyboard dismiss).
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            // Defer to the next run loop tick so any in-flight AttributeGraph cycle (triggered by
            // a text-state update racing the isFirstResponder update) has time to resolve.
            // If the coordinator's desiredFirstResponder flips back to true before the block runs,
            // the resign is cancelled — preventing the stale-render focus drop.
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView else { return }
                if !coordinator.desiredFirstResponder, uiView.isFirstResponder {
                    _ = uiView.resignFirstResponder()
                }
            }
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
        /// Tracks the most-recently-requested first-responder state across renders.
        /// Updated synchronously in updateUIView so deferred resign checks can
        /// re-read the settled value after an AttributeGraph cycle resolves.
        var desiredFirstResponder: Bool = false

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
                DispatchQueue.main.async { [weak self] in
                    self?.isFirstResponder.wrappedValue = true
                }
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if let autoSizing = textView as? AutoSizingTextView, autoSizing.isResignLockActive {
                textView.becomeFirstResponder()
                return
            }
            if isFirstResponder.wrappedValue == true {
                DispatchQueue.main.async { [weak self] in
                    self?.isFirstResponder.wrappedValue = false
                }
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

    /// Refuse resign until this time. Prevents keyboard dismiss during tab expand/collapse.
    private var refuseResignUntil: Date?
    private var lockObserver: Any?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        lockObserver = NotificationCenter.default.addObserver(
            forName: .quickInputLockFocus, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refuseResignUntil = Date().addingTimeInterval(0.6)
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        if let obs = lockObserver { NotificationCenter.default.removeObserver(obs) }
    }

    override func resignFirstResponder() -> Bool {
        if let until = refuseResignUntil, Date() < until {
            return false
        }
        refuseResignUntil = nil
        return super.resignFirstResponder()
    }

    /// True when we should refuse resign and re-acquire if end-editing fires.
    var isResignLockActive: Bool {
        guard let until = refuseResignUntil else { return false }
        return Date() < until
    }

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
