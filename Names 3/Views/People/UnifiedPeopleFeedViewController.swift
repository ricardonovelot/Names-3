//
//  UnifiedPeopleFeedViewController.swift
//  Names 3
//
//  UIKit view controller for the unified People-tab feed. One UICollectionView,
//  one diffable data source, three cell types:
//    • ContactCollectionViewCell     — persisted contact (photo + name)
//    • ParsedContactCollectionViewCell — unsaved preview contact
//    • NoteCollectionViewCell        — note (dimmed contact photo + text overlay)
//
//  Filter (all / contacts only / notes only) is applied when building the
//  diffable snapshot; changing it triggers an animated re-apply.
//
//  Section headers reuse ContactsFeedGroupHeaderView. The context menu is
//  suppressed for sections that contain no contacts (notes-only sections).
//

import UIKit
import SwiftData
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Names3",
    category: "UnifiedPeopleFeed"
)

// MARK: - UnifiedPeopleFeedViewController

@MainActor
final class UnifiedPeopleFeedViewController: UIViewController {

    // MARK: - Feed Item

    enum FeedItem: Hashable {
        case contact(UUID, isParsed: Bool)
        case note(UUID)
    }

    // MARK: - Callbacks

    var onContactSelected: ((UUID) -> Void)?
    var onNoteSelected: ((UUID, UUID) -> Void)?
    var onImport: ((UnifiedFeedGroup) -> Void)?
    var onEditDate: ((UnifiedFeedGroup) -> Void)?
    var onEditTag: ((UnifiedFeedGroup) -> Void)?
    var onRenameTag: ((UnifiedFeedGroup) -> Void)?
    var onDeleteAll: ((UnifiedFeedGroup) -> Void)?
    var onChangeDateForContact: ((Contact) -> Void)?
    var onTapHeader: ((UnifiedFeedGroup) -> Void)?
    var onDropRecords: (([ContactDragRecord], UnifiedFeedGroup) -> Void)?

    // MARK: - Subviews

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, FeedItem>!
    private var emptyStateView: ContactsFeedEmptyStateView!

    // MARK: - Data

    /// All groups before filtering (used to resolve drops and header callbacks).
    private var allGroups: [UnifiedFeedGroup] = []
    /// Groups actually present in the snapshot (after empty sections are skipped).
    private var displayedGroups: [UnifiedFeedGroup] = []
    /// O(1) group lookup by section ID.
    private var groupByID: [String: UnifiedFeedGroup] = [:]
    /// O(1) contact lookup by UUID (persisted + parsed).
    private var contactByUUID: [UUID: Contact] = [:]
    /// O(1) note lookup by UUID.
    private var noteByUUID: [UUID: Note] = [:]

    // MARK: - Configuration State

    private let modelContext: ModelContext
    private var currentFilter: PeopleFeedFilter = .people
    private var useSafeTitle: Bool = false
    private var showInitialSyncState: Bool = false
    private var isLowOnDeviceStorage: Bool = false
    private var isOffline: Bool = false

    /// True after we've done the initial scroll-to-bottom (anchor newest at bottom on launch).
    private var didInitialScrollToBottom = false

    // MARK: - Layout Constants

