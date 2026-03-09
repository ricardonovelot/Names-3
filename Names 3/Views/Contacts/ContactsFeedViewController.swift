//
//  ContactsFeedViewController.swift
//  Names 3
//
//  UIKit-based contacts feed using UICollectionView with compositional layout,
//  diffable data source, and modern cell/supplementary registration (iOS 14+).
//  Follows Apple's recommended patterns for collection views.
//

import UIKit
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "ContactsFeed")

// MARK: - ContactsFeedViewController

@MainActor
final class ContactsFeedViewController: UIViewController {

    // MARK: - Section & Item Types (Diffable Data Source)

    private enum Section: Hashable {
        case group(String)
    }

    private struct ContactItem: Hashable {
        let uuid: UUID
        let isParsed: Bool

        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
            hasher.combine(isParsed)
        }

        static func == (lhs: ContactItem, rhs: ContactItem) -> Bool {
            lhs.uuid == rhs.uuid && lhs.isParsed == rhs.isParsed
        }
    }

    // MARK: - Callbacks

    var onContactSelected: ((UUID) -> Void)?
    var onImport: ((ContactsGroup) -> Void)?
    var onEditDate: ((ContactsGroup) -> Void)?
    var onEditTag: ((ContactsGroup) -> Void)?
    var onRenameTag: ((ContactsGroup) -> Void)?
    var onDeleteAll: ((ContactsGroup) -> Void)?
    var onChangeDateForContact: ((Contact) -> Void)?
    var onTapHeader: ((ContactsGroup) -> Void)?
    var onDropRecords: (([ContactDragRecord], ContactsGroup) -> Void)?

    // MARK: - Subviews

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, ContactItem>!
    private var emptyStateView: ContactsFeedEmptyStateView!

    // MARK: - Data

    private var groups: [ContactsGroup] = []
    private var groupBySectionID: [String: ContactsGroup] = [:]

    // MARK: - Configuration

    private let modelContext: ModelContext
    private let useSafeTitle: Bool
    private var showInitialSyncState: Bool
    private var isLowOnDeviceStorage: Bool
    private var isOffline: Bool

    private enum Layout {
        static let itemSpacing: CGFloat = 10
        static let sectionInset = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16)
        static let columns: Int = 4
    }

    // MARK: - Init

    init(
        modelContext: ModelContext,
        useSafeTitle: Bool,
        showInitialSyncState: Bool,
        isLowOnDeviceStorage: Bool,
        isOffline: Bool
    ) {
        self.modelContext = modelContext
        self.useSafeTitle = useSafeTitle
        self.showInitialSyncState = showInitialSyncState
        self.isLowOnDeviceStorage = isLowOnDeviceStorage
        self.isOffline = isOffline
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func setBottomBarHeight(_ height: CGFloat) {
        let inset = max(height, tabBarMinimumHeight) + Layout.sectionInset.bottom
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
    }

    func update(
        contacts: [Contact],
        parsedContacts: [Contact],
        useSafeTitle: Bool,
        showInitialSyncState: Bool,
        isLowOnDeviceStorage: Bool,
        isOffline: Bool
    ) {
        self.showInitialSyncState = showInitialSyncState
        self.isLowOnDeviceStorage = isLowOnDeviceStorage
        self.isOffline = isOffline

        let newGroups = ContactsFeedView.computeGroups(contacts: contacts, parsedContacts: parsedContacts)
        applySnapshot(groups: newGroups)
        updateEmptyState(groups: newGroups)
    }

    // MARK: - Setup

    private func setupEmptyStateView() {
        emptyStateView = ContactsFeedEmptyStateView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.backgroundColor = .systemGroupedBackground
    }

    private func setupCollectionView() {
        let layout = createCompositionalLayout()

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
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

        // Tap on content to dismiss keyboard (does not block cell selection)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardFromTap))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        collectionView.addGestureRecognizer(tap)

        // Use backgroundView for empty state (Apple pattern: no overlapping views or isHidden toggling)
        collectionView.backgroundView = emptyStateView

        view.addSubview(collectionView)
    }

    @objc private func dismissKeyboardFromTap() {
        NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
    }

    private func createCompositionalLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard self != nil else { return nil }

            let containerWidth = environment.container.contentSize.width
            let horizontalInset = Layout.sectionInset.leading + Layout.sectionInset.trailing
            let availableWidth = containerWidth - horizontalInset
            let columns = CGFloat(Layout.columns)
            let totalSpacing = (columns - 1) * Layout.itemSpacing
            let cellSide = floor((availableWidth - totalSpacing) / columns)

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(cellSide),
                heightDimension: .absolute(cellSide)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(cellSide)
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
        return layout
    }

    private func setupDataSource() {
        let contactCellRegistration = UICollectionView.CellRegistration<ContactCollectionViewCell, ContactItem> { [weak self] cell, indexPath, item in
            guard let self else { return }
            guard let group = self.group(for: indexPath),
                  let contact = self.contact(for: item, in: group) else { return }

            cell.configure(with: contact)
            cell.onChangeDate = { [weak self] in
                self?.onChangeDateForContact?(contact)
            }
            cell.onDelete = { [weak self] in
                guard let self else { return }
                contact.isArchived = true
                contact.archivedDate = Date()
                do {
                    try self.modelContext.save()
                } catch {
                    logger.error("Save failed: \(error)")
                }
            }
        }

        let parsedCellRegistration = UICollectionView.CellRegistration<ParsedContactCollectionViewCell, ContactItem> { [weak self] cell, indexPath, item in
            guard let self else { return }
            guard let group = self.group(for: indexPath),
                  let contact = self.contact(for: item, in: group) else { return }
            cell.configure(with: contact)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<ContactsFeedGroupHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] headerView, elementKind, indexPath in
            guard let self,
                  indexPath.section < self.groups.count else { return }

            let group = self.groups[indexPath.section]
            headerView.configure(
                title: self.useSafeTitle ? group.dateOnlyTitle : group.title,
                subtitle: group.subtitle,
                isLongAgo: group.isLongAgo
            )
            headerView.onTap = { [weak self] in
                self?.onTapHeader?(group)
            }
            headerView.onImport = { [weak self] in
                self?.onImport?(group)
            }
            headerView.onEditDate = { [weak self] in
                self?.onEditDate?(group)
            }
            headerView.onEditTag = { [weak self] in
                self?.onEditTag?(group)
            }
            headerView.onDeleteAll = { [weak self] in
                self?.onDeleteAll?(group)
            }
            headerView.prepareMenuButton()
        }

        dataSource = UICollectionViewDiffableDataSource<Section, ContactItem>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard self != nil else { return nil }
            if item.isParsed {
                return collectionView.dequeueConfiguredReusableCell(
                    using: parsedCellRegistration,
                    for: indexPath,
                    item: item
                )
            } else {
                return collectionView.dequeueConfiguredReusableCell(
                    using: contactCellRegistration,
                    for: indexPath,
                    item: item
                )
            }
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard self != nil, kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration,
                for: indexPath
            )
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

    @objc private func keyboardWillShow(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            scrollToBottom(animated: true)
        }
    }

    // MARK: - Snapshot & Empty State

    private func applySnapshot(groups: [ContactsGroup]) {
        let wasEmpty = self.groups.isEmpty
        self.groups = groups
        groupBySectionID.removeAll()
        for group in groups {
            groupBySectionID[group.id] = group
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, ContactItem>()
        snapshot.appendSections(groups.map { Section.group($0.id) })

        for group in groups {
            let section = Section.group(group.id)
            let persistedItems = group.contacts.map { ContactItem(uuid: $0.uuid, isParsed: false) }
            let parsedItems = group.parsedContacts.map { ContactItem(uuid: $0.uuid, isParsed: true) }
            snapshot.appendItems(persistedItems + parsedItems, toSection: section)
        }

        // Force reconfigure so cells refresh when contact data changes (e.g. photo update)
        snapshot.reconfigureItems(snapshot.itemIdentifiers)

        dataSource.apply(snapshot, animatingDifferences: true)

        // Apple Photos style: start at bottom when content first loads (empty → non-empty)
        if wasEmpty && !groups.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.scrollToBottomIfNeeded(animated: false)
            }
        }
    }

    private func updateEmptyState(groups: [ContactsGroup]) {
        let showSyncing = useSafeTitle || (groups.isEmpty && showInitialSyncState && !isOffline)
        let showNoStorage = groups.isEmpty && isLowOnDeviceStorage && !showSyncing

        emptyStateView.configure(
            showSyncing: showSyncing,
            showNoStorage: showNoStorage
        )
        // Hide empty state when feed has content so it doesn't show behind cells
        emptyStateView.isHidden = !groups.isEmpty
    }

    // MARK: - Helpers

    private func group(for indexPath: IndexPath) -> ContactsGroup? {
        guard indexPath.section < groups.count else { return nil }
        return groups[indexPath.section]
    }

    private func contact(for item: ContactItem, in group: ContactsGroup) -> Contact? {
        if item.isParsed {
            return group.parsedContacts.first { $0.uuid == item.uuid }
        } else {
            return group.contacts.first { $0.uuid == item.uuid }
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard collectionView.numberOfSections > 0 else { return }
        let lastSection = collectionView.numberOfSections - 1
        let itemCount = collectionView.numberOfItems(inSection: lastSection)
        guard itemCount > 0 else { return }
        let lastIndexPath = IndexPath(item: itemCount - 1, section: lastSection)
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: animated)
    }

    /// Scrolls to bottom (most recent content) so user sees newest first, like Apple Photos.
    /// Call after layout is ready; no-op if content is empty.
    private func scrollToBottomIfNeeded(animated: Bool) {
        guard !groups.isEmpty else { return }
        collectionView.layoutIfNeeded()
        scrollToBottom(animated: animated)
    }
}

