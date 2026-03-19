import UIKit
import SwiftUI
import SwiftData
import Combine
import TipKit
import os

// MARK: - Modal State Bridge

/// ObservableObject that bridges UIKit state → SwiftUI sheet presentations.
@MainActor
final class ContactDetailsModalState: ObservableObject {
    @Published var showDatePicker = false
    @Published var showTagPicker = false
    @Published var showPhotoFacesSheet = false
    @Published var noteBeingEdited: Note?
    @Published var showNoteDatePicker = false
    @Published var faceDetectionViewModel: FaceDetectionViewModel?
}

// MARK: - Modals Container View

/// Zero-size SwiftUI host that owns all sheet/alert presentations for ContactDetailsViewController.
private struct ContactDetailsModalsView: View {
    @Bindable var contact: Contact
    let modelContext: ModelContext
    @ObservedObject var photoCoordinator: ContactPhotoSelectorCoordinator
    @ObservedObject var faceCoordinator: FaceRecognitionCoordinator
    @ObservedObject var state: ContactDetailsModalState

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .modifier(ContactPhotoSelectorModifier(
                contact: contact,
                coordinator: photoCoordinator,
                modelContext: modelContext,
                faceDetectionViewModel: Binding(
                    get: { state.faceDetectionViewModel },
                    set: { state.faceDetectionViewModel = $0 }
                ),
                onPhotoApplied: {}
            ))
            .sheet(isPresented: $state.showDatePicker) {
                CustomDatePicker(contact: contact)
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $state.showTagPicker) {
                TagPickerView(mode: .contactToggle(contact: contact))
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $state.showNoteDatePicker) {
                NavigationStack {
                    VStack {
                        DatePicker(
                            "Select Date",
                            selection: Binding(
                                get: { state.noteBeingEdited?.creationDate ?? Date() },
                                set: {
                                    if let note = state.noteBeingEdited {
                                        note.creationDate = $0
                                        try? modelContext.save()
                                    }
                                }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                        Spacer()
                        Button("Done") { state.showNoteDatePicker = false }
                            .padding()
                    }
                    .navigationBarTitle("Edit Note Date", displayMode: .inline)
                }
            }
            .sheet(isPresented: $faceCoordinator.showingResults) {
                FaceRecognitionResultsView(
                    contact: contact,
                    foundCount: faceCoordinator.foundFacesCount,
                    coordinator: faceCoordinator
                )
            }
            .sheet(isPresented: $state.showPhotoFacesSheet) {
                ContactPhotoFacesSheet(
                    contact: contact,
                    coordinator: faceCoordinator,
                    onDismiss: { state.showPhotoFacesSheet = false }
                )
                .environment(\.modelContext, modelContext)
            }
            .alert("Error", isPresented: .constant(faceCoordinator.errorMessage != nil)) {
                Button("OK") { faceCoordinator.errorMessage = nil }
            } message: {
                if let error = faceCoordinator.errorMessage {
                    Text(error)
                }
            }
    }
}

// MARK: - Glass Container Modifier (local copy; mirrors GlassContainerWhenPhotoModifier)

private struct ContactDetailsGlassModifier: ViewModifier {
    let hasPhoto: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), hasPhoto {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

// MARK: - Header SwiftUI View

private struct ContactDetailsHeaderView: View {
    @Bindable var contact: Contact
    let hasNoNotes: Bool
    let noNotesLayout: ContactDetailsNoNotesLayoutPreference
    let onPhotoTapped: () -> Void
    let onCameraTapped: () -> Void
    let onTagsTapped: () -> Void
    let onDateTapped: () -> Void
    let onAddNoteTapped: () -> Void

    /// Controls whether `axis: .vertical` TextFields are in the SwiftUI view hierarchy.
    ///
    /// Background: `TextField(axis: .vertical)` creates a `SwiftUI.VerticalTextView` in UIKit.
    /// The iOS text input extension scans ALL VerticalTextViews in the window at `viewDidAppear`
    /// time. If the enclosing UIHostingController has not yet received a valid window-coordinate
    /// frame (which happens while the UINavigationController push animation is running), the
    /// extension gets a null global rect, fails to position its completion UI, and its cleanup
    /// path calls `dismiss` on the presenting UIViewController — spuriously dismissing the
    /// contact details screen before the user has done anything.
    ///
    /// Fix: withhold the editable TextFields from the hierarchy for 450ms (past `viewDidAppear`)
    /// and substitute read-only `Text` placeholders. After 450ms the push animation is complete,
    /// the hosting controller has a valid frame, and the text input extension can position itself
    /// correctly. The placeholder-to-TextField swap is local to the UIHostingController and never
    /// touches ContentViewModel, so NavigationStack is unaffected.
    @State private var textFieldsReady = false

    private var image: UIImage { UIImage(data: contact.photo) ?? UIImage() }
    private var hasPhoto: Bool { image != UIImage() }
    private var photoGradientStartColor: Color? { contact.photoGradientColors?.start }

    var body: some View {
        Group {
            if textFieldsReady {
                headerContent
                    .modifier(ContactDetailsGlassModifier(hasPhoto: hasPhoto))
            } else {
                // Placeholder container with same dimensions, no TextFields
                headerPlaceholder
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            textFieldsReady = true
        }
    }

    @ViewBuilder
    private var headerPlaceholder: some View {
        ZStack(alignment: .bottom) {
            if hasPhoto {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
            }
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(contact.name?.isEmpty == false ? contact.name! : "")
                        .font(.system(size: 36, weight: .bold))
                        .lineLimit(4)
                        .foregroundColor(hasPhoto ? .white : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        if !hasPhoto {
                            Button { } label: { Image(systemName: "info.circle") }
                                .disabled(true)
                            Button { } label: { Image(systemName: "calendar") }
                                .disabled(true)
                            Button { } label: { Image(systemName: "tag") }
                                .disabled(true)
                        }
                    }
                    .font(.system(size: 20))
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 200)
    }

    @ViewBuilder
    private var headerContent: some View {
        ZStack(alignment: .bottom) {
            if hasPhoto {
                Button { onPhotoTapped() } label: {
                    GeometryReader { proxy in
                        let size = proxy.size
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: size.height)
                            .overlay {
                                if let startColor = photoGradientStartColor {
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: startColor.opacity(0.0), location: 0.5),
                                            .init(color: startColor.opacity(0.5), location: 0.75),
                                            .init(color: startColor, location: 0.9)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                } else {
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: .black.opacity(0.0), location: 0.5),
                                            .init(color: .black.opacity(0.2), location: 0.7),
                                            .init(color: .black.opacity(0.8), location: 0.95)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                            }
                    }
                    .frame(height: 400)
                    .clipped()
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityLabel("\(contact.displayName)'s photo")
                .accessibilityHint("Double tap to change photo or find similar faces")
            }

            VStack(spacing: 0) {
                // Name + buttons row
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom, spacing: 12) {
                        if textFieldsReady {
                            TextField(
                                "Name",
                                text: $contact.name ?? "",
                                prompt: Text("Name")
                                    .foregroundColor(hasPhoto ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText)),
                                axis: .vertical
                            )
                            .textContentType(.none)
                            .font(.system(size: 36, weight: .bold))
                            .lineLimit(4)
                            .foregroundColor(hasPhoto ? .white : .primary)
                        } else {
                            Text(contact.name?.isEmpty == false ? contact.name! : "")
                                .font(.system(size: 36, weight: .bold))
                                .lineLimit(4)
                                .foregroundColor(hasPhoto ? .white : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 8) {
                            if !hasPhoto {
                                Button { onCameraTapped() } label: {
                                    Image(systemName: "camera")
                                        .font(.system(size: 18))
                                        .frame(width: 44, height: 44)
                                        .foregroundColor(.blue)
                                        .liquidGlass(in: Circle(), stroke: true, style: .regular)
                                }
                                .accessibilityLabel("Add photo for \(contact.displayName)")
                            }
                            Button { onTagsTapped() } label: {
                                if !(contact.tags?.isEmpty ?? true) {
                                    Text((contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
                                        .foregroundColor(hasPhoto ? .white : Color(.secondaryLabel))
                                        .font(.system(size: 15, weight: .medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .frame(minWidth: 44)
                                        .contentShape(Rectangle())
                                        .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), stroke: true, style: .regular)
                                } else {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 18))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                        .foregroundColor(hasPhoto ? .purple.mix(with: .white, by: 0.3) : .purple)
                                        .liquidGlass(in: Circle(), stroke: true, style: .regular)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Date display
                    HStack {
                        Spacer()
                        Button { onDateTapped() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 13, weight: .medium))
                                Text(formatMetDate(contact.timestamp, isLongAgo: contact.isMetLongAgo))
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(hasPhoto ? .white.opacity(0.9) : Color(UIColor.secondaryLabel))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), stroke: true, style: .regular)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal)

                // Add-note banner (when no notes and preference says show banner)
                if hasNoNotes, noNotesLayout == .addNoteBanner {
                    Button { onAddNoteTapped() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(hasPhoto ? .white.opacity(0.9) : .accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add your first note")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(hasPhoto ? .white : .primary)
                                Text("Use the bar below to remember details")
                                    .font(.caption)
                                    .foregroundColor(hasPhoto ? .white.opacity(0.8) : .secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(hasPhoto ? .white.opacity(0.7) : .secondary)
                        }
                        .padding(16)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true, style: .clear)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 12)
                }

                // Summary field — guarded by textFieldsReady (see property comment above).
                if textFieldsReady {
                    TextField(
                        "",
                        text: $contact.summary ?? "",
                        prompt: Text("Main Note")
                            .foregroundColor(hasPhoto ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor: .placeholderText)),
                        axis: .vertical
                    )
                    .textContentType(.none)
                    .lineLimit(2...)
                    .padding(16)
                    .foregroundStyle(hasPhoto ? Color(uiColor: .lightText) : Color.primary)
                    .textFieldStyle(.plain)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), stroke: true, style: .clear)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .contentShape(.rect)
                } else {
                    // Non-interactive placeholder with identical visual footprint.
                    Group {
                        if let summary = contact.summary, !summary.isEmpty {
                            Text(summary)
                                .foregroundStyle(hasPhoto ? Color(uiColor: .lightText) : Color.primary)
                        } else {
                            Text("Main Note")
                                .foregroundStyle(hasPhoto ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor: .placeholderText))
                        }
                    }
                    .lineLimit(2)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), stroke: true, style: .clear)
                    .padding(.horizontal)
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
    }

    private func formatMetDate(_ date: Date, isLongAgo: Bool) -> String {
        if isLongAgo { return "Met long ago" }
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) { return "Met today" }
        if calendar.isDateInYesterday(date) { return "Met yesterday" }
        let components = calendar.dateComponents([.day], from: date, to: now)
        if let days = components.day, days > 0 {
            if days <= 7 { return "Met \(days) days ago" }
            if days <= 14 { let w = days / 7; return w == 1 ? "Met 1 week ago" : "Met \(w) weeks ago" }
        }
        return "Met \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Note Card View