    private enum Layout {
        static let itemSpacing: CGFloat = 10
        static let sectionInset = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16)
        static let columns: Int = 4
    }

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupEmptyStateView()
        setupCollectionView()
        setupDataSource()
        setupKeyboardObserver()
        setupScrollToTopObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didInitialScrollToBottom,
              collectionView.numberOfSections > 0,
              collectionView.bounds.height > 0 else { return }
        didInitialScrollToBottom = true
        scrollToBottom(animated: false)
    }

    private func setupScrollToTopObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollToTopIfNeeded),
            name: .peopleFeedScrollToTop,
            object: nil
        )
    }

    @objc private func scrollToTopIfNeeded() {
        scrollToBottom(animated: true)
    }

    // MARK: - Public API

    func update(
        contacts: [Contact],
        parsedContacts: [Contact],
        notes: [Note],
        filter: PeopleFeedFilter,
        useSafeTitle: Bool,
        showInitialSyncState: Bool,
        isLowOnDeviceStorage: Bool,
        isOffline: Bool
    ) {
        self.currentFilter = filter
        self.useSafeTitle = useSafeTitle
        self.showInitialSyncState = showInitialSyncState
        self.isLowOnDeviceStorage = isLowOnDeviceStorage
        self.isOffline = isOffline

        // Rebuild O(1) lookup tables
        contactByUUID.removeAll(keepingCapacity: true)
        for c in contacts + parsedContacts { contactByUUID[c.uuid] = c }
        noteByUUID.removeAll(keepingCapacity: true)
        for n in notes { noteByUUID[n.uuid] = n }

        let newGroups = UnifiedPeopleFeedView.computeGroups(
            contacts: contacts,
            parsedContacts: parsedContacts,
            notes: notes
        )
        applySnapshot(groups: newGroups, filter: filter)
        updateEmptyState(groups: newGroups, filter: filter)
    }

    // MARK: - Setup

    private func setupEmptyStateView() {
        emptyStateView = ContactsFeedEmptyStateView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.backgroundColor = .systemGroupedBackground
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(
            frame: view.bounds,
            collectionViewLayout: makeCompositionalLayout()
        )
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        collectionView.addGestureRecognizer(tap)

        collectionView.backgroundView = emptyStateView
        view.addSubview(collectionView)
    }

    @objc private func dismissKeyboard() {
        NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
    }

    private func makeCompositionalLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard self != nil else { return nil }

            let containerWidth = environment.container.contentSize.width
            let horizontal = Layout.sectionInset.leading + Layout.sectionInset.trailing
            let available = containerWidth - horizontal
            let cols = CGFloat(Layout.columns)
            let totalSpacing = (cols - 1) * Layout.itemSpacing
            let side = floor((available - totalSpacing) / cols)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(side),
                heightDimension: .absolute(side)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(side)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitems: Array(repeating: item, count: Layout.columns)
            )
            group.interItemSpacing = .fixed(Layout.itemSpacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = Layout.itemSpacing
            section.contentInsets = Layout.sectionInset

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(56)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    private func setupDataSource() {

        // MARK: Cell registrations

        let contactRegistration = UICollectionView.CellRegistration<ContactCollectionViewCell, UUID> {
            [weak self] cell, _, uuid in
            guard let self, let contact = self.contactByUUID[uuid] else { return }
            cell.configure(with: contact)
            cell.onChangeDate = { [weak self] in self?.onChangeDateForContact?(contact) }
            cell.onDelete = { [weak self] in
                guard let self else { return }
                contact.isArchived = true
                contact.archivedDate = Date()
                do { try self.modelContext.save() }
                catch { logger.error("Delete save failed: \(error)") }
            }
        }

        let parsedRegistration = UICollectionView.CellRegistration<ParsedContactCollectionViewCell, UUID> {
            [weak self] cell, _, uuid in
            guard let self, let contact = self.contactByUUID[uuid] else { return }
            cell.configure(with: contact)
        }

        let noteRegistration = UICollectionView.CellRegistration<NoteCollectionViewCell, UUID> {
            [weak self] cell, _, uuid in
            guard let self, let note = self.noteByUUID[uuid] else { return }
            cell.configure(note: note)
        }

        // MARK: Header registration

        let headerRegistration = UICollectionView.SupplementaryRegistration<ContactsFeedGroupHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, _, indexPath in
            guard let self, indexPath.section < self.displayedGroups.count else { return }
            let group = self.displayedGroups[indexPath.section]

            // Show the context menu only when the section has contacts to operate on.
            // Passing isLongAgo: true (regardless of actual date) hides the menu button.
            let suppressMenu = !group.hasContacts || group.isLongAgo
            headerView.configure(
                title: self.useSafeTitle ? group.dateOnlyTitle : group.title,
                subtitle: group.subtitle,
                isLongAgo: suppressMenu
            )
            headerView.onTap      = { [weak self] in self?.onTapHeader?(group) }
            headerView.onImport   = { [weak self] in self?.onImport?(group) }
            headerView.onEditDate = { [weak self] in self?.onEditDate?(group) }
            headerView.onEditTag  = { [weak self] in self?.onEditTag?(group) }
            headerView.onDeleteAll = { [weak self] in self?.onDeleteAll?(group) }
            headerView.prepareMenuButton()
        }

        // MARK: Data source

        dataSource = UICollectionViewDiffableDataSource<String, FeedItem>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard self != nil else { return nil }
            switch item {
            case .contact(let uuid, let isParsed):
                if isParsed {
                    return collectionView.dequeueConfiguredReusableCell(
                        using: parsedRegistration, for: indexPath, item: uuid)
                } else {
                    return collectionView.dequeueConfiguredReusableCell(
                        using: contactRegistration, for: indexPath, item: uuid)
                }
            case .note(let uuid):
                return collectionView.dequeueConfiguredReusableCell(
                    using: noteRegistration, for: indexPath, item: uuid)
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard self != nil, kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration, for: indexPath)
        }
    }

    private func setupKeyboardObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            scrollToBottom(animated: true)
        }
    }

    // MARK: - Snapshot

    private func applySnapshot(groups: [UnifiedFeedGroup], filter: PeopleFeedFilter) {
        _ = allGroups.isEmpty
        allGroups = groups
        groupByID.removeAll()
        for g in groups { groupByID[g.id] = g }

        var snapshot = NSDiffableDataSourceSnapshot<String, FeedItem>()
        var displayed: [UnifiedFeedGroup] = []

        for group in groups {
            let items = feedItems(for: group, filter: filter)
            guard !items.isEmpty else { continue }
            snapshot.appendSections([group.id])
            snapshot.appendItems(items, toSection: group.id)
            displayed.append(group)
        }

        // Force cells to reconfigure when underlying data changes (e.g. photo update)
        snapshot.reconfigureItems(snapshot.itemIdentifiers)

        displayedGroups = displayed
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func feedItems(for group: UnifiedFeedGroup, filter: PeopleFeedFilter) -> [FeedItem] {
        var result: [FeedItem] = []
        result += group.contacts.map { .contact($0.uuid, isParsed: false) }
        result += group.parsedContacts.map { .contact($0.uuid, isParsed: true) }
        if filter == .peopleWithNotes {
            result += group.notes.map { .note($0.uuid) }
        }
        return result
    }

    private func updateEmptyState(groups: [UnifiedFeedGroup], filter: PeopleFeedFilter) {
        let hasItems: Bool
        switch filter {
        case .people:
            hasItems = groups.contains { !$0.contacts.isEmpty || !$0.parsedContacts.isEmpty }
        case .peopleWithNotes:
            hasItems = groups.contains { !$0.contacts.isEmpty || !$0.parsedContacts.isEmpty || !$0.notes.isEmpty }
        }

        let showSyncing = useSafeTitle || (!hasItems && showInitialSyncState && !isOffline)
        let showNoStorage = !hasItems && isLowOnDeviceStorage && !showSyncing

        emptyStateView.configure(showSyncing: showSyncing, showNoStorage: showNoStorage)
        emptyStateView.isHidden = hasItems
    }

    // MARK: - Scroll

    private func scrollToTop(animated: Bool) {
        guard collectionView.numberOfSections > 0 else { return }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: animated
        )
    }

    private func scrollToBottom(animated: Bool) {
        guard collectionView.numberOfSections > 0 else { return }
        let lastSection = collectionView.numberOfSections - 1
        let itemCount = collectionView.numberOfItems(inSection: lastSection)
        guard itemCount > 0 else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: itemCount - 1, section: lastSection),
            at: .bottom,
            animated: animated
        )
    }

    // MARK: - Drop Helpers

    private func sectionGroupForDrop(at point: CGPoint) -> UnifiedFeedGroup? {
        let hitSize: CGFloat = 80
        let rect = CGRect(
            x: point.x - hitSize / 2, y: point.y - hitSize / 2,
            width: hitSize, height: hitSize
        )
        let attrs = collectionView.collectionViewLayout.layoutAttributesForElements(in: rect) ?? []
        let sectionIndex: Int? = (attrs.first { $0.representedElementCategory == .cell }
            ?? attrs.first { $0.representedElementCategory == .supplementaryView })?.indexPath.section

        if let idx = sectionIndex, idx < displayedGroups.count {
            return displayedGroups[idx]
        }
        // Fallback: scan header/cell frames
        for (idx, _) in displayedGroups.enumerated() {
            if let hAttrs = collectionView.layoutAttributesForSupplementaryElement(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: idx)
            ), hAttrs.frame.contains(point) {
                return displayedGroups[idx]
            }
        }
        return nil
    }
}

