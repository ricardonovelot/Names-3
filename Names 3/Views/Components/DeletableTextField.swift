import SwiftUI
import UIKit

struct DeletableTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFirstResponder: Bool
    var onDeleteWhenEmpty: (() -> Void)?
    var onReturn: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFirstResponder: $isFirstResponder, onReturn: onReturn)
    }

    func makeUIView(context: Context) -> BackspaceAwareTextField {
        let tf = BackspaceAwareTextField()
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.returnPressed(_:)), for: .editingDidEndOnExit)
        tf.placeholder = placeholder
        tf.font = .preferredFont(forTextStyle: .body)
        tf.returnKeyType = .send

        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType = .no
        tf.smartQuotesType = .no
        tf.smartDashesType = .no
        tf.smartInsertDeleteType = .no

        tf.onDeleteWhenEmpty = { onDeleteWhenEmpty?() }
        if isFirstResponder {
            tf.becomeFirstResponder()
        }
        return tf
    }

    func updateUIView(_ uiView: BackspaceAwareTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var isFirstResponder: Binding<Bool>
        var onReturn: (() -> Void)?

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, onReturn: (() -> Void)?) {
            self.text = text
            self.isFirstResponder = isFirstResponder
            self.onReturn = onReturn
        }

        @objc func textChanged(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        @objc func returnPressed(_ sender: UITextField) {
            onReturn?()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onReturn?()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFirstResponder.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFirstResponder.wrappedValue = false
        }
    }
}

final class BackspaceAwareTextField: UITextField {
    var onDeleteWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onDeleteWhenEmpty?()
        }
        super.deleteBackward()
    }
}