// MARK: - UICollectionViewDelegate

extension ContactsFeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        onContactSelected?(item.uuid)
    }
}

// MARK: - UICollectionViewDragDelegate

extension ContactsFeedViewController: UICollectionViewDragDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let record = ContactDragRecord(uuid: item.uuid)
        let provider = NSItemProvider(object: record.uuid.uuidString as NSString)
        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = record
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate

extension ContactsFeedViewController: UICollectionViewDropDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        canHandle session: UIDropSession
    ) -> Bool {
        // Accept local drag (same app) or drops with NSString (Transferable)
        if session.localDragSession != nil { return true }
        return session.canLoadObjects(ofClass: NSString.self)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        // Use .unspecified intent so we handle the drop ourselves (model update, not collection view insert)
        UICollectionViewDropProposal(operation: .copy, intent: .unspecified)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
        let resolvedSection: Int?
        if let destinationIndexPath = coordinator.destinationIndexPath {
            resolvedSection = destinationIndexPath.section
        } else {
            let viewPoint = coordinator.session.location(in: collectionView)
            let contentPoint = CGPoint(
                x: viewPoint.x + collectionView.contentOffset.x,
                y: viewPoint.y + collectionView.contentOffset.y
            )
            resolvedSection = sectionIndexForDrop(at: contentPoint)
        }

        guard let section = resolvedSection, section < groups.count else { return }

        let group = groups[section]

        var records: [ContactDragRecord] = []
        for item in coordinator.items {
            if let record = item.dragItem.localObject as? ContactDragRecord {
                records.append(record)
            } else if let uuidString = item.dragItem.localObject as? String,
                      let uuid = UUID(uuidString: uuidString) {
                records.append(ContactDragRecord(uuid: uuid))
            }
        }

        guard !records.isEmpty else { return }
        onDropRecords?(records, group)
    }

    /// Resolves section index from a point (e.g. when dropping on header or empty area).
    private func sectionIndexForDrop(at point: CGPoint) -> Int? {
        let hitSize: CGFloat = 80
        let rect = CGRect(
            x: point.x - hitSize / 2,
            y: point.y - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
        let attrs = collectionView.collectionViewLayout.layoutAttributesForElements(in: rect) ?? []
        let cellAttr = attrs.first { $0.representedElementCategory == .cell }
        let headerAttr = attrs.first { $0.representedElementCategory == .supplementaryView }
        if let sectionAttr = cellAttr ?? headerAttr {
            return sectionAttr.indexPath.section
        }
        // Fallback: find section whose frame contains the point
        for section in 0..<collectionView.numberOfSections {
            if let headerAttrs = collectionView.layoutAttributesForSupplementaryElement(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: section)
            ), headerAttrs.frame.contains(point) {
                return section
            }
            if collectionView.numberOfItems(inSection: section) > 0,
               let firstAttrs = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: section)),
               firstAttrs.frame.contains(point) {
                return section
            }
        }
        return nil
    }
}
