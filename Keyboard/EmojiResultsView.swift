import UIKit

private final class EmojiSectionHeader: UICollectionReusableView {
    let title = UILabel()
    let clear = UIButton(type: .system)
    var onClear: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabel
        title.accessibilityTraits = .header
        clear.setTitle("Clear", for: .normal)
        clear.accessibilityLabel = "Clear frequently used emojis"
        clear.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        for child in [title, clear] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor), title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: clear.leadingAnchor),
            clear.trailingAnchor.constraint(equalTo: trailingAnchor), clear.widthAnchor.constraint(equalToConstant: 60),
            clear.topAnchor.constraint(equalTo: topAnchor), clear.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    @objc private func clearHistory() { onClear?() }
}

private final class EmojiGridLayout: UICollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if newBounds.size != collectionView?.bounds.size,
           let flowContext = context as? UICollectionViewFlowLayoutInvalidationContext {
            flowContext.invalidateFlowLayoutDelegateMetrics = true
            flowContext.invalidateFlowLayoutAttributes = true
        }
        return context
    }
}

final class EmojiResultsView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: ((String) -> Void)?
    var onClearHistory: (() -> Void)?
    var onClearSearch: (() -> Void)?
    var onToneRequest: ((String) -> Void)?
    private(set) var results: [EmojiEntry] = []
    private(set) var browsing = true
    private var sections: [[EmojiEntry]] = []
    private var titles: [String] = []
    private let layout = EmojiGridLayout()
    private let collection: UICollectionView
    private let empty = UIStackView()
    private let confirmation = UIScrollView()
    private var previousSize = CGSize.zero
    private var previousHeadersVisible = true
    private var showsSectionHeaders: Bool {
        traitCollection.verticalSizeClass != .compact && min(bounds.height, collection.bounds.height) >= 88
    }
    private let categories = UIScrollView()
    private let categoryButtons = UIStackView()
    private var contentTop: [NSLayoutConstraint] = []
    private var categoryConstraints: [NSLayoutConstraint] = []
    private var categoriesExternal = false
    private var clearCategoryButton: UIButton?
    private var browseAnchor: (text: String, section: String, offset: CGFloat)?
    private var resetPosition = true
    private var selectedCategory = 0
    private var hold: UILongPressGestureRecognizer!

    override init(frame: CGRect) {
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = self
        collection.delegate = self
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "emoji")
        collection.register(EmojiSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: "section")
        collection.accessibilityIdentifier = "emojiResults"
        hold = UILongPressGestureRecognizer(target: self, action: #selector(holdEmoji(_:)))
        hold.minimumPressDuration = 0.4
        collection.addGestureRecognizer(hold)
        categories.accessibilityIdentifier = "emojiCategories"
        categories.isHidden = true
        categories.showsHorizontalScrollIndicator = false
        categoryButtons.spacing = 2
        categoryButtons.translatesAutoresizingMaskIntoConstraints = false
        categories.addSubview(categoryButtons)
        NSLayoutConstraint.activate([
            categoryButtons.leadingAnchor.constraint(equalTo: categories.contentLayoutGuide.leadingAnchor),
            categoryButtons.trailingAnchor.constraint(equalTo: categories.contentLayoutGuide.trailingAnchor),
            categoryButtons.topAnchor.constraint(equalTo: categories.contentLayoutGuide.topAnchor),
            categoryButtons.bottomAnchor.constraint(equalTo: categories.contentLayoutGuide.bottomAnchor),
            categoryButtons.heightAnchor.constraint(equalTo: categories.frameLayoutGuide.heightAnchor)
        ])
        categories.translatesAutoresizingMaskIntoConstraints = false
        addSubview(categories)
        categories.heightAnchor.constraint(equalToConstant: 44).isActive = true
        attachCategories(to: self)
        let message = UILabel()
        message.text = "No emoji found. Try another word."
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabel
        message.adjustsFontSizeToFitWidth = true
        let clear = UIButton(type: .system)
        clear.setTitle("Clear search", for: .normal)
        clear.titleLabel?.font = .systemFont(ofSize: 13)
        clear.widthAnchor.constraint(equalToConstant: 88).isActive = true
        clear.addTarget(self, action: #selector(clearSearch), for: .touchUpInside)
        empty.addArrangedSubview(message)
        empty.addArrangedSubview(clear)
        empty.spacing = 4
        for content in [collection, empty] {
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            let top = content.topAnchor.constraint(equalTo: topAnchor)
            contentTop.append(top)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
                top, content.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        empty.isHidden = true
        confirmation.backgroundColor = .systemGroupedBackground
        let question = UILabel()
        question.text = "Clear emoji history?"
        question.textAlignment = .center
        question.font = .systemFont(ofSize: 15, weight: .semibold)
        question.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let confirm = UIButton(type: .system)
        confirm.setTitle("Clear history", for: .normal)
        confirm.accessibilityLabel = "Confirm clear emoji history"
        confirm.setTitleColor(.systemRed, for: .normal)
        confirm.addTarget(self, action: #selector(confirmClearHistory), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.accessibilityLabel = "Cancel clear emoji history"
        cancel.addTarget(self, action: #selector(cancelClearHistory), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [confirm, cancel])
        actions.distribution = .fillEqually
        actions.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let confirmationContent = UIStackView(arrangedSubviews: [question, actions])
        confirmationContent.axis = .vertical
        confirmationContent.translatesAutoresizingMaskIntoConstraints = false
        confirmation.addSubview(confirmationContent)
        NSLayoutConstraint.activate([
            confirmationContent.leadingAnchor.constraint(equalTo: confirmation.contentLayoutGuide.leadingAnchor),
            confirmationContent.trailingAnchor.constraint(equalTo: confirmation.contentLayoutGuide.trailingAnchor),
            confirmationContent.topAnchor.constraint(equalTo: confirmation.contentLayoutGuide.topAnchor),
            confirmationContent.bottomAnchor.constraint(equalTo: confirmation.contentLayoutGuide.bottomAnchor),
            confirmationContent.widthAnchor.constraint(equalTo: confirmation.frameLayoutGuide.widthAnchor)
        ])
        confirmation.translatesAutoresizingMaskIntoConstraints = false
        addSubview(confirmation)
        NSLayoutConstraint.activate([
            confirmation.leadingAnchor.constraint(equalTo: leadingAnchor),
            confirmation.trailingAnchor.constraint(equalTo: trailingAnchor),
            confirmation.topAnchor.constraint(equalTo: topAnchor),
            confirmation.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        confirmation.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != bounds.size {
            previousSize = bounds.size
            if previousHeadersVisible != showsSectionHeaders {
                previousHeadersVisible = showsSectionHeaders
                collection.reloadData()
            }
            let context = UICollectionViewFlowLayoutInvalidationContext()
            context.invalidateFlowLayoutDelegateMetrics = true
            layout.invalidateLayout(with: context)
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
        }
        clearCategoryButton?.isHidden = showsSectionHeaders
    }

    func attachCategories(to container: UIView) {
        NSLayoutConstraint.deactivate(categoryConstraints)
        container.addSubview(categories)
        categoriesExternal = container !== self
        categoryConstraints = [
            categories.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            categories.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            categories.topAnchor.constraint(equalTo: container.topAnchor)
        ]
        NSLayoutConstraint.activate(categoryConstraints)
        for top in contentTop { top.constant = browsing && !categoriesExternal ? 44 : 0 }
    }

    func showBrowse(frequent: [EmojiEntry]) {
        if browsing && !resetPosition { captureBrowseAnchor() }
        browsing = true
        titles = [frequent.isEmpty ? "Popular" : "Frequently Used"] + EmojiCategory.allCases.map(\.rawValue)
        let grouped = EmojiCatalog.grouped(EmojiCatalog.entries)
        sections = [frequent.isEmpty ? EmojiCatalog.popular : Array(frequent.prefix(16))]
            + EmojiCategory.allCases.map { category in grouped.filter { EmojiCatalog.category(for: $0) == category } }
        for button in categoryButtons.arrangedSubviews { categoryButtons.removeArrangedSubview(button); button.removeFromSuperview() }
        for (index, title) in titles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(index == 0 && !frequent.isEmpty ? "Frequent" : title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            button.accessibilityLabel = index == 0 ? title : title + " emoji"
            button.accessibilityIdentifier = "emojiCategory." + String(index)
            button.tag = index
            button.isSelected = index == selectedCategory
            button.accessibilityTraits = index == selectedCategory ? [.button, .selected] : .button
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: index == selectedCategory ? .bold : .medium)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addTarget(self, action: #selector(jumpCategory(_:)), for: .touchUpInside)
            categoryButtons.addArrangedSubview(button)
        }
        if !frequent.isEmpty {
            let clear = UIButton(type: .system)
            clear.tag = -1
            clear.setTitle("Clear", for: .normal)
            clear.titleLabel?.font = .systemFont(ofSize: 13)
            clear.accessibilityLabel = "Clear emoji history"
            clear.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            clear.addTarget(self, action: #selector(requestClearHistory), for: .touchUpInside)
            categoryButtons.insertArrangedSubview(clear, at: 1)
            clearCategoryButton = clear
        } else { clearCategoryButton = nil }
        reload()
        collection.layoutIfNeeded()
        clearCategoryButton?.isHidden = showsSectionHeaders
        if !resetPosition, let anchor = browseAnchor,
           let path = indexPath(for: anchor.text, section: anchor.section), let attributes = layout.layoutAttributesForItem(at: path) {
            let maximum = max(0, collection.contentSize.height - collection.bounds.height)
            collection.setContentOffset(CGPoint(x: 0, y: min(maximum, max(0, attributes.frame.minY - anchor.offset))), animated: false)
        }
        resetPosition = false
    }

    func resetBrowsePosition() {
        browseAnchor = nil
        resetPosition = true
        selectedCategory = 0
        collection.setContentOffset(.zero, animated: false)
        categories.setContentOffset(.zero, animated: false)
    }

    private func captureBrowseAnchor() {
        guard let path = collection.indexPathsForVisibleItems.sorted().first,
              sections.indices.contains(path.section), sections[path.section].indices.contains(path.item),
              let attributes = layout.layoutAttributesForItem(at: path) else { return }
        selectedCategory = path.section
        browseAnchor = (sections[path.section][path.item].text, titles[path.section], attributes.frame.minY - collection.contentOffset.y)
    }

    private func indexPath(for text: String, section title: String) -> IndexPath? {
        for (section, entries) in sections.enumerated() {
            if titles[section] == title, let item = entries.firstIndex(where: { $0.text == text }) { return IndexPath(item: item, section: section) }
        }
        return nil
    }

    @objc private func jumpCategory(_ sender: UIButton) {
        guard browsing, sections.indices.contains(sender.tag), !sections[sender.tag].isEmpty else { return }
        collection.layoutIfNeeded()
        let path = IndexPath(item: 0, section: sender.tag)
        let header = layout.layoutAttributesForSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, at: path)
        if let destination = header ?? layout.layoutAttributesForItem(at: path) {
            let maximum = max(0, collection.contentSize.height - collection.bounds.height)
            collection.setContentOffset(CGPoint(x: 0, y: min(maximum, destination.frame.minY)), animated: false)
        }
        captureBrowseAnchor()
        selectedCategory = sender.tag
        for case let button as UIButton in categoryButtons.arrangedSubviews where button.tag >= 0 {
            button.isSelected = button === sender
            button.accessibilityTraits = button === sender ? [.button, .selected] : .button
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: button === sender ? .bold : .medium)
        }
    }

    @objc private func holdEmoji(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let path = collection.indexPathForItem(at: gesture.location(in: collection)) else { return }
        requestTones(at: path)
    }

    func requestTones(at path: IndexPath) {
        guard isAvailable, sections.indices.contains(path.section), sections[path.section].indices.contains(path.item) else { return }
        let entry = sections[path.section][path.item]
        guard EmojiCatalog.toneVariants(for: entry.text).count > 1 else { return }
        onToneRequest?(entry.text)
    }

    func showSearch(_ query: String, frequent: [EmojiEntry]) {
        browsing = false
        titles = []
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var seen = Set<String>()
            sections = [(frequent + EmojiCatalog.popular).filter { seen.insert($0.text).inserted }]
        } else {
            let matches = EmojiCatalog.search(query)
            let explicitTone = query.lowercased().split(whereSeparator: { !$0.isLetter }).contains { ["light", "medium", "dark", "tone"].contains(String($0)) }
            sections = [explicitTone ? matches : EmojiCatalog.grouped(matches)]
        }
        reload()
    }

    private func reload() {
        resetConfirmation()
        categories.isHidden = !browsing
        for top in contentTop { top.constant = browsing && !categoriesExternal ? 44 : 0 }
        layoutIfNeeded()
        results = sections.flatMap { $0 }
        layout.scrollDirection = browsing ? .vertical : .horizontal
        layout.sectionInset.bottom = browsing ? 8 : 0
        collection.verticalScrollIndicatorInsets.bottom = browsing ? 8 : 0
        collection.alwaysBounceVertical = browsing
        collection.alwaysBounceHorizontal = !browsing
        empty.isHidden = !results.isEmpty
        collection.isHidden = results.isEmpty
        collection.accessibilityValue = browsing ? "Emoji grid" : "\(results.count) results"
        layout.invalidateLayout()
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }
    @objc private func clearSearch() { onClearSearch?() }
    func resetConfirmation() {
        confirmation.isHidden = true
        collection.isHidden = results.isEmpty
    }
    @objc private func requestClearHistory() {
        guard browsing, titles.first == "Frequently Used" else { return }
        collection.isHidden = true
        confirmation.setContentOffset(.zero, animated: false)
        confirmation.isHidden = false
        UIAccessibility.post(notification: .layoutChanged, argument: confirmation)
    }
    @objc private func confirmClearHistory() {
        guard !confirmation.isHidden else { return }
        resetConfirmation()
        onClearHistory?()
    }
    @objc private func cancelClearHistory() { resetConfirmation() }
    private var isAvailable: Bool {
        var ancestor: UIView? = self
        while let current = ancestor {
            if current.isHidden || current.alpha < 0.01 || !current.isUserInteractionEnabled { return false }
            ancestor = current.superview
        }
        return true
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath)
        let entry = sections[indexPath.section][indexPath.item]
        var content = UIListContentConfiguration.cell()
        content.text = entry.text
        content.textProperties.font = .systemFont(ofSize: 28)
        content.textProperties.alignment = .center
        content.directionalLayoutMargins = .zero
        cell.contentConfiguration = content
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = "Insert " + entry.name
        cell.accessibilityTraits = .button
        cell.accessibilityHint = nil
        cell.accessibilityCustomActions = nil
        if EmojiCatalog.toneVariants(for: entry.text).count > 1 {
            cell.accessibilityHint = "Hold for skin tones."
            cell.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Choose skin tone") { [weak self] _ in
                guard let self, self.isAvailable, self.results.contains(entry) else { return false }
                self.onToneRequest?(entry.text)
                return true
            }]
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(sections[indexPath.section][indexPath.item].text)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns = max(1, floor(collectionView.bounds.width / 44))
        return CGSize(width: browsing ? collectionView.bounds.width / columns : 44, height: 44)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        return browsing && showsSectionHeaders ? CGSize(width: collectionView.bounds.width, height: 44) : .zero
    }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "section", for: indexPath) as! EmojiSectionHeader
        let title = titles.indices.contains(indexPath.section) ? titles[indexPath.section] : ""
        header.title.text = title
        header.clear.isHidden = title != "Frequently Used"
        header.onClear = { [weak self] in self?.requestClearHistory() }
        return header
    }
}