private struct NoteCardView: View {
    @Bindable var note: Note
    let isHighlighted: Bool
    let onEditDate: () -> Void
    @Environment(\.modelContext) private var modelContext

    /// Same rationale as `ContactDetailsHeaderView.textFieldsReady`.
    /// `TextField(axis: .vertical)` creates a `SwiftUI.VerticalTextView` in UIKit.
    /// The iOS text input extension scans ALL VerticalTextViews at viewDidAppear time;
    /// cells that are already in the initial viewport produce a null global rect while
    /// the push animation is running, and the extension's cleanup path calls dismiss
    /// on the presenting VC — spuriously popping contact details.
    /// Withhold the editable TextField for 450 ms (past viewDidAppear + animation settle)
    /// and show a read-only Text placeholder. The swap is entirely local and never writes
    /// to ContentViewModel, so NavigationStack is unaffected.
    @State private var textFieldsReady = false

    var body: some View {
        Group {
            if textFieldsReady {
                noteContentWithTextField
            } else {
                noteContentPlaceholder
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            textFieldsReady = true
        }
    }

    private var noteContentWithTextField: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Note Content", text: $note.content, axis: .vertical)
                .textContentType(.none)
                .font(.body)
                .lineLimit(2...)
                .onChange(of: note.content) { _, _ in try? modelContext.save() }
            HStack {
                Button { onEditDate() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 11))
                        Text(note.creationDate, style: .date).font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true, style: .clear)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(isHighlighted ? 0.75 : 0), lineWidth: 2)
        )
    }

    private var noteContentPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(note.content.isEmpty ? " " : note.content)
                .font(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 11))
                        Text(note.creationDate, style: .date).font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(true)
                Spacer()
            }
        }
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true, style: .clear)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(isHighlighted ? 0.75 : 0), lineWidth: 2)
        )
    }
}

