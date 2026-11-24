import UIKit

final class EmojiSearchControl: UIView, UITextFieldDelegate {
    var onActivate: (() -> Void)?
    var onClear: (() -> Void)?
    var onChange: ((String) -> Void)?
    var onFocusLost: (() -> Void)?
    private let field = UISearchTextField()
    private let clear = UIButton(type: .system)
    private let surface = UIView()
    private var clearWidth: NSLayoutConstraint?
    private(set) var query = ""
    var hasFocus: Bool { field.isFirstResponder }

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.backgroundColor = .tertiarySystemFill
        surface.layer.cornerRadius = 10
        surface.isUserInteractionEnabled = false
        accessibilityIdentifier = "emojiSearchContainer"
        isAccessibilityElement = false
        field.placeholder = "Search emoji"
        field.accessibilityIdentifier = "emojiSearchField"
        field.accessibilityLabel = "Search emoji"
        field.accessibilityHint = "Type to find an emoji. Tap the message field to resume typing."
        field.font = .systemFont(ofSize: 16)
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.clearButtonMode = .never
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .done
        // The existing letter keys edit this field.
        field.inputView = UIView(frame: .zero)
        field.delegate = self
        field.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        clear.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clear.tintColor = .secondaryLabel
        clear.accessibilityLabel = "Clear emoji search"
        clear.addTarget(self, action: #selector(clearQuery), for: .touchUpInside)
        for child in [surface, field, clear] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
        let clearWidth = clear.widthAnchor.constraint(equalToConstant: 0)
        self.clearWidth = clearWidth
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor, constant: 4), surface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 4), field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            field.trailingAnchor.constraint(equalTo: clear.leadingAnchor),
            clear.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), clearWidth,
            clear.topAnchor.constraint(equalTo: topAnchor), clear.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(activateSearch))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        update(query: "")
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func applyContrast(_ enabled: Bool) {
        clear.tintColor = enabled ? .label : .secondaryLabel
    }

    func matchesInput(before: String?, after: String?, selection: String?) -> Bool {
        guard let selected = field.selectedTextRange,
              let leading = field.textRange(from: field.beginningOfDocument, to: selected.start),
              let trailing = field.textRange(from: selected.end, to: field.endOfDocument) else { return false }
        let selectedText = selected.isEmpty ? nil : field.text(in: selected)
        return (before ?? "") == (field.text(in: leading) ?? "") &&
            (after ?? "") == (field.text(in: trailing) ?? "") && (selection ?? "") == (selectedText ?? "")
    }

    func focus() { field.becomeFirstResponder(); updateFocus() }
    func finishEditing() { field.resignFirstResponder(); updateFocus() }
    func insert(_ text: String) {
        let selected = field.selectedTextRange.flatMap { field.text(in: $0) } ?? ""
        guard (field.text ?? "").count - selected.count + text.count <= 64 else { return }
        field.insertText(text)
        queryChanged()
    }
    func deleteBackward() { field.deleteBackward(); queryChanged() }

    func update(query: String) {
        self.query = query
        if field.text != query { field.text = query }
        clear.isHidden = query.isEmpty
        clearWidth?.constant = query.isEmpty ? 0 : 44
        accessibilityValue = query.isEmpty ? "Empty" : query
        field.accessibilityValue = accessibilityValue
    }
    private func updateFocus() {
        surface.layer.borderWidth = hasFocus ? 1.5 : 0
        surface.layer.borderColor = tintColor.cgColor
    }
    @objc private func queryChanged() {
        let value = field.text ?? ""
        guard value != query else { return }
        update(query: value)
        onChange?(value)
    }
    @objc private func clearQuery() { onClear?(); focus() }
    @objc private func activateSearch() { if !hasFocus { focus() } }
    func textFieldDidBeginEditing(_ textField: UITextField) { updateFocus(); onActivate?() }
    func textFieldDidEndEditing(_ textField: UITextField) { updateFocus(); onFocusLost?() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { finishEditing(); return false }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let span = Range(range, in: textField.text ?? "") else { return false }
        return (textField.text ?? "").replacingCharacters(in: span, with: string).count <= 64
    }
    override func accessibilityActivate() -> Bool { onActivate?(); focus(); return true }
}
