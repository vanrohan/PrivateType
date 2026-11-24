import UIKit

final class KeyboardSettingsView: UIScrollView {
    let neuralSwitch = UISwitch()
    let correctionSwitch = UISwitch()
    let learningSwitch = UISwitch()
    let privateSwitch = UISwitch()
    let numberRowSwitch = UISwitch()
    let largerLabelsSwitch = UISwitch()
    let highContrastSwitch = UISwitch()
    private let preferredTitle = UILabel()
    private let preferredRow = UIStackView()
    private let deletion = UIStackView()
    private var cancelWidth: NSLayoutConstraint?
    private var contrastEnabled = false
    var onAppearanceChange: (() -> Void)?
    let layoutControl = UISegmentedControl(items: ["QWERTY", "QWERTZ"])
    var onKeyboardLayoutChange: ((KeyboardLanguage) -> Void)?
    let sizeControl = UISegmentedControl(items: ["Compact", "Standard", "Tall"])
    let handControl = UISegmentedControl(items: ["Full", "Left", "Right"])
    let cursorControl = UISegmentedControl(items: ["Slow", "Standard", "Fast"])
    let preferredButton = UIButton(type: .system)
    private let languageChoices = UIStackView()
    private var languageButtons: [UIButton] = []
    let deleteButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let status = UILabel()
    let touchButton = UIButton(type: .system)
    var onTouchDiagnostics: (() -> Void)?
    private(set) var deletionPending = false
    var onNeuralChange: ((Bool) -> Void)?
    var onCorrectionChange: ((Bool) -> Void)?
    var onLearningChange: ((Bool) -> Void)?
    var onDelete: (() -> Void)?
    var onLayoutChange: (() -> Void)?
    var onPrivateChange: ((Bool) -> Void)?
    var onCursorChange: ((CursorSpeed) -> Void)?
    var onPreferredLanguageChange: ((PreferredLanguage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "keyboardSettingsPanel"
        alwaysBounceVertical = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -8),
            stack.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor, constant: -12)
        ])
        stack.addArrangedSubview(choice(title: "Keyboard layout", control: layoutControl))
        layoutControl.addTarget(self, action: #selector(keyboardLayoutChanged), for: .valueChanged)
        stack.addArrangedSubview(row(title: "Neural predictions", detail: "Runs on this device", toggle: neuralSwitch))
        stack.addArrangedSubview(row(title: "Spell correction", detail: "Multilingual spelling. Delete undoes a correction.", toggle: correctionSwitch))
        stack.addArrangedSubview(row(title: "Local learning", detail: "Stores words and touch statistics. Backups can include them.", toggle: learningSwitch))
        stack.addArrangedSubview(row(title: "Private typing", detail: "Until the keyboard closes. Pauses learning and personal history.", toggle: privateSwitch))
        preferredTitle.text = "Preferred language"
        preferredTitle.font = .systemFont(ofSize: 15)
        preferredButton.accessibilityIdentifier = "preferredLanguageButton"
        preferredButton.addTarget(self, action: #selector(toggleLanguageChoices), for: .touchUpInside)
        preferredButton.setContentHuggingPriority(.required, for: .horizontal)
        preferredRow.addArrangedSubview(preferredTitle)
        preferredRow.addArrangedSubview(preferredButton)
        preferredRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.addArrangedSubview(preferredRow)
        languageChoices.axis = .vertical
        for (index, language) in PreferredLanguage.allCases.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(language.title, for: .normal)
            button.tag = index
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "preferredLanguage." + language.rawValue
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addTarget(self, action: #selector(selectPreferredLanguage(_:)), for: .touchUpInside)
            languageChoices.addArrangedSubview(button)
            languageButtons.append(button)
        }
        languageChoices.isHidden = true
        stack.addArrangedSubview(languageChoices)
        let languageHelp = UILabel()
        languageHelp.text = "All supported languages stay active. The preference breaks ties."
        languageHelp.font = .preferredFont(forTextStyle: .footnote)
        languageHelp.adjustsFontForContentSizeCategory = true
        languageHelp.textColor = .secondaryLabel
        languageHelp.numberOfLines = 0
        stack.addArrangedSubview(languageHelp)
        stack.addArrangedSubview(row(title: "Larger key labels", detail: "Key positions stay the same. System text settings also apply.", toggle: largerLabelsSwitch))
        stack.addArrangedSubview(row(title: "High contrast", detail: "Stronger key outlines. System contrast settings also apply.", toggle: highContrastSwitch))
        largerLabelsSwitch.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        highContrastSwitch.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        stack.addArrangedSubview(choice(title: "Keyboard size", control: sizeControl))
        stack.addArrangedSubview(choice(title: "One-hand layout", control: handControl))
        stack.addArrangedSubview(row(title: "Number row", detail: "Show numbers above the letters", toggle: numberRowSwitch))
        stack.addArrangedSubview(choice(title: "Cursor speed", control: cursorControl))
        cursorControl.addTarget(self, action: #selector(cursorChanged), for: .valueChanged)
        privateSwitch.addTarget(self, action: #selector(privateChanged), for: .valueChanged)
        for control in [sizeControl, handControl, numberRowSwitch] {
            control.addTarget(self, action: #selector(layoutChanged), for: .valueChanged)
        }
        neuralSwitch.addTarget(self, action: #selector(neuralChanged), for: .valueChanged)
        correctionSwitch.addTarget(self, action: #selector(correctionChanged), for: .valueChanged)
        learningSwitch.addTarget(self, action: #selector(learningChanged), for: .valueChanged)
        deletion.addArrangedSubview(deleteButton)
        deletion.addArrangedSubview(cancelButton)
        deletion.spacing = 8
        deletion.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        deleteButton.contentHorizontalAlignment = .leading
        deleteButton.tintColor = .systemRed
        deleteButton.titleLabel?.font = .systemFont(ofSize: 15)
        deleteButton.titleLabel?.numberOfLines = 2
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelWidth = cancelButton.widthAnchor.constraint(equalToConstant: 64)
        cancelWidth?.priority = .init(999)
        cancelWidth?.isActive = true
        cancelButton.addTarget(self, action: #selector(resetConfirmation), for: .touchUpInside)
        stack.addArrangedSubview(deletion)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
        stack.addArrangedSubview(status)
        touchButton.setTitle("Touch zones and statistics", for: .normal)
        touchButton.contentHorizontalAlignment = .leading
        touchButton.titleLabel?.font = .systemFont(ofSize: 15)
        touchButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        touchButton.addTarget(self, action: #selector(showTouchDiagnostics), for: .touchUpInside)
        stack.addArrangedSubview(touchButton)
        for button in [preferredButton, deleteButton, cancelButton] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        preferredButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        for toggle in [neuralSwitch, correctionSwitch, learningSwitch, privateSwitch, numberRowSwitch,
                       largerLabelsSwitch, highContrastSwitch] {
            toggle.addTarget(self, action: #selector(refreshSwitchContrast), for: .valueChanged)
        }
        updateTextStyles()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (panel: KeyboardSettingsView, _: UITraitCollection) in
            panel.updateTextStyles()
        }
        resetConfirmation()
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    private func choice(title: String, control: UISegmentedControl) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        control.accessibilityIdentifier = title
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return stack
    }

    private func row(title: String, detail: String, toggle: UISwitch) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 1
        let row = UIStackView(arrangedSubviews: [labels, toggle])
        row.alignment = .center
        row.spacing = 8
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = detail
        row.accessibilityElements = [toggle]
        return row
    }

    func configure(neural: Bool, correction: Bool, learning: Bool, engine: String,
                   layout: KeyboardLanguage, size: KeyboardSize, hand: KeyboardHand, numberRow: Bool,
                   privateTyping: Bool, cursorSpeed: CursorSpeed, preferredLanguage: PreferredLanguage,
                   largerKeyLabels: Bool, highContrast: Bool) {
        largerLabelsSwitch.isOn = largerKeyLabels
        highContrastSwitch.isOn = highContrast
        neuralSwitch.isOn = neural
        correctionSwitch.isOn = correction
        learningSwitch.isOn = learning
        learningSwitch.isEnabled = !privateTyping
        privateSwitch.isOn = privateTyping
        cursorControl.selectedSegmentIndex = CursorSpeed.allCases.firstIndex(of: cursorSpeed) ?? 1
        preferredButton.setTitle(preferredLanguage.title, for: .normal)
        preferredButton.accessibilityLabel = "Preferred language: " + preferredLanguage.title
        for (index, button) in languageButtons.enumerated() {
            button.accessibilityTraits = PreferredLanguage.allCases[index] == preferredLanguage ? [.button, .selected] : .button
        }
        layoutControl.selectedSegmentIndex = KeyboardLanguage.allCases.firstIndex(of: layout) ?? 0
        sizeControl.selectedSegmentIndex = KeyboardSize.allCases.firstIndex(of: size) ?? 1
        handControl.selectedSegmentIndex = KeyboardHand.allCases.firstIndex(of: hand) ?? 0
        numberRowSwitch.isOn = numberRow
        status.text = "Prediction engine: " + engine
        applyContrast(contrastEnabled)
    }

    private func updateTextStyles() {
        let accessibilityText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        preferredTitle.numberOfLines = 0
        preferredTitle.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        preferredTitle.adjustsFontForContentSizeCategory = true
        preferredRow.axis = accessibilityText ? .vertical : .horizontal
        preferredButton.contentHorizontalAlignment = accessibilityText ? .leading : .trailing
        for button in [preferredButton, deleteButton, cancelButton, touchButton] + languageButtons {
            button.titleLabel?.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.lineBreakMode = .byWordWrapping
        }
        deletion.axis = accessibilityText ? .vertical : .horizontal
        cancelWidth?.isActive = !accessibilityText
        status.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
        status.adjustsFontForContentSizeCategory = true
        for control in [layoutControl, sizeControl, handControl, cursorControl] {
            let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 14),
                maximumPointSize: 18, compatibleWith: traitCollection)
            control.setTitleTextAttributes([.font: font], for: .normal)
        }
    }

    func applyContrast(_ enabled: Bool) {
        contrastEnabled = enabled
        for control in [layoutControl, sizeControl, handControl, cursorControl] {
            control.selectedSegmentTintColor = enabled ? .label : nil
            control.setTitleTextAttributes(enabled ? [.foregroundColor: UIColor.systemBackground] : nil, for: .selected)
        }
        for toggle in [neuralSwitch, correctionSwitch, learningSwitch, privateSwitch, numberRowSwitch,
                       largerLabelsSwitch, highContrastSwitch] {
            toggle.onTintColor = enabled ? .label : nil
            toggle.thumbTintColor = enabled && toggle.isOn ? .systemBackground : nil
        }
        deleteButton.tintColor = enabled ? .label : .systemRed
    }

    @objc private func refreshSwitchContrast() { applyContrast(contrastEnabled) }
    @objc private func appearanceChanged() { onAppearanceChange?() }
    @objc private func showTouchDiagnostics() { onTouchDiagnostics?() }
    @objc private func neuralChanged() { onNeuralChange?(neuralSwitch.isOn) }
    @objc private func correctionChanged() { onCorrectionChange?(correctionSwitch.isOn) }
    @objc private func learningChanged() { onLearningChange?(learningSwitch.isOn) }
    @objc private func keyboardLayoutChanged() {
        guard KeyboardLanguage.allCases.indices.contains(layoutControl.selectedSegmentIndex) else { return }
        onKeyboardLayoutChange?(KeyboardLanguage.allCases[layoutControl.selectedSegmentIndex])
    }
    @objc private func layoutChanged() { onLayoutChange?() }
    @objc private func privateChanged() { onPrivateChange?(privateSwitch.isOn) }
    @objc private func cursorChanged() {
        guard CursorSpeed.allCases.indices.contains(cursorControl.selectedSegmentIndex) else { return }
        onCursorChange?(CursorSpeed.allCases[cursorControl.selectedSegmentIndex])
    }
    @objc private func toggleLanguageChoices() { languageChoices.isHidden.toggle() }
    @objc private func selectPreferredLanguage(_ sender: UIButton) {
        guard PreferredLanguage.allCases.indices.contains(sender.tag) else { return }
        onPreferredLanguageChange?(PreferredLanguage.allCases[sender.tag])
        languageChoices.isHidden = true
    }
    @objc private func deleteTapped() {
        if deletionPending { onDelete?(); resetConfirmation() }
        else {
            deletionPending = true
            deleteButton.setTitle("Confirm deletion", for: .normal)
            cancelButton.isHidden = false
        }
    }
    @objc func resetConfirmation() {
        languageChoices.isHidden = true
        deletionPending = false
        deleteButton.setTitle("Delete learned data", for: .normal)
        cancelButton.isHidden = true
    }
}