final class EmojiTonePanel: UIView {
    var onSelect: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private let tones = UIStackView()
    private let heading = UILabel()
    private let cancel = UIButton(type: .system)
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        accessibilityIdentifier = "emojiTonePanel"
        heading.text = "Choose skin tone"
        heading.font = .preferredFont(forTextStyle: .footnote)
        heading.adjustsFontSizeToFitWidth = true
        cancel.setTitle("Cancel", for: .normal)
        cancel.accessibilityLabel = "Cancel skin tone selection"
        cancel.addTarget(self, action: #selector(cancelSelection), for: .touchUpInside)
        tones.distribution = .fillEqually
        for content in [heading, cancel, tones] {
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            heading.topAnchor.constraint(equalTo: topAnchor), heading.heightAnchor.constraint(equalToConstant: 44),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -4),
            cancel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), cancel.topAnchor.constraint(equalTo: topAnchor),
            cancel.widthAnchor.constraint(equalToConstant: 72), cancel.heightAnchor.constraint(equalToConstant: 44),
            tones.topAnchor.constraint(equalTo: topAnchor, constant: 44), tones.heightAnchor.constraint(equalToConstant: 44),
            tones.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), tones.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func show(_ variants: [EmojiEntry]) {
        generation += 1
        let current = generation
        for view in tones.arrangedSubviews { tones.removeArrangedSubview(view); view.removeFromSuperview() }
        for entry in variants {
            let button = UIButton(type: .system)
            button.setTitle(entry.text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.accessibilityLabel = "Insert " + entry.name
            button.addAction(UIAction { [weak self] _ in
                guard let self, !self.isHidden, current == self.generation else { return }
                self.onSelect?(entry.text)
            }, for: .touchUpInside)
            tones.addArrangedSubview(button)
        }
        layer.borderColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
        isHidden = false
    }

    func hide() { generation += 1; isHidden = true }
    @objc private func cancelSelection() { onCancel?() }
}
