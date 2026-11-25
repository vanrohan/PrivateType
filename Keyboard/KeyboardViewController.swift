import UIKit
import os

private final class SuggestionRow: UIStackView {
    var didLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }
}

struct KeyboardInputPolicy {
    let keyboardType: UIKeyboardType?
    let autocorrectionType: UITextAutocorrectionType?

    var allowsPredictions: Bool {
        switch keyboardType {
        case .emailAddress, .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad: return false
        default: return true
        }
    }

    var allowsManualCorrections: Bool { allowsPredictions && keyboardType != .URL }
    var allowsCorrectionAndLearning: Bool { allowsManualCorrections && autocorrectionType != .no }
}

final class KeyboardViewController: UIInputViewController {
    private var startupInterval: OSSignpostIntervalState? = KeyboardPerformance.signposter.beginInterval(
        "Keyboard startup", id: KeyboardPerformance.signposter.makeSignpostID())
    var demoMode = false
    var onDemoTextChange: ((String) -> Void)?
    var onDemoCorrectionChange: ((Bool) -> Void)?
    var demoText = ""
    var storage = KeyboardStorage()
    var now: () -> Date = Date.init
    var voiceOverActive: () -> Bool = { UIAccessibility.isVoiceOverRunning }
    var postAccessibility: (UIAccessibility.Notification, Any?) -> Void = {
        UIAccessibility.post(notification: $0, argument: $1)
    }
    private var accessibilityVisible = true
    private var lastAccessibilityFeedback: String?
    private weak var wordOrigin: UIButton?
    var documentProxy: UITextDocumentProxy?
    private var proxy: UITextDocumentProxy { documentProxy ?? textDocumentProxy }
    let spelling = MultilingualSpelling()
    private var predictor = PredictionEngine()
    let plane = KeyboardPlane()
    let alternatePopup = AlternatePopupView()
    let emojiTonePanel = EmojiTonePanel()
    private var toneOrigin: String?
    private var lastHostFieldType: UIKeyboardType?
    private var lastHostDocument: UUID?
    private struct HostSurface: Equatable {
        let type: UIKeyboardType?
        let correction: UITextAutocorrectionType?
        let capitalization: UITextAutocapitalizationType?
        let document: UUID?
    }
    private var emojiHostSurface: HostSurface?
    private var restoringEmojiHost = false
    private let predictionStrip = UIStackView()
    private let suggestions = SuggestionRow()
    private let correctionStrip = UIStackView()
    private let deletionStrip = UIStackView()
    let deletionLabel = UILabel()
    let restoreButton = UIButton(type: .system)
    let privateIndicator = UIButton(type: .system)
    private var privateIndicatorLeading: NSLayoutConstraint?
    private var privateIndicatorTrailing: NSLayoutConstraint?
    private weak var keyboardHeader: UIView?
    private var otherStripLeading: [NSLayoutConstraint] = []
    let correctionLabel = UILabel()
    let undoButton = UIButton(type: .system)
    private let keyboardBody = UIView()
    private var planeLeading: NSLayoutConstraint?
    private var planeTrailing: NSLayoutConstraint?
    private var predictionLeading: NSLayoutConstraint?
    private var predictionTrailing: NSLayoutConstraint?
    private var emojiLeading: NSLayoutConstraint?
    private var emojiTrailing: NSLayoutConstraint?
    private var settingsLeading: NSLayoutConstraint?
    private var settingsTrailing: NSLayoutConstraint?
    private var settingsButtonLeading: NSLayoutConstraint?
    private var emojiButtonTrailing: NSLayoutConstraint?
    private let searchQueryRow = TouchBlockingStackView()
    private let searchResults = EmojiResultsView()
    private let browseResults = EmojiResultsView()
    private let expandButton = UIButton(type: .system)
    var onLayoutOptionsChange: ((KeyboardSize, Bool) -> Void)?
    private let wordHeader = UIStackView()
    private let wordBackButton = UIButton(type: .system)
    private let browseSearchButton = UIButton(type: .system)
    private let wordPanel = UIStackView()
    private let wordTitle = UILabel()
    let forgetWordButton = UIButton(type: .system)
    let protectWordButton = UIButton(type: .system)
    private var selectedWord: String?
    private(set) var isShowingWordOptions = false
    private let settingsHeader = UIStackView()
    private let emojiHeader = UIStackView()
    var emojiResults: EmojiResultsView { isSearchingEmoji ? searchResults : browseResults }
    let emojiSearch = EmojiSearchControl()
    var onEmojiSearchVisibilityChange: ((Bool) -> Void)?
    private(set) var isShowingEmoji = false
    private let emojiBody = UIStackView()
    private let emojiFooter = UIStackView()
    private let emojiBrowseButton = UIButton(type: .system)
    let emojiDelete = UIButton(type: .system)
    private let emojiGlobe = UIButton(type: .system)
    private var normalPlaneConstraints: [NSLayoutConstraint] = []
    private var savedTypingState: (page: Int, shifted: Bool, caps: Bool, manual: Bool)?
    private(set) var isSearchingEmoji = false
    private(set) var emojiQuery = ""
    private let settingsButton = DeliberateTapButton(type: .system)
    private let emojiButton = DeliberateTapButton(type: .system)
    let settingsPanel = KeyboardSettingsView()
    private var heightConstraint: NSLayoutConstraint?
    private(set) var isShowingSettings = false
    private(set) var suggestionButtons: [UIButton] = []
    private var rankedSuggestions: [String] = []
    private var suggestionGeometry: CGSize = .zero
    private var suggestionFrame: CGRect = .zero
    private struct SuggestionPress {
        let button: UIButton
        let word: String
        let host: HostState
    }
    private var suggestionPress: SuggestionPress?
    private var suggestionPressInvalidated = false
    private var cancelledSuggestionButtons = Set<ObjectIdentifier>()
    private var renderedSuggestionHost: HostState?
    private var deferredSuggestions: [String]?
    private struct WordDeletion {
        let host: HostState
        let suffixes: [String]
    }
    private var wordDeletion: WordDeletion?
    private var deletionWordCount = 0
    private var deletionPreviewVisible = false
    private var restoredText: String?
    private var restoreHost: HostState?
    private var deletePressHost: HostState?
    private struct LearningBoundary {
        let document: UUID?
        let prefix: String
        let partialToken: Bool
    }
    private var learningBoundary: LearningBoundary?
    private var lexiconWords: Set<String> = []
    private var lexiconReplacements: [String: String] = [:]
    private var properForms: [String: String] = [:]
    private static let lowercaseEnglishWords: Set<String> = {
        guard let url = Bundle.main.url(forResource: "EnglishVocabulary", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return PredictionEngine.commonEnglishWords }
        return Set(text.split(separator: "\n").map(String.init).filter { $0 == $0.lowercased() && TextRules.isWord($0) })
    }()
    private var undo: CorrectionUndo?
    private var undoHostState: HostState?
    private var hits: [KeyHit] = []
    private struct TouchCorrection {
        let original: String
        let hits: [KeyHit]
        let before: String
        let document: UUID?
        let profile: TouchProfile?
    }
    private var touchCorrection: TouchCorrection?
    private var lastTouchWord: TouchCorrection?
    private(set) var activeTouchProfile: TouchProfile?
    private var touchGeometry = CGSize.zero
    let touchDiagnostics = TouchDiagnosticsView()
    private let settingsTitle = UILabel()
    private let settingsBackButton = UIButton(type: .system)
    private var diagnosticPage: Int?
    private(set) var isShowingTouchDiagnostics = false
    private var lastShift = Date.distantPast
    private var lastSpace = Date.distantPast
    private var saveTask: DispatchWorkItem?
    private var expectedContext: String?
    private struct HostState: Equatable {
        let document: UUID?
        let before: String?
        let after: String?
        let selection: String?
    }
    private var expectedHostState: HostState?
    private var suggestionSpaceHost: HostState?
    private var changingEmojiInput = false
    private var emojiSearchDocument: UUID?
    private let demoDocumentIdentifier = UUID()
    private var hostState: HostState {
        // Some input sessions return nil for this nonoptional Swift property.
        let document = demoMode ? demoDocumentIdentifier : (proxy as? NSObject)?.value(forKey: "documentIdentifier") as? UUID
        return HostState(document: document,
                  before: demoMode ? demoText : proxy.documentContextBeforeInput,
                  after: demoMode ? "" : proxy.documentContextAfterInput,
                  selection: demoMode ? nil : proxy.selectedText)
    }
    private var shiftWasManual = false
    private var rejectedWord: String?
    var neuralService = NeuralPredictionService()
    private var neuralWords: [String] = []
    private var neuralContext: String?
    private(set) var neuralEngine = "Loading predictions"
    private(set) var neuralSuspended = false

