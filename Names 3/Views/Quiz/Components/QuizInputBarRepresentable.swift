import SwiftUI
import UIKit

/// UIKit-backed quiz input bar so the keyboard stays up across question changes. We control first responder explicitly instead of relying on SwiftUI FocusState.
struct QuizInputBarRepresentable: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var submitDisabled: Bool
    /// When this value changes (e.g. currentIndex), we re-assert first responder so the keyboard does not dismiss.
    var focusTrigger: Int
    var onSubmit: () -> Void
    /// When true, uses smaller padding and submit button for compact keyboard-dock layout.
    var compact: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> QuizInputBarHostView {
        let host = QuizInputBarHostView()
        host.textField.delegate = context.coordinator
        host.textField.placeholder = placeholder
        host.textField.text = text
        host.textField.autocapitalizationType = .words
        host.textField.autocorrectionType = .no
        host.textField.returnKeyType = .done
        host.textField.font = .systemFont(ofSize: compact ? 16 : 17, weight: .regular)
        host.textField.backgroundColor = .clear
        host.textField.translatesAutoresizingMaskIntoConstraints = false
        host.textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange), for: .editingChanged)

        host.submitButton.translatesAutoresizingMaskIntoConstraints = false
        host.submitButton.addTarget(context.coordinator, action: #selector(Coordinator.submitTapped), for: .touchUpInside)
        host.submitButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        host.submitButton.tintColor = .systemBlue
        host.submitButton.contentVerticalAlignment = .fill
        host.submitButton.contentHorizontalAlignment = .fill
        host.submitButton.imageView?.contentMode = .scaleAspectFit

        host.stackView.axis = .horizontal
        host.stackView.alignment = .center
        host.stackView.addArrangedSubview(host.textFieldContainer)
        host.stackView.addArrangedSubview(host.submitButton)
        host.stackView.spacing = 12
        host.stackView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(host.stackView)

        NSLayoutConstraint.activate([
            host.submitButton.widthAnchor.constraint(equalToConstant: 36),
            host.submitButton.heightAnchor.constraint(equalToConstant: 36),
            host.stackView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            host.stackView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            host.stackView.topAnchor.constraint(equalTo: host.topAnchor),
            host.stackView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        context.coordinator.host = host
        context.coordinator.updateSubmitButtonAppearance(host: host)

        DispatchQueue.main.async {
            host.textField.becomeFirstResponder()
        }
        return host
    }

    func updateUIView(_ host: QuizInputBarHostView, context: Context) {
        if host.textField.text != text {
            host.textField.text = text
        }
        host.textField.placeholder = placeholder
        host.textField.font = .systemFont(ofSize: compact ? 16 : 17, weight: .regular)
        host.applyCompactStyle(compact)
        host.textField.isUserInteractionEnabled = true
        context.coordinator.updateSubmitButtonAppearance(host: host)

        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            host.textField.becomeFirstResponder()
        }
        let focused = host.textField.isFirstResponder
        host.textFieldContainer.layer.borderWidth = focused ? 2 : 0
        host.textFieldContainer.layer.borderColor = focused ? UIColor.systemBlue.cgColor : nil
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: QuizInputBarRepresentable
        weak var host: QuizInputBarHostView?
        var lastFocusTrigger: Int

        init(_ parent: QuizInputBarRepresentable) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
        }

        @objc func textDidChange(_ textField: UITextField) {
            parent.text = textField.text ?? ""
            guard let host else { return }
            updateSubmitButtonAppearance(host: host)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if !parent.submitDisabled, !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parent.onSubmit()
            }
            return true
        }

        @objc func submitTapped() {
            if !parent.submitDisabled, !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parent.onSubmit()
            }
        }

        func updateSubmitButtonAppearance(host: QuizInputBarHostView) {
            let canSubmit = !parent.submitDisabled && !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            host.submitButton.isEnabled = canSubmit
            host.submitButton.tintColor = canSubmit ? .systemBlue : UIColor.placeholderText.withAlphaComponent(0.5)
        }
    }
}

/// Host view that holds the text field (in a rounded container) and submit button.
final class QuizInputBarHostView: UIView {
    let stackView = UIStackView()
    let textFieldContainer = UIView()
    let blurView: UIVisualEffectView
    let textField = UITextField()
    let submitButton = UIButton(type: .system)

    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        super.init(frame: frame)
        blurView.layer.cornerRadius = 12
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        textFieldContainer.backgroundColor = .clear
        textFieldContainer.layer.cornerRadius = 12
        textFieldContainer.layer.cornerCurve = .continuous
        textFieldContainer.translatesAutoresizingMaskIntoConstraints = false
        textFieldContainer.insertSubview(blurView, at: 0)
        textFieldContainer.addSubview(textField)

        let padding: CGFloat = 16
        let verticalPadding: CGFloat = 14
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: textFieldContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: textFieldContainer.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: textFieldContainer.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: textFieldContainer.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: textFieldContainer.leadingAnchor, constant: padding),
            textField.trailingAnchor.constraint(equalTo: textFieldContainer.trailingAnchor, constant: -padding),
            textField.topAnchor.constraint(equalTo: textFieldContainer.topAnchor, constant: verticalPadding),
            textField.bottomAnchor.constraint(equalTo: textFieldContainer.bottomAnchor, constant: -verticalPadding),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyCompactStyle(_ compact: Bool) {
        let radius: CGFloat = compact ? 10 : 12
        textFieldContainer.layer.cornerRadius = radius
        blurView.layer.cornerRadius = radius
        stackView.spacing = compact ? 8 : 12
    }
}