// MARK: - UICollectionViewDelegate

extension UnifiedPeopleFeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .contact(let uuid, _):
            onContactSelected?(uuid)
        case .note(let uuid):
            guard let note = noteByUUID[uuid],
                  let contactUUID = note.contact?.uuid else { return }
            onNoteSelected?(contactUUID, uuid)
        }
    }
}

// MARK: - UICollectionViewDragDelegate

extension UnifiedPeopleFeedViewController: UICollectionViewDragDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .contact(let uuid, let isParsed) = item, !isParsed else { return [] }
        let record = ContactDragRecord(uuid: uuid)
        let provider = NSItemProvider(object: record.uuid.uuidString as NSString)
        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = record
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate

extension UnifiedPeopleFeedViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil || session.canLoadObjects(ofClass: NSString.self)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        UICollectionViewDropProposal(operation: .copy, intent: .unspecified)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
        let group: UnifiedFeedGroup?
        if let dest = coordinator.destinationIndexPath, dest.section < displayedGroups.count {
            group = displayedGroups[dest.section]
        } else {
            let point = coordinator.session.location(in: collectionView)
            let content = CGPoint(
                x: point.x + collectionView.contentOffset.x,
                y: point.y + collectionView.contentOffset.y
            )
            group = sectionGroupForDrop(at: content)
        }
        guard let group else { return }

        var records: [ContactDragRecord] = []
        for item in coordinator.items {
            if let record = item.dragItem.localObject as? ContactDragRecord {
                records.append(record)
            } else if let str = item.dragItem.localObject as? String,
                      let uuid = UUID(uuidString: str) {
                records.append(ContactDragRecord(uuid: uuid))
            }
        }
        guard !records.isEmpty else { return }
        onDropRecords?(records, group)
    }
}