    var context: String { demoMode ? demoText : proxy.documentContextBeforeInput ?? "" }
    private var language: KeyboardLanguage { storage.language }
    private var observedHostSurface: HostSurface {
        HostSurface(type: demoMode ? .default : proxy.keyboardType,
                    correction: demoMode ? .default : proxy.autocorrectionType,
                    capitalization: demoMode ? .sentences : proxy.autocapitalizationType,
                    document: hostState.document)
    }
    private var effectiveHostSurface: HostSurface {
        let observed = observedHostSurface
        guard let saved = emojiHostSurface, isSearchingEmoji || restoringEmojiHost else { return observed }
        if isSearchingEmoji || isReturningSearchDocument { return saved }
        if let document = observed.document, document != saved.document { return observed }
        if observed == saved { return observed }
        if observed.type == nil || observed.type == .default { return saved }
        return observed
    }
    private var isReturningSearchDocument: Bool {
        guard restoringEmojiHost, !isSearchingEmoji, let searchDocument = emojiSearchDocument else { return false }
        return hostState.document == searchDocument
    }
    private var inputPolicy: KeyboardInputPolicy {
        let surface = effectiveHostSurface
        return KeyboardInputPolicy(keyboardType: surface.type, autocorrectionType: surface.correction)
    }
    private var allowsWords: Bool { inputPolicy.allowsCorrectionAndLearning }
    private var allowsPredictions: Bool { inputPolicy.allowsPredictions }
    var isPrivateTyping: Bool { storage.privateTyping }
    private var settingsMenuTitle: String { demoMode ? "Preview settings" : "Settings" }
    private var settingsButtonLabel: String { demoMode ? "Preview settings" : "Keyboard settings" }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForTraitChanges([UITraitAccessibilityContrast.self, UITraitPreferredContentSizeCategory.self,
                                UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _: UITraitCollection) in
            controller.applyAccessibilityOptions()
        }
        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "simpleKeysKeyboard"
        let root = UIStackView()
        root.axis = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardLayout.height(compact: false))
        height.priority = .init(999)
        height.isActive = true
        heightConstraint = height
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 2),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -2),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let header = UIView()
        keyboardHeader = header
        header.heightAnchor.constraint(equalToConstant: KeyboardLayout.suggestionHeight).isActive = true
        searchQueryRow.spacing = 4
        searchQueryRow.isLayoutMarginsRelativeArrangement = true
        searchQueryRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        let queryHeight = searchQueryRow.heightAnchor.constraint(equalToConstant: 44)
        queryHeight.priority = .init(999)
        queryHeight.isActive = true
        searchQueryRow.addArrangedSubview(emojiSearch)
        searchQueryRow.addArrangedSubview(emojiBrowseButton)
        searchQueryRow.isHidden = true
        root.addArrangedSubview(searchQueryRow)
        for strip in [predictionStrip, settingsHeader, emojiHeader, wordHeader] {
            strip.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(strip)
            let leading = strip.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: strip == wordHeader ? 6 : 54)
            let trailing = strip.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: strip == wordHeader ? -6 : -54)
            if strip == predictionStrip {
                predictionLeading = leading
                predictionTrailing = trailing
            } else if strip == emojiHeader {
                emojiLeading = leading
                emojiTrailing = trailing
            } else if strip == settingsHeader {
                settingsLeading = leading
                settingsTrailing = trailing
            } else { otherStripLeading.append(leading) }
            NSLayoutConstraint.activate([
                leading, trailing,
                strip.topAnchor.constraint(equalTo: header.topAnchor),
                strip.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
            ])
        }
        for button in [emojiButton, settingsButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: header.topAnchor),
                button.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
        settingsButtonLeading = settingsButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 6)
        emojiButtonTrailing = emojiButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6)
        settingsButtonLeading?.isActive = true
        emojiButtonTrailing?.isActive = true
        searchResults.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchResults)
        NSLayoutConstraint.activate([
            searchResults.leadingAnchor.constraint(equalTo: emojiHeader.leadingAnchor),
            searchResults.trailingAnchor.constraint(equalTo: emojiHeader.trailingAnchor),
            searchResults.topAnchor.constraint(equalTo: header.topAnchor),
            searchResults.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])
        searchResults.isHidden = true
        privateIndicator.translatesAutoresizingMaskIntoConstraints = false
        var privateStyle = UIButton.Configuration.plain()
        privateStyle.title = "Private\non"
        privateStyle.titleAlignment = .center
        privateStyle.titleLineBreakMode = .byWordWrapping
        privateStyle.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 12, weight: .semibold)
            return attributes
        }
        privateStyle.contentInsets = .zero
        privateStyle.cornerStyle = .capsule
        privateStyle.baseForegroundColor = .label
        privateStyle.background.backgroundColor = .secondarySystemFill
        privateStyle.background.strokeColor = .secondaryLabel
        privateStyle.background.strokeWidth = 1
        privateStyle.background.backgroundInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)
        privateIndicator.configuration = privateStyle
        privateIndicator.accessibilityLabel = "End private typing"
        privateIndicator.accessibilityValue = "On"
        privateIndicator.accessibilityIdentifier = "privateTypingIndicator"
        privateIndicator.addTarget(self, action: #selector(endPrivateTyping), for: .touchUpInside)
        header.addSubview(privateIndicator)
        privateIndicatorLeading = privateIndicator.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 6)
        privateIndicatorTrailing = privateIndicator.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10)
        NSLayoutConstraint.activate([
            privateIndicatorLeading!,
            privateIndicator.widthAnchor.constraint(equalToConstant: 52),
            privateIndicator.topAnchor.constraint(equalTo: header.topAnchor),
            privateIndicator.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8)
        ])
        privateIndicator.isHidden = true
        suggestions.distribution = .fillEqually
        for _ in 0..<4 {
            let button = UIButton(type: .system)
            button.titleLabel?.font = .systemFont(ofSize: 16)
            button.setTitleColor(.label, for: .normal)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.addTarget(self, action: #selector(acceptSuggestion(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(beginSuggestionPress(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(cancelSuggestionPress(_:)), for: [.touchCancel, .touchUpOutside])
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdSuggestion(_:)))
            hold.cancelsTouchesInView = false
            button.addGestureRecognizer(hold)
            button.accessibilityHint = "Use Actions for word options."
            button.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Word options") { [weak self, weak button] _ in
                guard let self, let button, self.suggestionIsAvailable(button),
                      let word = self.suggestionWord(for: button) else { return false }
                return self.showWordOptions(word, origin: button)
            }]
            suggestionButtons.append(button)
            suggestions.addArrangedSubview(button)
        }
        predictionStrip.addArrangedSubview(suggestions)
        suggestions.didLayout = { [weak self] in self?.layoutSuggestions() }
        correctionLabel.font = .systemFont(ofSize: 13)
        correctionLabel.adjustsFontSizeToFitWidth = true
        correctionLabel.minimumScaleFactor = 0.7
        correctionLabel.lineBreakMode = .byTruncatingMiddle
        correctionLabel.accessibilityIdentifier = "correctionFeedback"
        undoButton.setTitle("Undo", for: .normal)
        undoButton.accessibilityLabel = "Undo correction"
        undoButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        undoButton.addTarget(self, action: #selector(undoCorrection), for: .touchUpInside)
        correctionStrip.addArrangedSubview(correctionLabel)
        correctionStrip.addArrangedSubview(undoButton)
        correctionStrip.spacing = 4
        correctionStrip.isHidden = true
        predictionStrip.addArrangedSubview(correctionStrip)
        deletionLabel.font = .systemFont(ofSize: 13)
        deletionLabel.numberOfLines = 2
        deletionLabel.lineBreakMode = .byTruncatingMiddle
        deletionLabel.accessibilityIdentifier = "wordDeletionPreview"
        restoreButton.setTitle("Restore", for: .normal)
        restoreButton.accessibilityLabel = "Restore deleted text"
        restoreButton.widthAnchor.constraint(equalToConstant: 64).isActive = true
        restoreButton.addTarget(self, action: #selector(restoreDeletedText), for: .touchUpInside)
        deletionStrip.addArrangedSubview(deletionLabel)
        deletionStrip.addArrangedSubview(restoreButton)
        deletionStrip.spacing = 4
        deletionStrip.isHidden = true
        predictionStrip.addArrangedSubview(deletionStrip)
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.accessibilityLabel = settingsButtonLabel
        settingsButton.accessibilityIdentifier = "keyboardSettingsToggle"
        settingsButton.tintColor = .secondaryLabel
        settingsButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        settingsButton.addTarget(self, action: #selector(toggleSettings), for: .touchUpInside)
        emojiButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        emojiButton.accessibilityLabel = "Open emoji"
        emojiButton.accessibilityIdentifier = "searchEmoji"
        emojiButton.tintColor = .secondaryLabel
        emojiButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        emojiButton.addTarget(self, action: #selector(toggleEmoji), for: .touchUpInside)
        emojiButton.canActivate = { [weak self] in self?.plane.hasActiveContact == false }
        settingsButton.canActivate = { [weak self] in self?.plane.hasActiveContact == false }
        plane.onContactBegin = { [weak self] in
            self?.dismissEmojiTones()
            self?.emojiButton.cancelTap()
            self?.settingsButton.cancelTap()
        }
        browseSearchButton.setTitle("Search", for: .normal)
        browseSearchButton.titleLabel?.font = .systemFont(ofSize: 15)
        browseSearchButton.accessibilityLabel = "Search emoji"
        browseSearchButton.contentHorizontalAlignment = .leading
        browseSearchButton.accessibilityIdentifier = "emojiSearchField"
        browseSearchButton.addTarget(self, action: #selector(startEmojiSearch), for: .touchUpInside)
        emojiBrowseButton.setTitle("Browse emoji", for: .normal)
        emojiBrowseButton.titleLabel?.font = .systemFont(ofSize: 15)
        emojiBrowseButton.setContentHuggingPriority(.required, for: .horizontal)
        emojiBrowseButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        emojiBrowseButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        emojiBrowseButton.addTarget(self, action: #selector(showEmojiBrowse), for: .touchUpInside)
        emojiDelete.setImage(UIImage(systemName: "delete.left"), for: .normal)
        emojiDelete.accessibilityLabel = "Delete last character"
        let deleteWidth = emojiDelete.widthAnchor.constraint(equalToConstant: 44)
        deleteWidth.priority = .init(999)
        deleteWidth.isActive = true
        emojiDelete.addTarget(self, action: #selector(deleteFromEmojiBrowse), for: .touchUpInside)
        for item in [browseSearchButton, emojiDelete] { emojiHeader.addArrangedSubview(item) }
        emojiHeader.spacing = 4
        emojiHeader.isHidden = true
        emojiSearch.onActivate = { [weak self] in self?.startEmojiSearch() }
        emojiSearch.onClear = { [weak self] in self?.clearEmojiSearch() }
        emojiSearch.onChange = { [weak self] query in
            guard let self, self.isSearchingEmoji else { return }
            self.emojiQuery = query
            self.refreshEmojiSearch()
        }
        emojiSearch.onFocusLost = { [weak self] in
            guard let self, self.isSearchingEmoji else { return }
            self.hideEmoji()
        }
        for results in [browseResults, searchResults] {
            results.onSelect = { [weak self] in self?.selectEmoji($0) }
            results.onClearHistory = { [weak self] in self?.clearEmojiHistory() }
            results.onClearSearch = { [weak self] in self?.clearEmojiSearch() }
        }
        let back = settingsBackButton
        back.setTitle("Back", for: .normal)
        back.contentHorizontalAlignment = .leading
        back.accessibilityLabel = "Back to keyboard"
        back.widthAnchor.constraint(equalToConstant: 44).isActive = true
        back.addTarget(self, action: #selector(hideSettings), for: .touchUpInside)
        back.isHidden = true
        let title = settingsTitle
        title.text = settingsMenuTitle
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textAlignment = .left
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.7
        for item in [back, title] { settingsHeader.addArrangedSubview(item) }
        settingsHeader.isHidden = true
        let wordBack = wordBackButton
        wordBack.setTitle("Back", for: .normal)
        wordBack.contentHorizontalAlignment = .leading
        wordBack.accessibilityLabel = "Close word options"
        wordBack.widthAnchor.constraint(equalToConstant: 60).isActive = true
        wordBack.addTarget(self, action: #selector(hideWordOptions), for: .touchUpInside)
        wordTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        wordTitle.textAlignment = .center
        wordTitle.lineBreakMode = .byTruncatingMiddle
        let wordSpacer = UIView()
        wordSpacer.widthAnchor.constraint(equalToConstant: 60).isActive = true
        for item in [wordBack, wordTitle, wordSpacer] { wordHeader.addArrangedSubview(item) }
        wordHeader.isHidden = true
        root.addArrangedSubview(header)
        let body = keyboardBody
        for content in [plane, settingsPanel, emojiBody, touchDiagnostics, wordPanel] {
            content.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(content)
        }
        normalPlaneConstraints = [
            plane.topAnchor.constraint(equalTo: body.topAnchor), plane.bottomAnchor.constraint(equalTo: body.bottomAnchor)
        ]
        planeLeading = plane.leadingAnchor.constraint(equalTo: body.leadingAnchor)
        planeTrailing = plane.trailingAnchor.constraint(equalTo: body.trailingAnchor)
        planeLeading?.isActive = true
        planeTrailing?.isActive = true
        NSLayoutConstraint.activate(normalPlaneConstraints)
        for content in [settingsPanel, emojiBody, touchDiagnostics] {
            let inset: CGFloat = content == emojiBody ? 6 : 0
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: inset),
                content.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -inset),
                content.topAnchor.constraint(equalTo: body.topAnchor), content.bottomAnchor.constraint(equalTo: body.bottomAnchor)
            ])
        }
        emojiBody.axis = .vertical
        emojiBody.addArrangedSubview(browseResults)
        emojiBody.addArrangedSubview(emojiFooter)
        let footerHeight = emojiFooter.heightAnchor.constraint(equalToConstant: 44)
        footerHeight.priority = .init(999)
        footerHeight.isActive = true
        emojiGlobe.setImage(UIImage(systemName: "globe"), for: .normal)
        emojiGlobe.accessibilityLabel = "Switch keyboard"
        let globeWidth = emojiGlobe.widthAnchor.constraint(equalToConstant: 44)
        globeWidth.priority = .init(999)
        globeWidth.isActive = true
        emojiGlobe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let footerSpace = UIView()
        for item in [emojiGlobe, footerSpace] { emojiFooter.addArrangedSubview(item) }
        browseResults.attachCategories(to: footerSpace)
        expandButton.setImage(UIImage(systemName: "arrow.left.and.right"), for: .normal)
        expandButton.accessibilityLabel = "Use full keyboard width"
        expandButton.addTarget(self, action: #selector(expandKeyboard), for: .touchUpInside)
        body.addSubview(expandButton)
        wordPanel.axis = .vertical
        wordPanel.spacing = 8
        let wordHelp = UILabel()
        wordHelp.text = "Forget removes local word history."
        wordHelp.font = .systemFont(ofSize: 13)
        wordHelp.textColor = .secondaryLabel
        wordHelp.numberOfLines = 0
        forgetWordButton.setTitle("Forget word", for: .normal)
        forgetWordButton.addTarget(self, action: #selector(forgetSelectedWord), for: .touchUpInside)
        protectWordButton.addTarget(self, action: #selector(toggleWordProtection), for: .touchUpInside)
        for button in [forgetWordButton, protectWordButton] {
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        for item in [forgetWordButton, protectWordButton, wordHelp] { wordPanel.addArrangedSubview(item) }
        NSLayoutConstraint.activate([
            wordPanel.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 16),
            wordPanel.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -16),
            wordPanel.topAnchor.constraint(equalTo: body.topAnchor, constant: 8)
        ])
        wordPanel.isHidden = true
        settingsPanel.isHidden = true
        touchDiagnostics.isHidden = true
        emojiBody.isHidden = true
        root.addArrangedSubview(body)
        plane.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        settingsPanel.onTouchDiagnostics = { [weak self] in self?.showTouchDiagnostics() }
        settingsPanel.onPrivateChange = { [weak self] in self?.setPrivateTyping($0) }
        settingsPanel.onAppearanceChange = { [weak self] in
            guard let self else { return }
            self.storage.largerKeyLabels = self.settingsPanel.largerLabelsSwitch.isOn
            self.storage.highContrast = self.settingsPanel.highContrastSwitch.isOn
            self.applyAccessibilityOptions()
        }
        settingsPanel.onCursorChange = { [weak self] speed in
            self?.storage.cursorSpeed = speed
            self?.plane.cursorSpeed = speed
        }
        settingsPanel.onPreferredLanguageChange = { [weak self] preference in
            guard let self else { return }
            self.storage.preferredLanguage = preference
            self.cancelSuggestionInteraction()
            self.neuralService.clear()
            self.neuralWords = []
            self.neuralContext = nil
            self.invalidateEditingState()
            self.configureSettings()
        }
        settingsPanel.onKeyboardLayoutChange = { [weak self] layout in
            guard let self, self.language != layout else { return }
            self.switchLanguage()
            self.configureSettings()
        }
        settingsPanel.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.persist()
            self.storage.keyboardSize = KeyboardSize.allCases[self.settingsPanel.sizeControl.selectedSegmentIndex]
            self.storage.keyboardHand = KeyboardHand.allCases[self.settingsPanel.handControl.selectedSegmentIndex]
            self.storage.numberRow = self.settingsPanel.numberRowSwitch.isOn
            self.applyLayoutOptions()
        }
        settingsPanel.onNeuralChange = { [weak self] value in
            self?.storage.neuralPrediction = value
            self?.reloadLanguage()
            self?.configureSettings()
        }
        settingsPanel.onCorrectionChange = { [weak self] value in
            self?.storage.autocorrection = value
            self?.configureSettings()
        }
        settingsPanel.onLearningChange = { [weak self] value in
            guard let self, !self.isPrivateTyping else { return }
            self.saveTask?.cancel()
            self.persist()
            self.storage.learning = value
            self.reloadLanguage()
            self.configureSettings()
        }
        settingsPanel.onDelete = { [weak self] in
            guard let self else { return }
            self.saveTask?.cancel()
            self.storage.clear()
            self.reloadLanguage()
            self.configureSettings()
        }
        plane.onGeometryChange = { [weak self] in
            self?.dismissEmojiTones()
            self?.plane.cancelDeletePress()
            self?.clearDeletionActions()
            self?.invalidateSuggestionPress()
            self?.plane.cancelSymbolDrag()
            self?.synchronizeTouchProfile()
        }
        plane.onKey = { [weak self] in self?.type($0) }
        plane.onDeleteStart = { [weak self] in
            guard let self else { return false }
            self.deletePressHost = self.hostState
            return self.beginWordDeletion()
        }
        plane.onDeleteKey = { [weak self] hit in
            guard let self, self.deletePressHost == self.hostState else { return false }
            self.type(hit)
            self.deletePressHost = self.hostState
            return true
        }
        plane.onDeletePreview = { [weak self] in self?.previewWordDeletion($0) }
        plane.onDeleteCommit = { [weak self] in self?.commitWordDeletion() }
        plane.onDeleteCancel = { [weak self] in self?.cancelWordDeletion() }
        plane.onDeleteWord = { [weak self] in
            guard let self, self.beginWordDeletion() else { return false }
            self.previewWordDeletion(1)
            self.commitWordDeletion()
            return true
        }
        plane.onCursor = { [weak self] offset in
            guard let self, !self.demoMode, !self.isSearchingEmoji else { return }
            self.proxy.adjustTextPosition(byCharacterOffset: offset)
            self.invalidateEditingState()
            self.updateSuggestions()
        }
        requestSupplementaryLexicon { [weak self] lexicon in
            guard let self else { return }
            for entry in lexicon.entries {
                self.registerLexiconEntry(input: entry.userInput, replacement: entry.documentText)
            }
        }
        alternatePopup.isHidden = true
        view.addSubview(alternatePopup)
        emojiTonePanel.isHidden = true
        view.addSubview(emojiTonePanel)
        plane.onAlternatesChange = { [weak self] options, frame, selected in
            guard let self else { return }
            self.dismissEmojiTones()
            self.keyboardHeader?.isUserInteractionEnabled = options.isEmpty
            self.searchQueryRow.blocksTouches = !options.isEmpty
            self.alternatePopup.options = options
            self.alternatePopup.selected = selected
            self.alternatePopup.highContrast = self.plane.usesHighContrast
            self.alternatePopup.frame = self.plane.convert(frame, to: self.view)
            self.alternatePopup.isHidden = options.isEmpty
            self.view.bringSubviewToFront(self.alternatePopup)
            self.alternatePopup.setNeedsDisplay()
        }
        emojiTonePanel.onCancel = { [weak self] in self?.dismissEmojiTones() }
        emojiTonePanel.onSelect = { [weak self] text in self?.selectEmojiTone(text) }
        for results in [browseResults, searchResults] {
            results.onToneRequest = { [weak self] text in self?.showEmojiTones(for: text) }
        }
        updateInputSurface()
        applyAccessibilityOptions()
    }

    func registerLexiconEntry(input: String, replacement: String) {
        lexiconWords.insert(replacement.lowercased())
        lexiconReplacements[input.lowercased()] = replacement
        for part in replacement.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(part)
            if TextRules.isWord(word), word.first?.isUppercase == true { properForms[word.lowercased()] = word }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        emojiHostSurface = nil
        restoringEmojiHost = false
        emojiSearchDocument = nil
        accessibilityVisible = true
        plane.accessibilityInputEnabled = true
        applyAccessibilityOptions()
        plane.showsGlobe = demoMode || needsInputModeSwitchKey
        plane.globeButton.isEnabled = !demoMode
        emojiGlobe.isHidden = !plane.showsGlobe || demoMode
        emojiGlobe.isEnabled = !demoMode
        if isShowingEmoji && !isSearchingEmoji { emojiFooter.isHidden = false }
        neuralSuspended = false
        rebaseLearningBoundary()
        reloadLanguage()
        updateInputSurface()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let startupInterval {
            KeyboardPerformance.signposter.endInterval("Keyboard startup", startupInterval)
            self.startupInterval = nil
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyLayoutOptions()
    }

    private func applyAccessibilityOptions() {
        suggestions.setNeedsLayout()
        if plane.largerKeyLabels != storage.largerKeyLabels { plane.largerKeyLabels = storage.largerKeyLabels }
        if plane.highContrast != storage.highContrast { plane.highContrast = storage.highContrast }
        let contrast = storage.highContrast || traitCollection.accessibilityContrast == .high
        view.tintColor = contrast ? .label : UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.30, green: 0.85, blue: 0.80, alpha: 1)
                : UIColor(red: 0, green: 0.42, blue: 0.408, alpha: 1)
        }
        settingsButton.tintColor = contrast ? .label : .secondaryLabel
        emojiButton.tintColor = contrast ? .label : .secondaryLabel
        view.backgroundColor = contrast ? .systemBackground : .systemGroupedBackground
        settingsPanel.applyContrast(contrast)
        emojiSearch.applyContrast(contrast)
    }

    private func applyLayoutOptions() {
        let compact = traitCollection.verticalSizeClass == .compact
        let height = CGFloat(KeyboardLayout.height(compact: compact, emoji: isSearchingEmoji,
            size: storage.keyboardSize, numberRow: storage.numberRow))
        if heightConstraint?.constant != height { heightConstraint?.constant = height }
        if plane.compact != compact { plane.compact = compact }
        if plane.numberRow != storage.numberRow { plane.numberRow = storage.numberRow }
        plane.cursorSpeed = storage.cursorSpeed
        plane.cursorMovementEnabled = !demoMode && !isSearchingEmoji
        let available = max(0, view.safeAreaLayoutGuide.layoutFrame.width - 4)
        let width = CGFloat(KeyboardLayout.typingWidth(available: Double(available), hand: storage.keyboardHand))
        let gap = available - width
        planeLeading?.constant = storage.keyboardHand == .right ? gap : 0
        planeTrailing?.constant = storage.keyboardHand == .left ? -gap : 0
        let privateSlot: CGFloat = isPrivateTyping ? 56 : 0
        let leadingGap = storage.keyboardHand == .right ? gap : 0
        let trailingGap = storage.keyboardHand == .left ? gap : 0
        predictionLeading?.constant = 54 + privateSlot + leadingGap
        predictionTrailing?.constant = -54 - trailingGap
        emojiLeading?.constant = 54 + privateSlot + leadingGap
        emojiTrailing?.constant = -54 - trailingGap
        settingsLeading?.constant = 54 + privateSlot + leadingGap
        settingsTrailing?.constant = -54 - trailingGap
        settingsButtonLeading?.constant = 6 + leadingGap
        emojiButtonTrailing?.constant = -6 - trailingGap
        emojiButton.isHidden = isShowingWordOptions
        settingsButton.isHidden = isShowingWordOptions
        settingsButton.setImage(UIImage(systemName: isShowingSettings ? "xmark" : "gearshape"), for: .normal)
        settingsButton.accessibilityLabel = isShowingSettings ? "Back to keyboard" : settingsButtonLabel
        emojiButton.setImage(isShowingEmoji ? nil : UIImage(systemName: "face.smiling"), for: .normal)
        emojiButton.setTitle(isShowingEmoji ? "ABC" : nil, for: .normal)
        emojiButton.accessibilityLabel = isShowingEmoji ? "Back to typing" : "Open emoji"
        for leading in otherStripLeading { leading.constant = 6 }
        privateIndicator.isHidden = !isPrivateTyping
        let navigationHeader = isShowingWordOptions
        if navigationHeader {
            privateIndicatorLeading?.isActive = false
            privateIndicatorTrailing?.constant = -10
            privateIndicatorTrailing?.isActive = true
        } else {
            privateIndicatorTrailing?.isActive = false
            privateIndicatorLeading?.constant = 54 + leadingGap
            privateIndicatorLeading?.isActive = true
        }
        updateHeaderAccessibilityOrder()
        expandButton.frame = CGRect(x: storage.keyboardHand == .left ? width : 0,
            y: max(0, keyboardBody.bounds.midY - 22), width: gap, height: 44)
        expandButton.isHidden = gap < 44 || isShowingSettings || isShowingWordOptions || (isShowingEmoji && !isSearchingEmoji)
        onLayoutOptionsChange?(storage.keyboardSize, storage.numberRow)
        synchronizeTouchProfile()
    }

    private func updateHeaderAccessibilityOrder() {
        var order: [UIView]
        if isShowingSettings {
            order = (isShowingTouchDiagnostics ? [settingsBackButton] : []) + [settingsTitle, emojiButton, settingsButton]
        } else if isShowingWordOptions {
            order = [wordBackButton, wordTitle]
        } else if isShowingEmoji {
            order = isSearchingEmoji ? [searchResults] : [browseSearchButton, emojiDelete]
            order += [emojiButton, settingsButton]
        } else {
            if !correctionStrip.isHidden { order = [correctionLabel, undoButton] }
            else if !deletionStrip.isHidden {
                order = [deletionLabel] + (restoreButton.isHidden ? [] : [restoreButton])
            } else { order = suggestionButtons.filter { $0.isEnabled && !$0.isHidden } }
            order += [emojiButton, settingsButton]
        }
        if isPrivateTyping {
            if isShowingWordOptions { order.append(privateIndicator) }
            else { order.insert(privateIndicator, at: 0) }
        }
        if !isShowingWordOptions {
            order.removeAll { $0 === emojiButton || $0 === settingsButton }
            order.insert(settingsButton, at: 0)
            order.append(emojiButton)
        }
        keyboardHeader?.accessibilityElements = order
    }

    @objc func expandKeyboard() {
        storage.keyboardHand = .full
        view.setNeedsLayout()
        configureSettings()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        plane.alternateTopInset = max(0, plane.convert(.zero, to: view).y - 2)
        if !emojiTonePanel.isHidden { layoutEmojiTonePanel() }
        synchronizeTouchProfile()
    }

    private func synchronizeTouchProfile() {
        guard plane.bounds.width > 0 else { return }
        let geometryChanged = touchGeometry != plane.bounds.size
        if geometryChanged {
            touchGeometry = plane.bounds.size
            hits = []
            touchCorrection = nil
            lastTouchWord = nil
        }
        let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? plane.compact
        let geometry = storage.keyboardSize == .standard && !storage.numberRow && storage.keyboardHand == .full ? "" :
            "." + storage.keyboardSize.rawValue + (storage.numberRow ? ".numbers" : "") + "." + storage.keyboardHand.rawValue
        let profile = TouchProfile(layout: language, landscape: landscape, width: Double(plane.bounds.width), geometry: geometry)
        guard profile != activeTouchProfile else {
            if geometryChanged && isShowingTouchDiagnostics { refreshTouchDiagnostics() }
            return
        }
        if let activeTouchProfile { storage.saveTouches(plane.touchModel, profile: activeTouchProfile) }
        activeTouchProfile = profile
        plane.touchModel = storage.touches(profile: profile)
        hits = []
        touchCorrection = nil
        lastTouchWord = nil
        if isShowingTouchDiagnostics { refreshTouchDiagnostics() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        accessibilityVisible = false
        plane.accessibilityInputEnabled = false
        lastAccessibilityFeedback = nil
        plane.cancelSymbolDrag()
        plane.cancelDeletePress()
        cancelSuggestionInteraction()
        hideWordOptions()
        hideEmoji()
        emojiHostSurface = nil
        restoringEmojiHost = false
        emojiSearchDocument = nil
        saveTask?.cancel()
        persist()
        invalidateEditingState()
        neuralService.clear()
        neuralWords = []
        neuralContext = nil
        emojiHeader.isHidden = true
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        isShowingSettings = false
        predictionStrip.isHidden = false
        settingsHeader.isHidden = true
        settingsPanel.isHidden = true
        settingsPanel.resetConfirmation()
        closeTouchDiagnostics()
        plane.isHidden = false
        if isPrivateTyping {
            rebaseLearningBoundary()
            storage.privateTyping = false
            predictor = PredictionEngine(memory: storage.multilingualMemory, multilingual: true)
            activeTouchProfile = nil
            plane.touchModel = .init()
            synchronizeTouchProfile()
            privateIndicator.isHidden = true
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        neuralService.clear()
        neuralWords = []
        neuralContext = nil
        neuralEngine = "Basic predictions"
        neuralSuspended = true
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        checkEmojiInputDocument()
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        super.selectionWillChange(textInput)
        if isReturningSearchDocument { return }
        checkEmojiInputDocument()
        if !isShowingEmoji {
            invalidateEditingState(preservingSuggestionSpace: true)
            if !plane.capsLocked { plane.shifted = false }
            showSuggestions([])
        }
    }

    private func checkEmojiInputDocument() {
        guard isSearchingEmoji, !changingEmojiInput, !demoMode else { return }
        let state = hostState
        let document = state.document
        if document == nil, emojiSearch.hasFocus {
            let matchesHost = (state.before ?? "") == (expectedHostState?.before ?? "") &&
                (state.after ?? "") == (expectedHostState?.after ?? "") &&
                (state.selection ?? "") == (expectedHostState?.selection ?? "")
            let matchesSearch = emojiSearch.matchesInput(before: state.before, after: state.after, selection: state.selection)
            if (emojiSearchDocument != nil && matchesHost) || (!matchesHost && !matchesSearch) {
                hideEmoji()
            }
        } else if let emojiSearchDocument {
            if document != emojiSearchDocument { hideEmoji() }
        } else if emojiSearch.hasFocus, document != expectedHostState?.document {
            emojiSearchDocument = document
        }
    }

    private func editEmojiInput(_ action: () -> Void) {
        let previous = changingEmojiInput
        changingEmojiInput = true
        defer { changingEmojiInput = previous }
        action()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateInputSurface()
        if isReturningSearchDocument { return }
        checkEmojiInputDocument()
        if isShowingEmoji, !emojiSearch.hasFocus, let expectedHostState, expectedHostState != hostState { hideEmoji() }
        let state = hostState
        if expectedContext != context || expectedHostState?.document != state.document ||
            (wordDeletion != nil || restoreHost != nil || suggestionPress != nil) && expectedHostState != state {
            if learningBoundary != nil { rebaseLearningBoundary() }
            invalidateEditingState()
        }
        if !isShowingEmoji { expectedContext = context; expectedHostState = state }
        updateSuggestions()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        updateInputSurface()
        if isReturningSearchDocument { return }
        checkEmojiInputDocument()
        if isShowingEmoji, !emojiSearch.hasFocus, let expectedHostState, expectedHostState != hostState { hideEmoji() }
        if learningBoundary != nil { rebaseLearningBoundary() }
        invalidateEditingState(preservingSuggestionSpace: true)
        if !isShowingEmoji { expectedContext = context; expectedHostState = hostState }
        updateSuggestions()
    }

    private func insert(_ text: String) {
        suggestionSpaceHost = nil
        if demoMode { demoText += text; onDemoTextChange?(demoText) }
        else { proxy.insertText(text) }
        expectedContext = context
        expectedHostState = hostState
    }
    private func delete(_ count: Int = 1) {
        suggestionSpaceHost = nil
        for _ in 0..<count {
            if demoMode { if !demoText.isEmpty { demoText.removeLast() } }
            else { proxy.deleteBackward() }
        }
        if demoMode { onDemoTextChange?(demoText) }
        expectedContext = context
        expectedHostState = hostState
    }
    private func invalidateEditingState(preservingSuggestionSpace: Bool = false) {
        let previousSuggestionSpace = suggestionSpaceHost
        suggestionSpaceHost = nil
        plane.cancelDeletePress()
        deletePressHost = nil
        clearDeletionActions()
        invalidateSuggestionPress()
        touchCorrection = nil
        lastTouchWord = nil
        undo = nil
        undoHostState = nil
        rejectedWord = nil
        hits = []
        lastSpace = .distantPast
        lastShift = .distantPast
        shiftWasManual = false
        if preservingSuggestionSpace, previousSuggestionSpace == hostState {
            suggestionSpaceHost = previousSuggestionSpace
        }
    }

    private func reloadLanguage() {
        neuralService.clear()
        neuralWords = []
        neuralContext = nil
        neuralEngine = storage.neuralPrediction && !neuralSuspended ? "Loading predictions" : "Basic predictions"
        predictor = PredictionEngine(memory: storage.multilingualMemory, multilingual: true)
        plane.language = language
        activeTouchProfile = nil
        plane.touchModel = .init()
        synchronizeTouchProfile()
        plane.page = 0
        plane.capsLocked = false
        primaryLanguage = language.rawValue
        invalidateEditingState()
        updateSuggestions()
    }

    @objc func switchLanguage() {
        saveTask?.cancel()
        persist()
        storage.language = language == .english ? .german : .english
        reloadLanguage()
    }

    private func corrections(for word: String, manual: Bool = false) -> [String] {
        let policy = inputPolicy
        guard (manual ? policy.allowsManualCorrections : policy.allowsCorrectionAndLearning),
              TextRules.isWord(word), isPrivateTyping || !lexiconWords.contains(word.lowercased()),
              !storage.protectedWords.contains(word.lowercased()) else { return [] }
        let language = spelling.writingLanguage(in: context, preference: storage.preferredLanguage)
        if manual { return spelling.manualCorrections(word, language: language) }
        if predictor.memory.words[word.lowercased()] != nil {
            return spelling.contractions(word, language: language)
        }
        return spelling.corrections(word, language: language)
    }

    private func updateSuggestions() {
        let interval = KeyboardPerformance.signposter.beginInterval("Dictionary update", id: KeyboardPerformance.signposter.makeSignpostID())
        defer { KeyboardPerformance.signposter.endInterval("Dictionary update", interval) }
        guard !suggestionButtons.isEmpty, !isShowingSettings, !isShowingEmoji, !isShowingWordOptions else { return }
        if allowsPredictions, !demoMode, effectiveHostSurface.type == .URL,
           let addresses = TextRules.urlCompletions(before: context) {
            neuralService.clear()
            neuralWords = []
            neuralContext = nil
            neuralEngine = "URL completions"
            showSuggestions(addresses)
            updateShift()
            return
        }
        let token = TextRules.prefix(before: context)
        let currentContext = context
        let writingLanguage = spelling.writingLanguage(in: currentContext, preference: storage.preferredLanguage)
        let completions = allowsPredictions ? spelling.completions(token, language: writingLanguage) : []
        let correctionWords = Array(corrections(for: token, manual: true).prefix(24))
        let capitalization: KeyboardLanguage = writingLanguage == .german ? .german : .english
        let sentenceStart = automaticCapitalization
        let currentNeural = neuralContext == currentContext ? neuralWords : []
        let languageScores = spelling.rankingScores(Array(completions.prefix(24)) + correctionWords + currentNeural,
                                                   language: writingLanguage)
        let suggestions = allowsPredictions ? predictor.suggestions(context: currentContext,
            completions: Array(completions.prefix(24)), corrections: correctionWords,
            neural: currentNeural,
            lowercaseEnglishWords: Self.lowercaseEnglishWords, properForms: isPrivateTyping ? [:] : properForms,
            capitalizationLanguage: capitalization, sentenceStart: sentenceStart,
            writingLanguage: writingLanguage, languageScores: languageScores, limit: 4) : []
        showSuggestions(suggestions)
        let neuralLanguage = writingLanguage.neuralLanguage.flatMap { neuralService.supports($0) ? $0 : nil }
        if storage.neuralPrediction, !neuralSuspended, allowsPredictions,
           let currentLanguage = neuralLanguage, TextRules.suggestionToken(before: currentContext) != nil {
            let requestDocument = hostState.document
            neuralService.request(context: currentContext, language: currentLanguage,
                                  candidates: correctionWords + Array(completions.prefix(24))) { [weak self] result in
                guard let self, self.context == currentContext,
                      self.storage.neuralPrediction, self.allowsPredictions, !self.isShowingEmoji, !self.isShowingSettings, !self.isShowingWordOptions,
                      self.hostState.document == requestDocument else { return }
                self.neuralContext = currentContext
                self.neuralWords = result.words.filter { self.spelling.isKnown($0) || correctionWords.contains($0) }
                self.neuralEngine = result.engine
                let scores = self.spelling.rankingScores(Array(completions.prefix(24)) + correctionWords + self.neuralWords,
                                                        language: writingLanguage)
                self.showSuggestions(self.predictor.suggestions(context: currentContext, completions: Array(completions.prefix(24)),
                    corrections: correctionWords, neural: self.neuralWords,
                    lowercaseEnglishWords: Self.lowercaseEnglishWords, properForms: self.isPrivateTyping ? [:] : self.properForms,
                    capitalizationLanguage: capitalization, sentenceStart: self.automaticCapitalization,
                    writingLanguage: writingLanguage, languageScores: scores, limit: 4))
            }
        } else {
            neuralService.clear()
            neuralWords = []
            neuralContext = nil
            neuralEngine = neuralLanguage == nil ? "Multilingual dictionary" : "Basic predictions"
        }
        updateShift()
    }

    private func showSuggestions(_ suggestions: [String]) {
        if let suggestionPress {
            if suggestionPress.host != hostState { suggestionPressInvalidated = true }
            deferredSuggestions = suggestions
            return
        }
        let showDeletion = deletionPreviewVisible || canRestoreDeletion
        let showUndo = canUndoCorrection
        let feedback = showUndo && !showDeletion ? "Correction available. Undo restores the original word." :
            canRestoreDeletion && !deletionPreviewVisible ? "Text deleted. Restore is available." : nil
        if feedback != lastAccessibilityFeedback {
            lastAccessibilityFeedback = feedback
            if let feedback, voiceOverActive(), accessibilityVisible {
                let message = NSAttributedString(string: feedback,
                    attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.low.rawValue])
                postAccessibility(.announcement, message)
            }
        }
        if demoMode { onDemoCorrectionChange?(showUndo) }
        self.suggestions.isHidden = showUndo || showDeletion
        correctionStrip.isHidden = !showUndo || showDeletion
        deletionStrip.isHidden = !showDeletion
        restoreButton.isHidden = !canRestoreDeletion || deletionPreviewVisible
        if !deletionPreviewVisible && canRestoreDeletion { deletionLabel.text = "Text deleted" }
        if showUndo, let undo {
            correctionLabel.text = undo.original + " > " + undo.replacement
            correctionLabel.accessibilityLabel = "Changed " + undo.original + " to " + undo.replacement
        }
        rankedSuggestions = suggestions
        renderSuggestions()
        renderedSuggestionHost = hostState
        updateHeaderAccessibilityOrder()
    }

    private var suggestionFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16),
            maximumPointSize: 24, compatibleWith: suggestions.traitCollection)
    }

    private func layoutSuggestions() {
        let geometry = CGSize(width: suggestions.bounds.width, height: suggestionFont.pointSize)
        let frame = suggestions.convert(suggestions.bounds, to: view)
        guard geometry != suggestionGeometry || frame != suggestionFrame else { return }
        if let press = suggestionPress {
            if press.host == hostState, let deferredSuggestions { rankedSuggestions = deferredSuggestions }
            cancelSuggestionInteraction()
        }
        renderSuggestions()
    }

    private func renderSuggestions() {
        let width = suggestions.bounds.width
        let font = suggestionFont
        suggestionGeometry = CGSize(width: width, height: font.pointSize)
        suggestionFrame = suggestions.convert(suggestions.bounds, to: view)
        var count = min(rankedSuggestions.count, suggestionButtons.count)
        while count > 2 {
            let slot = width / CGFloat(count)
            let fits = slot >= 44 && rankedSuggestions.prefix(count).allSatisfy {
                ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 16 <= slot
            }
            if fits { break }
            count -= 1
        }
        if width > 0 && width < 88 { count = min(count, 1) }
        for (index, button) in suggestionButtons.enumerated() {
            let visible = index < count
            let title = visible ? rankedSuggestions[index] : ""
            button.titleLabel?.font = font
            button.setTitle(title, for: .normal)
            button.isHidden = !visible
            button.isEnabled = visible
            button.accessibilityLabel = visible ? "Insert " + title : "No suggestion"
        }
        updateHeaderAccessibilityOrder()
    }

    @objc func beginSuggestionPress(_ sender: UIButton) {
        cancelledSuggestionButtons.remove(ObjectIdentifier(sender))
        guard suggestionPress == nil, !suggestions.isHidden,
              renderedSuggestionHost == hostState,
              let word = sender.title(for: .normal), !word.isEmpty else {
            cancelledSuggestionButtons.insert(ObjectIdentifier(sender))
            return
        }
        suggestionPress = SuggestionPress(button: sender, word: word, host: hostState)
        suggestionPressInvalidated = false
    }

    private func suggestionIsAvailable(_ button: UIButton) -> Bool {
        guard accessibilityVisible, button.isEnabled else { return false }
        var ancestor: UIView? = button
        while let current = ancestor {
            if current.isHidden || current.alpha < 0.01 || !current.isUserInteractionEnabled { return false }
            ancestor = current.superview
        }
        return true
    }

    private func suggestionWord(for button: UIButton) -> String? {
        guard !cancelledSuggestionButtons.contains(ObjectIdentifier(button)) else { return nil }
        if let suggestionPress {
            guard suggestionPress.button === button, !suggestionPressInvalidated,
                  suggestionPress.host == hostState else { return nil }
            return suggestionPress.word
        }
        guard renderedSuggestionHost == hostState else { return nil }
        return button.title(for: .normal)
    }

    private func invalidateSuggestionPress() {
        if suggestionPress != nil { suggestionPressInvalidated = true }
    }

    @objc private func cancelSuggestionPress(_ sender: UIButton) {
        cancelledSuggestionButtons.remove(ObjectIdentifier(sender))
        guard suggestionPress?.button === sender else { return }
        finishSuggestionPress(refresh: true)
    }

    private func finishSuggestionPress(refresh: Bool) {
        suggestionPress = nil
        suggestionPressInvalidated = false
        let deferred = deferredSuggestions
        deferredSuggestions = nil
        if refresh {
            if let deferred { showSuggestions(deferred) }
            updateSuggestions()
        }
    }

    private func cancelSuggestionInteraction() {
        if let suggestionPress { cancelledSuggestionButtons.insert(ObjectIdentifier(suggestionPress.button)) }
        finishSuggestionPress(refresh: false)
    }

    @discardableResult
    func beginWordDeletion() -> Bool {
        guard !isShowingEmoji, !isShowingSettings, !isShowingWordOptions,
              let before = hostState.before, (hostState.selection ?? "").isEmpty else { return false }
        let suffixes = TextRules.wordDeletionSuffixes(before: before, allowLeadingToken: demoMode)
        guard !suffixes.isEmpty else { return false }
        wordDeletion = WordDeletion(host: hostState, suffixes: suffixes)
        deletionWordCount = 0
        return true
    }

    func previewWordDeletion(_ count: Int) {
        guard let wordDeletion, wordDeletion.host == hostState else { cancelWordDeletion(); return }
        deletionWordCount = min(max(0, count), wordDeletion.suffixes.count)
        deletionPreviewVisible = true
        if deletionWordCount == 0 { deletionLabel.text = "Release to cancel" }
        else {
            let text = wordDeletion.suffixes[deletionWordCount - 1].trimmingCharacters(in: .whitespaces)
            deletionLabel.text = "Delete \(deletionWordCount) \(deletionWordCount == 1 ? "word" : "words"): " + String(text.prefix(48))
        }
        showSuggestions([])
    }

    func commitWordDeletion() {
        guard let wordDeletion, wordDeletion.host == hostState, deletionWordCount > 0 else {
            cancelWordDeletion()
            return
        }
        let text = wordDeletion.suffixes[deletionWordCount - 1]
        invalidateEditingState()
        delete(text.count)
        restoredText = text
        restoreHost = hostState
        updateSuggestions()
    }

    private func cancelWordDeletion() {
        let refresh = deletionPreviewVisible
        wordDeletion = nil
        deletionWordCount = 0
        deletionPreviewVisible = false
        if refresh { updateSuggestions() }
    }

    private func clearDeletionActions() {
        wordDeletion = nil
        deletionWordCount = 0
        deletionPreviewVisible = false
        restoredText = nil
        restoreHost = nil
        deletionStrip.isHidden = true
        suggestions.isHidden = canUndoCorrection
        correctionStrip.isHidden = !canUndoCorrection
        updateHeaderAccessibilityOrder()
    }

    private var canRestoreDeletion: Bool {
        restoredText != nil && restoreHost == hostState && (hostState.selection ?? "").isEmpty
    }

    @objc func restoreDeletedText() {
        guard canRestoreDeletion, let text = restoredText else {
            clearDeletionActions()
            updateSuggestions()
            return
        }
        invalidateEditingState()
        insert(text)
        updateSuggestions()
        restoreAccessibilityFocus()
    }

    private var canUndoCorrection: Bool {
        allowsWords && undo?.matches(context) == true && undoHostState == hostState && (hostState.selection ?? "").isEmpty
    }

    @objc func undoCorrection() {
        guard canUndoCorrection, let undo else {
            self.undo = nil
            undoHostState = nil
            updateSuggestions()
            return
        }
        touchCorrection = nil
        lastTouchWord = nil
        hits = []
        delete(undo.replacement.count + 1)
        insert(undo.original)
        rejectedWord = undo.original
        self.undo = nil
        undoHostState = nil
        lastSpace = .distantPast
        updateSuggestions()
        restoreAccessibilityFocus()
    }

    @objc private func holdSuggestion(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton,
              let word = suggestionWord(for: button) else { return }
        showWordOptions(word, origin: button)
    }

    @discardableResult
    func showWordOptions(_ word: String, origin: UIButton? = nil) -> Bool {
        guard accessibilityVisible, !plane.isHidden, allowsPredictions, TextRules.isWord(word),
              !isShowingSettings, !isShowingEmoji else { return false }
        cancelSuggestionInteraction()
        plane.cancelDeletePress()
        clearDeletionActions()
        plane.cancelSymbolDrag()
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        selectedWord = word
        wordOrigin = origin
        wordTitle.text = word
        protectWordButton.setTitle(storage.protectedWords.contains(word.lowercased()) ? "Allow correction" : "Never correct this", for: .normal)
        isShowingWordOptions = true
        neuralService.clear()
        predictionStrip.isHidden = true
        wordHeader.isHidden = false
        wordPanel.isHidden = false
        plane.isHidden = true
        view.setNeedsLayout()
        UIAccessibility.post(notification: .screenChanged, argument: forgetWordButton)
        return true
    }

    @objc func hideWordOptions() {
        guard isShowingWordOptions else { return }
        let origin = wordOrigin
        let originalWord = selectedWord
        wordOrigin = nil
        isShowingWordOptions = false
        selectedWord = nil
        wordHeader.isHidden = true
        wordPanel.isHidden = true
        predictionStrip.isHidden = false
        plane.isHidden = false
        updateSuggestions()
        view.setNeedsLayout()
        restoreAccessibilityFocus(preferred: origin, word: originalWord)
    }

    private func restoreAccessibilityFocus(preferred: UIButton? = nil, word: String? = nil) {
        guard voiceOverActive(), accessibilityVisible, !plane.isHidden, !isShowingSettings, !isShowingEmoji else { return }
        if let preferred, preferred.isEnabled, !preferred.isHidden, preferred.currentTitle == word {
            postAccessibility(.layoutChanged, preferred)
        } else if let suggestion = suggestionButtons.first(where: { $0.isEnabled && !$0.isHidden }) {
            postAccessibility(.layoutChanged, suggestion)
        } else if let key = plane.accessibilityElements?.first {
            postAccessibility(.layoutChanged, key)
        }
    }

    @objc func forgetSelectedWord() {
        guard let word = selectedWord else { return }
        forgetWordHistory(word)
        hideWordOptions()
    }

    private func forgetWordHistory(_ word: String) {
        saveTask?.cancel()
        predictor.memory.forget(word)
        storage.forgetWord(word)
        storage.saveWords(predictor.memory)
    }

    @objc func toggleWordProtection() {
        guard let word = selectedWord else { return }
        let protected = storage.protectedWords.contains(word.lowercased())
        storage.setProtected(word, enabled: !protected)
        if protected { forgetWordHistory(word) }
        if !protected && !storage.protectedWords.contains(word.lowercased()) {
            wordTitle.text = "Word limit reached"
            return
        }
        hideWordOptions()
    }

    private var automaticCapitalization: Bool {
        let state = hostState
        let hasText = demoMode ? !demoText.isEmpty : proxy.hasText
        let capitalization = effectiveHostSurface.capitalization ?? .sentences
        switch capitalization {
        case .allCharacters: return true
        case .words:
            guard let before = state.before else { return !hasText && (state.after ?? "").isEmpty }
            return before.isEmpty || before.last?.isWhitespace == true
        case .sentences:
            return TextRules.shouldCapitalizeSentence(before: state.before, after: state.after, hasText: hasText)
        default: return false
        }
    }

    private func updateShift() {
        if !plane.capsLocked && !shiftWasManual { plane.shifted = automaticCapitalization }
    }

    @objc private func acceptSuggestion(_ sender: UIButton) {
        if cancelledSuggestionButtons.remove(ObjectIdentifier(sender)) != nil { return }
        guard suggestionPress == nil || suggestionPress?.button === sender else { return }
        let word = suggestionWord(for: sender)
        finishSuggestionPress(refresh: false)
        guard suggestionIsAvailable(sender), allowsPredictions, !isShowingWordOptions, !isShowingSettings, !isShowingEmoji,
              let word, !word.isEmpty else { updateSuggestions(); return }
        selectSuggestion(word)
    }

    func selectSuggestion(_ word: String) {
        guard allowsPredictions else { return }
        clearDeletionActions()
        lastShift = .distantPast
        if !demoMode, effectiveHostSurface.type == .URL,
           TextRules.urlCompletions(before: context)?.contains(word) == true {
            delete(TextRules.token(before: context).count)
            insert(word)
            invalidateEditingState()
            updateSuggestions()
            return
        }
        let token = TextRules.prefix(before: context)
        guard TextRules.suggestionToken(before: context) != nil else { return }
        let before = String(context.dropLast(token.count))
        if storage.usesPersonalization && allowsWords {
            if !confirmTouchCorrection(word: word, before: before) {
                plane.train(original: token, replacement: word, hits: hits)
            }
        }
        touchCorrection = nil
        lastTouchWord = nil
        delete(token.count)
        insert(word + " ")
        if hostState.document != nil, hostState.before?.hasSuffix(word + " ") == true, (hostState.selection ?? "").isEmpty {
            suggestionSpaceHost = hostState
        }
        learn(word: word, before: before)
        undo = nil
        hits = []
        shiftWasManual = false
        updateSuggestions()
    }

    func type(_ hit: KeyHit) {
        dismissEmojiTones()
        let interval = KeyboardPerformance.signposter.beginInterval("Key processing", id: KeyboardPerformance.signposter.makeSignpostID())
        defer { KeyboardPerformance.signposter.endInterval("Key processing", interval) }
        clearDeletionActions()
        invalidateSuggestionPress()
        if hit.key != "shift" { lastShift = .distantPast }
        if isSearchingEmoji {
            switch hit.key {
            case "delete": editEmojiInput { emojiSearch.deleteBackward() }; return
            case "space": editEmojiInput { emojiSearch.insert(" ") }; return
            case "return": hideEmoji(); return
            case "language", "globe", "shift", "page", "more": break
            default:
                editEmojiInput { emojiSearch.insert(hit.literal ? hit.key : AlternateCharacters.cased(hit.key, uppercase: plane.shifted && plane.page == 0)) }
                if !plane.capsLocked { plane.shifted = false }
                return
            }
        }
        switch hit.key {
        case "language": switchLanguage(); return
        case "globe": if !demoMode { advanceToNextInputMode() }; return
        case "shift":
            if now().timeIntervalSince(lastShift) < 0.35 { plane.capsLocked.toggle(); plane.shifted = plane.capsLocked }
            else { plane.capsLocked = false; plane.shifted.toggle() }
            lastShift = now()
            shiftWasManual = true
            return
        case "page", "more":
            plane.page = hit.key == "page" ? (plane.page == 0 ? 1 : 0) : (plane.page == 1 ? 2 : 1)
            invalidateEditingState(preservingSuggestionSpace: true)
            return
        case "delete":
            if canUndoCorrection {
                undoCorrection()
            } else {
                captureTouchCorrection()
                let deletingSpace = context.hasSuffix(" ")
                delete()
                if !deletingSpace && !hits.isEmpty { hits.removeLast() }
                undo = nil
            }
            lastSpace = .distantPast
        case "space": commitSpace()
        case "return":
            let word = TextRules.prefix(before: context)
            _ = confirmTouchCorrection(word: word, before: String(context.dropLast(word.count)))
            insert("\n")
            invalidateEditingState()
        default:
            undo = nil
            rejectedWord = nil
            lastSpace = .distantPast
            if let expectedHostState, expectedHostState.document != hostState.document { shiftWasManual = false }
            updateShift()
            let key = hit.literal ? hit.key : AlternateCharacters.cased(hit.key, uppercase: plane.shifted && plane.page == 0)
            if TextRules.token(before: context).isEmpty && touchCorrection == nil { lastTouchWord = nil }
            if [".", ",", "?", "!", ":", ";"].contains(key), let suggestionSpaceHost,
               suggestionSpaceHost == hostState, hostState.before?.hasSuffix(" ") == true,
               (hostState.selection ?? "").isEmpty {
                delete()
            }
            insert(key)
            if key.count == 1 && (key.first?.isLetter == true || key == "'" || key == "\u{2019}") {
                if hits.count < 32 { hits.append(hit) }
            } else { hits = []; touchCorrection = nil; lastTouchWord = nil }
            if !plane.capsLocked { plane.shifted = false }
            shiftWasManual = false
        }
        updateSuggestions()
    }

    private func commitSpace() {
        let current = context
        if allowsWords, now().timeIntervalSince(lastSpace) < 0.4, current.hasSuffix(" "),
           let last = current.dropLast().last, last.isLetter || last.isNumber {
            delete()
            insert(". ")
            undo = nil
            touchCorrection = nil
            lastTouchWord = nil
            hits = []
            lastSpace = .distantPast
            shiftWasManual = false
            return
        }
        let word = TextRules.prefix(before: current)
        let before = String(current.dropLast(word.count))
        var replacement: String?
        if allowsWords && storage.autocorrection && !word.isEmpty && rejectedWord != word &&
            !storage.protectedWords.contains(word.lowercased()) {
            let expansion = isPrivateTyping ? nil : lexiconReplacements[word.lowercased()]
            let writingLanguage = spelling.writingLanguage(in: current, preference: storage.preferredLanguage)
            let capitalShortcut = expansion.map {
                ($0.count > 1 && $0 == $0.uppercased() && $0.contains(where: { $0.isLetter }) &&
                 !Self.lowercaseEnglishWords.contains(word.lowercased()) && writingLanguage == .english) ||
                ($0 == "I" && writingLanguage == .english)
            } ?? false
            if let expansion, expansion != word,
               expansion.caseInsensitiveCompare(word) != .orderedSame || capitalShortcut {
                replacement = expansion
            } else if predictor.memory.words[word.lowercased()] == nil,
                      let guess = spelling.automaticCorrection(word, candidates: corrections(for: word)) {
                replacement = TextRules.matchCase(guess, to: word)
            }
        }
        if let replacement {
            touchCorrection = nil
            lastTouchWord = nil
            delete(word.count)
            insert(replacement + " ")
            undo = CorrectionUndo(original: word, replacement: replacement, context: context)
            undoHostState = hostState
        } else {
            _ = confirmTouchCorrection(word: word, before: before)
            lastTouchWord = storage.usesPersonalization && allowsWords && word.count == hits.count && !word.isEmpty ?
                TouchCorrection(original: word, hits: hits, before: before, document: hostState.document, profile: activeTouchProfile) : nil
            touchCorrection = nil
            insert(" ")
            undo = nil
            if allowsWords { learn(word: word, before: before) }
        }
        hits = []
        rejectedWord = nil
        lastSpace = now()
        shiftWasManual = false
    }

    private func captureTouchCorrection() {
        guard storage.usesPersonalization, allowsWords, plane.page == 0, touchCorrection == nil else { return }
        if let lastTouchWord, context == lastTouchWord.before + lastTouchWord.original + " ",
           lastTouchWord.document == hostState.document, lastTouchWord.profile == activeTouchProfile {
            touchCorrection = lastTouchWord
            hits = lastTouchWord.hits
            self.lastTouchWord = nil
            return
        }
        let word = TextRules.prefix(before: context)
        guard !word.isEmpty, word.count == hits.count else { return }
        touchCorrection = TouchCorrection(original: word, hits: hits, before: String(context.dropLast(word.count)),
                                          document: hostState.document, profile: activeTouchProfile)
    }

    @discardableResult
    private func confirmTouchCorrection(word: String, before: String) -> Bool {
        guard storage.usesPersonalization, allowsWords, let correction = touchCorrection,
              correction.before == before, correction.document == hostState.document,
              correction.profile == activeTouchProfile, correction.original != word else { return false }
        plane.train(original: correction.original, replacement: word, hits: correction.hits)
        return true
    }

    private func learn(word: String, before: String) {
        guard storage.usesPersonalization && allowsWords else { return }
        var eligibleBefore = before
        if let learningBoundary {
            guard learningBoundary.document == hostState.document, before.hasPrefix(learningBoundary.prefix) else {
                rebaseLearningBoundary()
                return
            }
            eligibleBefore = String(before.dropFirst(learningBoundary.prefix.count))
            if learningBoundary.partialToken {
                guard let separator = eligibleBefore.firstIndex(where: { $0.isWhitespace }) else { return }
                eligibleBefore = String(eligibleBefore[eligibleBefore.index(after: separator)...])
            }
        }
        predictor.memory.learn(word: word, previous: TextRules.previousWord(before: eligibleBefore))
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.persist() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
    }

    private func rebaseLearningBoundary() {
        let state = hostState
        let prefix = state.before ?? ""
        if prefix.isEmpty && learningBoundary == nil && !isPrivateTyping { return }
        learningBoundary = LearningBoundary(document: state.document, prefix: prefix,
                                            partialToken: prefix.last?.isWhitespace == false)
    }
    private func persist() {
        guard storage.usesPersonalization else { return }
        storage.saveWords(predictor.memory)
        if let activeTouchProfile { storage.saveTouches(plane.touchModel, profile: activeTouchProfile) }
    }

    private func configureSettings() {
        settingsPanel.configure(neural: storage.neuralPrediction, correction: storage.autocorrection,
                                learning: storage.learning, engine: neuralEngine,
                                layout: language, size: storage.keyboardSize, hand: storage.keyboardHand, numberRow: storage.numberRow,
                                privateTyping: isPrivateTyping, cursorSpeed: storage.cursorSpeed,
                                preferredLanguage: storage.preferredLanguage,
                                largerKeyLabels: storage.largerKeyLabels, highContrast: storage.highContrast)
    }

    func setPrivateTyping(_ enabled: Bool) {
        guard enabled != isPrivateTyping else { return }
        plane.cancelDeletePress()
        plane.cancelSymbolDrag()
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        cancelSuggestionInteraction()
        saveTask?.cancel()
        if enabled { persist() }
        else { rebaseLearningBoundary() }
        storage.privateTyping = enabled
        browseResults.resetBrowsePosition()
        reloadLanguage()
        configureSettings()
        if isShowingEmoji {
            if isSearchingEmoji { refreshEmojiSearch() }
            else { emojiResults.showBrowse(frequent: storage.emojiUsage.ranked) }
        }
        view.setNeedsLayout()
    }

    @objc private func endPrivateTyping() { setPrivateTyping(false) }

    @objc private func toggleEmoji() {
        if isShowingEmoji { hideEmoji() }
        else { showEmoji() }
    }

    @objc private func toggleSettings() {
        if isShowingSettings { closeTouchDiagnostics(); hideSettings() }
        else { showSettings() }
    }

    @objc func showEmoji() {
        guard !isShowingEmoji else { return }
        cancelSuggestionInteraction()
        plane.cancelDeletePress()
        hideWordOptions()
        plane.cancelSymbolDrag()
        if isShowingSettings { closeTouchDiagnostics(); hideSettings() }
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        savedTypingState = (plane.page, plane.shifted, plane.capsLocked, shiftWasManual)
        expectedHostState = hostState
        isShowingEmoji = true
        emojiQuery = ""
        neuralService.clear()
        neuralWords = []
        neuralContext = nil
        invalidateEditingState()
        predictionStrip.isHidden = true
        emojiHeader.isHidden = false
        emojiBody.isHidden = false
        emojiGlobe.isHidden = !plane.showsGlobe || demoMode
        emojiGlobe.isEnabled = !demoMode
        showEmojiBrowse()
        view.setNeedsLayout()
    }

    private func rememberOwnedSearchDocument() {
        guard isSearchingEmoji, !demoMode, emojiSearch.hasFocus, emojiSearchDocument == nil else { return }
        let state = hostState
        guard state.document != emojiHostSurface?.document,
              emojiSearch.matchesInput(before: state.before, after: state.after, selection: state.selection) else { return }
        emojiSearchDocument = state.document
    }

    @objc func showEmojiBrowse() {
        rememberOwnedSearchDocument()
        lastShift = .distantPast
        guard isShowingEmoji else { return }
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        isSearchingEmoji = false
        restoringEmojiHost = emojiHostSurface != nil
        emojiSearch.finishEditing()
        updateInputSurface()
        plane.returnTitle = "return"
        emojiQuery = ""
        emojiSearch.update(query: "")
        emojiDelete.isHidden = false
        emojiFooter.isHidden = false
        searchQueryRow.isHidden = true
        searchResults.isHidden = true
        emojiHeader.isHidden = false
        emojiBody.isHidden = false
        plane.isHidden = true
        emojiResults.showBrowse(frequent: storage.emojiUsage.ranked)
        onEmojiSearchVisibilityChange?(false)
        view.setNeedsLayout()
    }

    @objc func startEmojiSearch() {
        guard isShowingEmoji, !isSearchingEmoji else { return }
        dismissEmojiTones()
        emojiHostSurface = effectiveHostSurface
        restoringEmojiHost = false
        isSearchingEmoji = true
        updateInputSurface()
        browseResults.resetConfirmation()
        emojiSearchDocument = nil
        plane.page = 0
        plane.shifted = false
        plane.capsLocked = false
        emojiDelete.isHidden = true
        emojiFooter.isHidden = true
        searchQueryRow.isHidden = false
        searchResults.isHidden = false
        emojiHeader.isHidden = true
        emojiBody.isHidden = true
        plane.isHidden = false
        plane.superview?.bringSubviewToFront(plane)
        refreshEmojiSearch()
        plane.returnTitle = "Done"
        onEmojiSearchVisibilityChange?(true)
        view.setNeedsLayout()
        editEmojiInput { emojiSearch.focus() }
        UIAccessibility.post(notification: .layoutChanged, argument: emojiSearch)
    }

    @objc func hideEmoji() {
        rememberOwnedSearchDocument()
        lastShift = .distantPast
        guard isShowingEmoji else { return }
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        isSearchingEmoji = false
        isShowingEmoji = false
        restoringEmojiHost = emojiHostSurface != nil
        emojiSearch.finishEditing()
        updateInputSurface()
        plane.returnTitle = "return"
        emojiQuery = ""
        emojiSearch.update(query: "")
        browseResults.resetConfirmation()
        searchQueryRow.isHidden = true
        searchResults.isHidden = true
        emojiHeader.isHidden = true
        emojiBody.isHidden = true
        plane.isHidden = false
        predictionStrip.isHidden = false
        onEmojiSearchVisibilityChange?(false)
        if let saved = savedTypingState {
            plane.page = saved.page
            plane.shifted = saved.shifted
            plane.capsLocked = saved.caps
            shiftWasManual = saved.manual
        }
        savedTypingState = nil
        updateSuggestions()
        view.setNeedsLayout()
    }

    @objc func clearEmojiSearch() {
        lastShift = .distantPast
        guard isSearchingEmoji else { return }
        emojiQuery = ""
        refreshEmojiSearch()
    }

    @objc func clearEmojiHistory() {
        dismissEmojiTones()
        browseResults.resetBrowsePosition()
        storage.clearEmojiUsage()
        if isShowingEmoji && !isSearchingEmoji { emojiResults.showBrowse(frequent: []) }
    }

    @objc private func deleteFromEmojiBrowse() {
        guard isShowingEmoji, !isSearchingEmoji else { return }
        type(KeyHit(key: "delete", point: .zero, frame: .zero))
    }

    private func refreshEmojiSearch() {
        dismissEmojiTones()
        emojiResults.showSearch(emojiQuery, frequent: storage.emojiUsage.ranked)
        emojiSearch.update(query: emojiQuery)
    }

    private func updateInputSurface() {
        if isSearchingEmoji {
            if plane.fieldKey != "," { plane.fieldKey = "," }
            plane.cursorMovementEnabled = false
            return
        }
        let surface = effectiveHostSurface
        if restoringEmojiHost, !isReturningSearchDocument, surface == observedHostSurface {
            restoringEmojiHost = false
            emojiHostSurface = nil
        }
        let field = surface.type ?? .default
        let key = field == .emailAddress ? "@" : field == .URL ? "/" : ","
        let document = surface.document
        if lastHostFieldType != field || plane.fieldKey != key || lastHostDocument != document {
            plane.cancelInteractions()
            dismissEmojiTones()
            lastHostFieldType = field
            lastHostDocument = document
            plane.fieldKey = key
        }
        plane.cursorMovementEnabled = !demoMode && !isSearchingEmoji
    }

    func showEmojiTones(for text: String) {
        guard isShowingEmoji, emojiResults.results.contains(where: { $0.text == text }) else { return }
        let variants = EmojiCatalog.toneVariants(for: text)
        guard variants.count > 1 else { return }
        plane.cancelInteractions()
        toneOrigin = text
        emojiTonePanel.show(variants)
        layoutEmojiTonePanel()
        view.bringSubviewToFront(emojiTonePanel)
        UIAccessibility.post(notification: .layoutChanged, argument: emojiTonePanel)
    }

    private func layoutEmojiTonePanel() {
        let region = plane.convert(plane.bounds, to: view)
        let top = isSearchingEmoji ? region.minY : emojiResults.convert(emojiResults.bounds, to: view).minY
        emojiTonePanel.frame = CGRect(x: region.minX, y: max(0, top), width: region.width,
                                     height: min(96, max(0, view.bounds.height - top)))
    }

    func dismissEmojiTones() {
        toneOrigin = nil
        emojiTonePanel.hide()
    }

    func selectEmojiTone(_ text: String) {
        guard isShowingEmoji, !emojiTonePanel.isHidden, let origin = toneOrigin,
              emojiResults.results.contains(where: { $0.text == origin }),
              EmojiCatalog.toneVariants(for: origin).contains(where: { $0.text == text }) else { return }
        insertSelectedEmoji(text)
    }

    func selectEmoji(_ text: String) {
        guard isShowingEmoji, emojiResults.results.contains(where: { $0.text == text }) else { return }
        insertSelectedEmoji(text)
    }

    private func insertSelectedEmoji(_ text: String) {
        dismissEmojiTones()
        let searched = isSearchingEmoji
        if searched { hideEmoji() }
        insert(text)
        storage.recordEmoji(text, at: now())
        invalidateEditingState()
        if searched { updateSuggestions() }
    }

    @objc func showSettings() {
        lastShift = .distantPast
        guard !isShowingSettings else { return }
        cancelSuggestionInteraction()
        plane.cancelDeletePress()
        clearDeletionActions()
        hideWordOptions()
        plane.cancelSymbolDrag()
        hideEmoji()
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        isShowingSettings = true
        settingsTitle.text = settingsMenuTitle
        neuralService.clear()
        neuralWords = []
        neuralContext = nil
        configureSettings()
        settingsPanel.resetConfirmation()
        settingsPanel.setContentOffset(.zero, animated: false)
        predictionStrip.isHidden = true
        settingsHeader.isHidden = false
        plane.isHidden = true
        settingsPanel.isHidden = false
        view.setNeedsLayout()
        UIAccessibility.post(notification: .screenChanged, argument: settingsButton)
    }

    @objc func hideSettings() {
        lastShift = .distantPast
        guard isShowingSettings else { return }
        if isShowingTouchDiagnostics {
            closeTouchDiagnostics()
            settingsPanel.isHidden = false
            return
        }
        plane.cancelPress()
        plane.cancelCursor()
        dismissEmojiTones()
        isShowingSettings = false
        predictionStrip.isHidden = false
        settingsHeader.isHidden = true
        settingsPanel.isHidden = true
        settingsPanel.resetConfirmation()
        plane.isHidden = false
        updateSuggestions()
        view.setNeedsLayout()
        UIAccessibility.post(notification: .screenChanged, argument: settingsButton)
    }
    @objc func showTouchDiagnostics() {
        lastShift = .distantPast
        guard isShowingSettings, !isShowingTouchDiagnostics else { return }
        diagnosticPage = plane.page
        plane.page = 0
        isShowingTouchDiagnostics = true
        settingsTitle.text = "Touch zones"
        settingsBackButton.accessibilityLabel = "Back to settings"
        settingsBackButton.isHidden = false
        settingsPanel.isHidden = true
        touchDiagnostics.isHidden = false
        touchDiagnostics.setContentOffset(.zero, animated: false)
        refreshTouchDiagnostics()
        view.setNeedsLayout()
        UIAccessibility.post(notification: .screenChanged, argument: touchDiagnostics)
    }
    private func refreshTouchDiagnostics() {
        touchDiagnostics.configure(profile: activeTouchProfile, model: plane.touchModel, plane: plane, learning: storage.usesPersonalization)
    }
    private func closeTouchDiagnostics() {
        isShowingTouchDiagnostics = false
        touchDiagnostics.isHidden = true
        settingsTitle.text = settingsMenuTitle
        settingsBackButton.accessibilityLabel = "Back to keyboard"
        settingsBackButton.isHidden = true
        if let diagnosticPage { plane.page = diagnosticPage }
        diagnosticPage = nil
    }

}