// MARK: - Empty State View

private struct ContactEmptyStateView: View {
    let contact: Contact
    let onAddNote: () -> Void

    var body: some View {
        Button { onAddNote() } label: {
            VStack(spacing: 12) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No notes yet")
                    .font(.headline)
                Text("Tap to use the bar below and add a note about \(contact.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true, style: .clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Table View Cells

private final class ContactHeaderCell: UITableViewCell {
    static let reuseID = "ContactHeaderCell"
    private weak var hostingController: UIHostingController<AnyView>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        contact: Contact,
        hasNoNotes: Bool,
        noNotesLayout: ContactDetailsNoNotesLayoutPreference,
        modelContext: ModelContext,
        parentVC: UIViewController,
        onPhotoTapped: @escaping () -> Void,
        onCameraTapped: @escaping () -> Void,
        onTagsTapped: @escaping () -> Void,
        onDateTapped: @escaping () -> Void,
        onAddNoteTapped: @escaping () -> Void
    ) {
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let headerView = ContactDetailsHeaderView(
            contact: contact,
            hasNoNotes: hasNoNotes,
            noNotesLayout: noNotesLayout,
            onPhotoTapped: onPhotoTapped,
            onCameraTapped: onCameraTapped,
            onTagsTapped: onTagsTapped,
            onDateTapped: onDateTapped,
            onAddNoteTapped: onAddNoteTapped
        )
        let hc = UIHostingController(rootView: AnyView(headerView.environment(\.modelContext, modelContext)))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        parentVC.addChild(hc)
        contentView.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        hc.didMove(toParent: parentVC)
        hostingController = hc
    }
}

private final class NoteCardHostingCell: UITableViewCell {
    static let reuseID = "NoteCardHostingCell"
    private weak var hostingController: UIHostingController<AnyView>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        note: Note,
        isHighlighted: Bool,
        modelContext: ModelContext,
        parentVC: UIViewController,
        onEditDate: @escaping () -> Void
    ) {
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let cardView = NoteCardView(note: note, isHighlighted: isHighlighted, onEditDate: onEditDate)
        let hc = UIHostingController(rootView: AnyView(cardView.environment(\.modelContext, modelContext)))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        parentVC.addChild(hc)
        contentView.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
        hc.didMove(toParent: parentVC)
        hostingController = hc
    }
}

private final class EmptyStateHostingCell: UITableViewCell {
    static let reuseID = "EmptyStateHostingCell"
    private weak var hostingController: UIHostingController<AnyView>?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(contact: Contact, parentVC: UIViewController, onAddNote: @escaping () -> Void) {
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let emptyView = ContactEmptyStateView(contact: contact, onAddNote: onAddNote)
        let hc = UIHostingController(rootView: AnyView(emptyView))
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        parentVC.addChild(hc)
        contentView.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
        hc.didMove(toParent: parentVC)
        hostingController = hc
    }
}

// MARK: - ContactDetailsViewController

final class ContactDetailsViewController: UIViewController {

    private static let navLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Names3",
        category: "Navigation"
    )

    // MARK: - Dependencies

    let contact: Contact
    private let modelContext: ModelContext
    let photoSelectorCoordinator: ContactPhotoSelectorCoordinator
    let faceRecognitionCoordinator: FaceRecognitionCoordinator

    // MARK: - Configuration

    var isCreationFlow: Bool = false
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onBack: (() -> Void)?
    var onRequestAddNote: (() -> Void)?
    var highlightedNoteUUID: UUID?

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let backgroundGradientLayer = CAGradientLayer()
    private var modalsHostingController: UIHostingController<ContactDetailsModalsView>?

    // MARK: - State

    private var activeNotes: [Note] = []
    private var cancellables = Set<AnyCancellable>()
    private var activeHighlightNoteUUID: UUID?
    private let modalState = ContactDetailsModalState()

    private let backButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Back"
        config.image = UIImage(systemName: "chevron.backward")
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 0)
        return UIButton(configuration: config)
    }()

    // MARK: - Init

    init(
        contact: Contact,
        modelContext: ModelContext,
        photoSelectorCoordinator: ContactPhotoSelectorCoordinator,
        faceRecognitionCoordinator: FaceRecognitionCoordinator,
        highlightedNoteUUID: UUID? = nil
    ) {
        self.contact = contact
        self.modelContext = modelContext
        self.photoSelectorCoordinator = photoSelectorCoordinator
        self.faceRecognitionCoordinator = faceRecognitionCoordinator
        self.highlightedNoteUUID = highlightedNoteUUID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupTableView()
        setupModalsHost()
        setupNavigationBar()
        reloadNotes()
        updateBackgroundGradient()
        subscribeToNotifications()
        Task { await updateDerivedBackgroundIfNeeded() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Self.navLogger.debug("⬡ ContactDetailsVC viewWillAppear — contact=\(self.contact.displayName) isMovingToParent=\(self.isMovingToParent) onBack=\(self.onBack != nil) navStack=\(self.navigationController?.viewControllers.count ?? -1)")
        TipManager.shared.donateContactViewed()
        reloadNotes()
        // Become the delegate for the interactive-pop gesture so we can decide
        // whether it should fire (see UIGestureRecognizerDelegate extension below).
        navigationController?.interactivePopGestureRecognizer?.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Self.navLogger.debug("⬡ ContactDetailsVC viewDidAppear — contact=\(self.contact.displayName) navStack=\(self.navigationController?.viewControllers.count ?? -1)")
        // Force a synchronous layout pass so every subview (including any VerticalTextViews
        // already in the hierarchy) receives a valid window-coordinate frame BEFORE the iOS
        // text-input extension's asynchronous OTP scan fires. If a VerticalTextView has a
        // null global rect when the scan fires, the extension's cleanup path calls
        // setViewControllers([root]) and dismisses this screen. Belt-and-suspenders alongside
        // the textFieldsReady guards in ContactDetailsHeaderView and NoteCardView.
        view.window?.layoutIfNeeded()

        // DIAGNOSTIC: Enumerate every UITextView subclass in the window to identify the
        // source of the "Refusing to display OTP completion list relative to null rect" error.
        // The error names a SwiftUI.VerticalTextView; this scan will tell us exactly which
        // view it is, its class, its superview chain, and whether it has a window.
        if let window = view.window {
            let allTextViews = Self.collectTextViews(in: window)
            Self.navLogger.debug("⬡ UITextView scan — found \(allTextViews.count) UITextView(s) in window:")
            for tv in allTextViews {
                let windowRect = tv.window.map { w in w.convert(tv.bounds, from: tv) } ?? CGRect.null
                let frameStr = "(\(tv.frame.origin.x), \(tv.frame.origin.y); \(tv.frame.size.width)×\(tv.frame.size.height))"
                let wRectStr = "(\(windowRect.origin.x), \(windowRect.origin.y); \(windowRect.size.width)×\(windowRect.size.height))"
                let superChain = Self.superviewChain(of: tv, limit: 5)
                Self.navLogger.debug("  📝 class=\(type(of: tv)) addr=\(String(format: "0x%x", UInt(bitPattern: ObjectIdentifier(tv)))) frame=\(frameStr) windowRect=\(wRectStr) hasWindow=\(tv.window != nil) text='\(tv.text ?? "")' superviews=[\(superChain)]")
            }
        }

        animateBackButton()
        scrollToHighlightedNote()
    }

    private static func collectTextViews(in view: UIView) -> [UITextView] {
        var result: [UITextView] = []
        if let tv = view as? UITextView { result.append(tv) }
        for sub in view.subviews { result += collectTextViews(in: sub) }
        return result
    }

    private static func superviewChain(of view: UIView, limit: Int) -> String {
        var parts: [String] = []
        var current: UIView? = view.superview
        for _ in 0..<limit {
            guard let v = current else { break }
            parts.append(String(describing: type(of: v)))
            current = v.superview
        }
        return parts.joined(separator: " → ")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Self.navLogger.debug("⬡ ContactDetailsVC viewWillDisappear — contact=\(self.contact.displayName) isMovingFromParent=\(self.isMovingFromParent) navStack=\(self.navigationController?.viewControllers.count ?? -1)")
        NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        // When the user swipe-backs (interactive pop), UIKit pops the VC and SwiftUI
        // updates the NavigationPath automatically — but our custom backTapped() is
        // never called, so the quick-input lock notification is never posted.
        // Post it here for every programmatic-or-gesture pop so the quick input bar
        // always returns to its idle state regardless of how the user navigated back.
        if isMovingFromParent {
            Self.navLogger.debug("⬡ ContactDetailsVC isMovingFromParent=true — posting quickInputLockFocus")
            NotificationCenter.default.post(name: .quickInputLockFocus, object: nil)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Self.navLogger.debug("⬡ ContactDetailsVC viewDidDisappear — contact=\(self.contact.displayName) isMovingFromParent=\(self.isMovingFromParent)")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundGradientLayer.frame = view.bounds
    }

    // MARK: - Setup

    private func setupBackground() {
        view.backgroundColor = UIColor.systemGroupedBackground
        view.layer.insertSublayer(backgroundGradientLayer, at: 0)
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 200
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ContactHeaderCell.self, forCellReuseIdentifier: ContactHeaderCell.reuseID)
        tableView.register(NoteCardHostingCell.self, forCellReuseIdentifier: NoteCardHostingCell.reuseID)
        tableView.register(EmptyStateHostingCell.self, forCellReuseIdentifier: EmptyStateHostingCell.reuseID)
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupModalsHost() {
        let modalsView = ContactDetailsModalsView(
            contact: contact,
            modelContext: modelContext,
            photoCoordinator: photoSelectorCoordinator,
            faceCoordinator: faceRecognitionCoordinator,
            state: modalState
        )
        let hc = UIHostingController(rootView: modalsView)
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hc)
        view.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.widthAnchor.constraint(equalToConstant: 0),
            hc.view.heightAnchor.constraint(equalToConstant: 0),
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
        hc.didMove(toParent: self)
        modalsHostingController = hc
    }

    private func setupNavigationBar() {
        navigationItem.hidesBackButton = true
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: buildOptionsMenu()
        )

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
    }

    private func buildOptionsMenu() -> UIMenu {
        var actions: [UIAction] = []
        if !contact.photo.isEmpty {
            actions.append(UIAction(title: "Change Photo", image: UIImage(systemName: "photo")) { [weak self] _ in
                self?.photoSelectorCoordinator.startSelection()
            })
        }
        actions.append(UIAction(title: "Find Similar Faces", image: UIImage(systemName: "face.smiling")) { [weak self] _ in
            self?.modalState.showPhotoFacesSheet = true
        })
        actions.append(UIAction(title: "Duplicate") { _ in })
        actions.append(UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            contact.isArchived = true
            contact.archivedDate = Date()
            try? modelContext.save()
            navigationController?.popViewController(animated: true)
        })
        return UIMenu(children: actions)
    }

    private func subscribeToNotifications() {
        NotificationCenter.default
            .publisher(for: .contactsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Only reload while this VC is actually attached to a window.
                // If two contacts are stacked (a pre-existing bug being fixed elsewhere)
                // the background VC would otherwise thrash its table during transitions.
                guard view.window != nil else { return }
                reloadNotes()
                updateBackgroundGradient()
                tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
            }
            .store(in: &cancellables)
    }

    // MARK: - Notes

    private func reloadNotes() {
        activeNotes = (contact.notes ?? [])
            .filter { !$0.isArchived }
            .sorted { $0.creationDate > $1.creationDate }
    }

    // MARK: - Background Gradient

    private func updateBackgroundGradient() {
        guard let colors = contact.photoGradientColors else {
            backgroundGradientLayer.colors = nil
            return
        }
        let screenHeight = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height
        let headerFraction = Float(min(1.0, 400.0 / screenHeight))
        backgroundGradientLayer.colors = [
            UIColor(colors.start).cgColor,
            UIColor(colors.start).cgColor,
            UIColor(colors.end).cgColor
        ]
        backgroundGradientLayer.locations = [0, NSNumber(value: headerFraction), 1]
        backgroundGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func updateDerivedBackgroundIfNeeded() async {
        let img = UIImage(data: contact.photo) ?? UIImage()
        guard img != UIImage(), !contact.photo.isEmpty, !contact.hasPhotoGradient else { return }
        let result = await Task.detached(priority: .userInitiated) {
            ImageAccessibleBackground.accessibleColors(from: img)
        }.value
        await MainActor.run {
            if result != nil {
                ImageAccessibleBackground.updateContactPhotoGradient(contact, image: img)
                try? modelContext.save()
                updateBackgroundGradient()
            }
        }
    }

    // MARK: - Navigation

    @objc private func backTapped() {
        Self.navLogger.debug("⬡ backTapped — contact=\(self.contact.displayName) hasOnBack=\(self.onBack != nil)")
        if let onBack {
            // Navigation-stack context: let SwiftUI pop by modifying the path.
            // Calling popViewController here too would double-pop and desync the NavigationPath.
            onBack()
        } else {
            // Sheet context (isCreationFlow via ContactSelectView): dismiss the presenting nav controller.
            navigationController?.presentingViewController?.dismiss(animated: true)
                ?? presentingViewController?.dismiss(animated: true)
        }
    }

    private func animateBackButton() {
        UIView.animate(withDuration: 0.3) {
            var config = self.backButton.configuration
            config?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            self.backButton.configuration = config
        }
    }

    // MARK: - Highlight Scroll

    private func scrollToHighlightedNote() {
        guard let targetUUID = highlightedNoteUUID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if let row = activeNotes.firstIndex(where: { $0.uuid == targetUUID }) {
                let ip = IndexPath(row: row, section: 1)
                tableView.scrollToRow(at: ip, at: .middle, animated: true)
                try? await Task.sleep(for: .milliseconds(450))
                activeHighlightNoteUUID = targetUUID
                tableView.reloadRows(at: [ip], with: .none)
                try? await Task.sleep(for: .seconds(2))
                activeHighlightNoteUUID = nil
                tableView.reloadRows(at: [ip], with: .none)
            }
        }
    }

    // MARK: - Note Actions

    private func showNoteDatePicker(for note: Note) {
        modalState.noteBeingEdited = note
        modalState.showNoteDatePicker = true
    }

    private func deleteNote(_ note: Note) {
        note.isArchived = true
        note.archivedDate = Date()
        try? modelContext.save()
        reloadNotes()
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }

    private func currentNoNotesLayout() -> ContactDetailsNoNotesLayoutPreference {
        ContactDetailsNoNotesLayoutPreference(
            rawValue: UserDefaults.standard.string(forKey: ContactDetailsNoNotesLayoutPreference.userDefaultsKey) ?? ""
        ) ?? .summaryFirst
    }

    private func showPhotoActionSheet() {
        let alert = UIAlertController(
            title: "Photo",
            message: "Choose an action for \(contact.displayName)'s photo",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Change Photo", style: .default) { [weak self] _ in
            self?.photoSelectorCoordinator.startSelection()
        })
        alert.addAction(UIAlertAction(title: "Find Similar Faces", style: .default) { [weak self] _ in
            self?.modalState.showPhotoFacesSheet = true
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ContactDetailsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        if activeNotes.isEmpty, currentNoNotesLayout() == .emptyStatePrompt { return 1 }
        return activeNotes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: ContactHeaderCell.reuseID, for: indexPath) as! ContactHeaderCell
            cell.configure(
                contact: contact,
                hasNoNotes: activeNotes.isEmpty,
                noNotesLayout: currentNoNotesLayout(),
                modelContext: modelContext,
                parentVC: self,
                onPhotoTapped: { [weak self] in self?.showPhotoActionSheet() },
                onCameraTapped: { [weak self] in self?.photoSelectorCoordinator.startSelection() },
                onTagsTapped: { [weak self] in self?.modalState.showTagPicker = true },
                onDateTapped: { [weak self] in self?.modalState.showDatePicker = true },
                onAddNoteTapped: { [weak self] in self?.onRequestAddNote?() }
            )
            return cell
        }

        if activeNotes.isEmpty, currentNoNotesLayout() == .emptyStatePrompt {
            let cell = tableView.dequeueReusableCell(withIdentifier: EmptyStateHostingCell.reuseID, for: indexPath) as! EmptyStateHostingCell
            cell.configure(contact: contact, parentVC: self, onAddNote: { [weak self] in self?.onRequestAddNote?() })
            return cell
        }

        let note = activeNotes[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: NoteCardHostingCell.reuseID, for: indexPath) as! NoteCardHostingCell
        cell.configure(
            note: note,
            isHighlighted: activeHighlightNoteUUID == note.uuid,
            modelContext: modelContext,
            parentVC: self,
            onEditDate: { [weak self] in self?.showNoteDatePicker(for: note) }
        )
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ContactDetailsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, !activeNotes.isEmpty, indexPath.row < activeNotes.count else { return nil }
        let note = activeNotes[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteNote(note)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        let editDateAction = UIContextualAction(style: .normal, title: "Edit Date") { [weak self] _, _, completion in
            self?.showNoteDatePicker(for: note)
            completion(true)
        }
        editDateAction.image = UIImage(systemName: "calendar")

        return UISwipeActionsConfiguration(actions: [deleteAction, editDateAction])
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool { false }
}

// MARK: - UIGestureRecognizerDelegate

extension ContactDetailsViewController: UIGestureRecognizerDelegate {

    /// Allow the interactive-pop gesture only when we are in a proper NavigationStack
    /// context (onBack is set). In the sheet / creation-flow context there is no
    /// NavigationStack handler, so we block the gesture to prevent desync.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
            return true
        }
        let allow = onBack != nil
        Self.navLogger.debug("⬡ interactivePopGesture shouldBegin=\(allow) contact=\(self.contact.displayName)")
        return allow
    }
}
