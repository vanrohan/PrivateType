import UIKit

struct KeyHit {
    let key: String
    let point: CGPoint
    let frame: CGRect
    let physical: Bool
    let literal: Bool
    init(key: String, point: CGPoint, frame: CGRect, physical: Bool = true, literal: Bool = false) {
        self.key = key; self.point = point; self.frame = frame; self.physical = physical; self.literal = literal
    }
}

private final class AccessibleKey: UIAccessibilityElement {
    var action: (() -> Bool)?
    override func accessibilityActivate() -> Bool { action?() ?? false }
}

final class DeliberateTapButton: UIButton {
    var canActivate: () -> Bool = { true }
    private var origin: CGPoint?
    private(set) var validTap = false

    func cancelTap() {
        validTap = false
        isHighlighted = false
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        return beginTap(at: point) && super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        moveTap(to: touch.location(in: self))
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { moveTap(to: touch.location(in: self)) }
        else { cancelTap() }
        super.endTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        cancelTap()
        super.cancelTracking(with: event)
    }

    override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        guard canActivate(), event?.type != .touches || validTap else { return }
        super.sendAction(action, to: target, for: event)
    }

    func beginTap(at point: CGPoint) -> Bool {
        origin = point
        validTap = bounds.contains(point) && canActivate()
        return validTap
    }

    func moveTap(to point: CGPoint) {
        guard let origin, bounds.contains(point), canActivate(), hypot(point.x - origin.x, point.y - origin.y) <= 8 else {
            cancelTap()
            return
        }
    }
}

final class TouchBlockingStackView: UIStackView {
    var blocksTouches = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        blocksTouches ? nil : super.hitTest(point, with: event)
    }
}

final class KeyboardPlane: UIView {
    var language: KeyboardLanguage = .english { didSet { rebuild() } }
    var page = 0 { didSet { if page != oldValue { cancelPress(); cancelCursor(); cancelDeletePress() }; rebuild() } }
    var fieldKey = "," { didSet { if fieldKey != oldValue { cancelInteractions() }; rebuild() } }
    var cursorMovementEnabled = true {
        didSet { if !cursorMovementEnabled { cancelCursor() } }
    }
    var alternateTopInset: CGFloat = 0
    var onAlternatesChange: (([String], CGRect, Int?) -> Void)?
    var shifted = false { didSet { rebuild() } }
    var capsLocked = false { didSet { rebuild() } }
    var compact = false { didSet { setNeedsDisplay() } }
    var returnTitle = "return" { didSet { rebuild() } }
    var showsGlobe = true { didSet { rebuild() } }
    var numberRow = false { didSet { rebuild() } }
    var largerKeyLabels = false { didSet { setNeedsDisplay() } }
    var highContrast = false { didSet { setNeedsDisplay() } }
    var usesLargerLabels: Bool { largerKeyLabels || traitCollection.preferredContentSizeCategory.isAccessibilityCategory }
    var usesHighContrast: Bool { highContrast || traitCollection.accessibilityContrast == .high }
    var accessibilityInputEnabled = true
    private var accessibilityGeneration = 0
    private var accessibleLabels: [String] = []
    var cursorSpeed = CursorSpeed.standard
    let globeButton = UIButton(type: .system)
    var touchModel = TouchModel()
    var onKey: ((KeyHit) -> Void)?
    var onContactBegin: (() -> Void)?
    private var activeContacts = Set<ObjectIdentifier>()
    var hasActiveContact: Bool {
        !activeContacts.isEmpty || pressed != nil || pendingHit != nil || cursorOrigin != nil || deleteHit != nil || symbolOrigin != nil
    }
    func beginContact(_ identifier: ObjectIdentifier) {
        if activeContacts.insert(identifier).inserted { onContactBegin?() }
    }
    func endContact(_ identifier: ObjectIdentifier) { activeContacts.remove(identifier) }
    var onCursor: ((Int) -> Void)?
    var onGeometryChange: (() -> Void)?
    var onDeleteStart: (() -> Bool)?
    var onDeletePreview: ((Int) -> Void)?
    var onDeleteCommit: (() -> Void)?
    var onDeleteCancel: (() -> Void)?
    var onDeleteWord: (() -> Bool)?
    var onDeleteKey: ((KeyHit) -> Bool)?
    private var previousSize = CGSize.zero
    private(set) var keys: [(String, CGRect)] = []
    private var alternateTimer: Timer?
    private var alternateTouch: UITouch?
    private var pendingHit: KeyHit?
    private var pressPoint: CGPoint?
    private(set) var alternateOptions: [String] = []
    private(set) var alternateFrame = CGRect.zero
    private(set) var alternateIndex: Int?
    private var pressed: String?
    private var repeatTimer: Timer?
    private var cursorOrigin: CGPoint?
    private(set) var movingCursor = false
    private var spaceTouch: UITouch?
    private var deleteTouch: UITouch?
    private var deleteHit: KeyHit?
    private var deleteRepeated = false
    private var deleteDragging = false
    private var canDragDelete = false
    private var symbolTouch: UITouch?
    private var symbolOrigin: CGPoint?
    private var symbolMoved = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitAccessibilityContrast.self, UITraitPreferredContentSizeCategory.self,
                                UITraitUserInterfaceStyle.self]) { (plane: KeyboardPlane, _: UITraitCollection) in
            plane.setNeedsDisplay()
        }
        isMultipleTouchEnabled = true
        isAccessibilityElement = false
        backgroundColor = .clear
        accessibilityIdentifier = "keyPlane"
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = .label
        globeButton.accessibilityLabel = "Switch keyboard"
        addSubview(globeButton)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuild()
        if previousSize != bounds.size {
            previousSize = bounds.size
            cancelInteractions()
            onGeometryChange?()
        }
    }

    func refreshGeometry() { rebuild() }

    private func rebuild() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        var rows: [[String]]
        if page == 0 {
            rows = language == .english ? [Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init),
                ["shift"] + Array("zxcvbnm").map(String.init) + ["delete"]] :
                [Array("qwertzuiopü").map(String.init), Array("asdfghjklöä").map(String.init),
                 ["shift"] + Array("yxcvbnmß").map(String.init) + ["delete"]]
        } else if page == 1 {
            rows = [Array("1234567890").map(String.init), ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""],
                    ["more", ".", ",", "?", "!", "'", "delete"]]
        } else {
            rows = [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                    ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"],
                    ["more", ".", ",", "?", "!", "'", "delete"]]
        }
        if numberRow && page == 0 { rows.insert(Array("1234567890").map(String.init), at: 0) }
        let previousKeys = keys
        keys = []
        let height = bounds.height / CGFloat(rows.count + 1)
        for (rowIndex, row) in rows.enumerated() {
            let letterRow = rowIndex - (numberRow && page == 0 ? 1 : 0)
            let inset: CGFloat = page == 0 && letterRow == 1 && language == .english ? bounds.width / 20 : 0
            let weights: [CGFloat] = page == 0 && letterRow == 2 ?
                [1.5] + Array(repeating: 1, count: row.count - 2) + [1.5] : Array(repeating: 1, count: row.count)
            let unit = (bounds.width - inset * 2) / weights.reduce(0, +)
            var x = inset
            for (index, key) in row.enumerated() {
                let width = weights[index] * unit
                keys.append((key, CGRect(x: x, y: CGFloat(rowIndex) * height, width: width, height: height)))
                x += width
            }
        }
        let punctuation = page == 0 ? fieldKey : ","
        let bottom = ["page"] + (showsGlobe ? ["globe"] : []) + [punctuation, "space", ".", "return"]
        let scale = min(1, bounds.width / 320)
        let fixed: [String: CGFloat] = ["page": 44 * scale, "globe": 44 * scale,
                                       punctuation: 44 * scale, ".": 44 * scale, "return": 60 * scale]
        let fixedWidth = bottom.filter { $0 != "space" }.reduce(CGFloat(0)) { $0 + fixed[$1, default: 0] }
        let spaceWidth = bounds.width - fixedWidth
        var x: CGFloat = 0
        for key in bottom {
            let width = key == "space" ? spaceWidth : fixed[key, default: 44]
            keys.append((key, CGRect(x: x, y: height * CGFloat(rows.count), width: width, height: height)))
            x += width
        }
        globeButton.isHidden = !showsGlobe
        globeButton.frame = keys.first(where: { $0.0 == "globe" })?.1 ?? .zero
        let labels = keys.map { accessibilityTitle($0.0) }
        let sameGeometry = previousKeys.count == keys.count && zip(previousKeys, keys).allSatisfy {
            $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1
        }
        guard !sameGeometry || labels != accessibleLabels else { setNeedsDisplay(); return }
        accessibleLabels = labels
        accessibilityGeneration += 1
        let generation = accessibilityGeneration
        var elements: [Any] = []
        for (key, frame) in keys {
            if key == "globe" { elements.append(globeButton); continue }
            let element = AccessibleKey(accessibilityContainer: self)
            element.accessibilityLabel = accessibilityTitle(key)
            element.accessibilityTraits = .keyboardKey
            element.accessibilityFrameInContainerSpace = frame
            element.action = { [weak self] in
                guard let self, self.canActivateAccessibility(generation), let onKey = self.onKey else { return false }
                onKey(KeyHit(key: key, point: CGPoint(x: frame.midX, y: frame.midY), frame: frame, physical: false))
                return true
            }
            let options = AlternateCharacters.options(for: key, uppercase: shifted && page == 0)
            element.accessibilityHint = options.isEmpty ? nil : "Use Actions for alternate characters."
            element.accessibilityCustomActions = options.map { option in
                UIAccessibilityCustomAction(name: "Insert " + option) { [weak self] _ in
                    guard let self, self.canActivateAccessibility(generation), let onKey = self.onKey else { return false }
                    onKey(KeyHit(key: option, point: CGPoint(x: frame.midX, y: frame.midY), frame: frame, physical: false, literal: true))
                    return true
                }
            }
            if key == "delete" {
                element.accessibilityCustomActions?.append(UIAccessibilityCustomAction(name: "Delete word") { [weak self] _ in
                    guard let self, self.canActivateAccessibility(generation) else { return false }
                    return self.onDeleteWord?() ?? false
                })
            }
            elements.append(element)
        }
        accessibilityElements = elements
        setNeedsDisplay()
    }

    private func title(_ key: String) -> String {
        switch key {
        case "shift": return capsLocked ? "⇪" : "⇧"
        case "delete": return "⌫"
        case "page": return page == 0 ? "123" : "ABC"
        case "more": return page == 1 ? "#+=" : "123"
        case "space": return movingCursor ? "Move cursor" : "PrivateType"
        case "language": return language.badge
        case "globe": return ""
        case "return": return returnTitle
        default: return AlternateCharacters.cased(key, uppercase: shifted && page == 0)
        }
    }
    private func accessibilityTitle(_ key: String) -> String {
        switch key {
        case "shift": return capsLocked ? "Caps lock" : "Shift"
        case "delete": return "Delete"
        case "page": return page == 0 ? "Numbers" : "Letters"
        case "more": return "More symbols"
        case "space": return language == .english ? "space" : "Leerzeichen"
        case "language": return "Language: " + language.title + ". Switch language."
        default: return title(key)
        }
    }

    private func canActivateAccessibility(_ generation: Int) -> Bool {
        guard accessibilityInputEnabled, generation == accessibilityGeneration else { return false }
        var ancestor: UIView? = self
        while let current = ancestor {
            if current.isHidden || current.alpha < 0.01 || !current.isUserInteractionEnabled { return false }
            ancestor = current.superview
        }
        return true
    }

    func labelFont(for key: String, frame: CGRect) -> UIFont {
        let base: CGFloat = key == "space" ? (frame.width < 70 ? 10 : 12) : key == "return" ? 14 :
            key.count > 1 ? 17 : (compact || bounds.width < 320) ? 19 : 22
        let weight: UIFont.Weight = key == "space" ? .medium : .regular
        let text = title(key) as NSString
        func fitted(_ size: CGFloat) -> UIFont {
            var font = UIFont.systemFont(ofSize: size, weight: weight)
            for _ in 0..<4 {
                let width = text.size(withAttributes: [.font: font]).width
                let scale = min(1, max(0, frame.width - 2) / max(1, width), max(0, frame.height - 2) / font.lineHeight)
                if scale >= 1 { break }
                font = UIFont.systemFont(ofSize: max(1, font.pointSize * scale), weight: weight)
            }
            return font
        }
        let normal = fitted(base)
        guard usesLargerLabels else { return normal }
        let larger = fitted(base + (key.count == 1 ? 4 : 2))
        return larger.pointSize >= normal.pointSize ? larger : normal
    }

    func keyFill(for key: String) -> UIColor {
        if key == "space", movingCursor { return .label }
        if usesHighContrast {
            if pressed == key { return .label }
            return ["shift", "delete", "page", "more", "return", "globe", "language"].contains(key)
                ? .secondarySystemBackground : .systemBackground
        }
        let special = ["shift", "delete", "page", "more", "return", "globe", "language"].contains(key)
        return pressed == key ? .systemGray2 : special ? .tertiarySystemFill : .secondarySystemGroupedBackground
    }

    func keyForeground(for key: String) -> UIColor {
        if key == "space", movingCursor { return .systemBackground }
        if usesHighContrast { return pressed == key ? .systemBackground : .label }
        return key == "space" ? .secondaryLabel : .label
    }

    override func draw(_ rect: CGRect) {
        globeButton.tintColor = keyForeground(for: "globe")
        for (key, cell) in keys {
            let frame = cell.insetBy(dx: 2, dy: 2)
            keyFill(for: key).setFill()
            let path = UIBezierPath(roundedRect: frame, cornerRadius: 7)
            path.fill()
            if usesHighContrast {
                UIColor.label.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            if key == "return", returnTitle == "return",
               let symbol = UIImage(systemName: "return", withConfiguration:
                    UIImage.SymbolConfiguration(pointSize: usesLargerLabels ? 24 : 21, weight: .regular)) {
                let area = frame.insetBy(dx: 6, dy: 5)
                let scale = min(1, max(0, area.width) / symbol.size.width, max(0, area.height) / symbol.size.height)
                let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.withTintColor(keyForeground(for: key), renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                     width: size.width, height: size.height))
                continue
            }
            let font = labelFont(for: key, frame: frame)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (title(key) as NSString).draw(in: CGRect(x: frame.minX, y: frame.midY - font.lineHeight / 2,
                                                    width: frame.width, height: font.lineHeight),
                withAttributes: [.font: font, .foregroundColor: keyForeground(for: key), .paragraphStyle: style])
        }
        if onAlternatesChange == nil, !alternateOptions.isEmpty {
            AlternatePopupView.drawOptions(alternateOptions, selected: alternateIndex,
                                           in: alternateFrame, highContrast: usesHighContrast)
        }
    }

    func hit(at point: CGPoint) -> KeyHit? {
        guard bounds.contains(point) else { return nil }
        return resolvedKey(at: point).map { KeyHit(key: $0.0, point: point, frame: $0.1) }
    }

    func resolvedKey(at point: CGPoint, variant: TouchModel.Variant = .active) -> (String, CGRect)? {
        Self.resolvedKey(at: point, keys: keys, bounds: bounds, page: page, model: touchModel, variant: variant)
    }

    static func resolvedKey(at point: CGPoint, keys: [(String, CGRect)], bounds: CGRect, page: Int,
                            model: TouchModel, variant: TouchModel.Variant = .active) -> (String, CGRect)? {
        guard bounds.contains(point),
              let row = keys.first(where: { point.y >= $0.1.minY && point.y < $0.1.maxY })?.1 else { return nil }
        let rowKeys = keys.filter { $0.1.minY == row.minY }
        if let cell = rowKeys.first(where: { $0.1.contains(point) }),
           page != 0 || cell.0.count != 1 || cell.0.first?.isLetter != true { return cell }
        let letters = rowKeys.filter { $0.0.count == 1 && $0.0.first?.isLetter == true }
        return letters.min { lhs, rhs in
            func score(_ entry: (String, CGRect)) -> Double {
                let (key, rect) = entry
                let x = Double((point.x - rect.midX) / rect.width)
                let y = Double((point.y - rect.midY) / rect.height)
                return model.score(key: key, x: x, y: y, variant: page == 0 ? variant : .baseline)
            }
            return score(lhs) < score(rhs)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            beginContact(ObjectIdentifier(touch))
            let point = touch.location(in: self)
            guard let hit = hit(at: point) else { continue }
            if deleteHit != nil { endDeletePress() }
            pressed = hit.key
            if hit.key == "delete" {
                beginDeletePress(hit)
                deleteTouch = touch
                continue
            }
            if beginSymbolDrag(hit) {
                symbolTouch = touch
                continue
            }
            if hit.key == "space" {
                spaceTouch = touch
            }
            if let pendingHit { endPress(at: pressPoint ?? pendingHit.point) }
            if AlternateCharacters.options(for: hit.key).isEmpty {
                beginKey(hit)
            } else {
                alternateTouch = touch
                beginPress(hit)
            }
        }
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = deleteTouch, touches.contains(touch) { moveDeletePress(to: touch.location(in: self)) }
        if let touch = symbolTouch, touches.contains(touch) { moveSymbolDrag(to: touch.location(in: self)) }
        if let touch = alternateTouch, touches.contains(touch) { movePress(to: touch.location(in: self)) }
        if let touch = spaceTouch, touches.contains(touch) { moveSpace(to: touch.location(in: self)) }
    }

    func moveSpace(to point: CGPoint) {
        guard cursorMovementEnabled, let origin = cursorOrigin else { return }
        let step = CGFloat(cursorSpeed.pointsPerCharacter)
        let delta = Int((point.x - origin.x) / step)
        if delta != 0 {
            movingCursor = true
            setNeedsDisplay()
            cursorOrigin = CGPoint(x: origin.x + CGFloat(delta) * step, y: origin.y)
            onCursor?(delta)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { endContact(ObjectIdentifier(touch)) }
        if let touch = symbolTouch, touches.contains(touch) {
            endSymbolDrag(at: touch.location(in: self))
            symbolTouch = nil
        }
        if let touch = alternateTouch, touches.contains(touch) {
            endPress(at: touch.location(in: self))
            alternateTouch = nil
        }
        if let touch = deleteTouch, touches.contains(touch) {
            moveDeletePress(to: touch.location(in: self))
            endDeletePress()
        }
        if let touch = spaceTouch, touches.contains(touch) {
            endSpace(at: touch.location(in: self))
            spaceTouch = nil
        }
        pressed = nil
        setNeedsDisplay()
    }

    private func finishPendingInput() {
        if let pendingHit { endPress(at: pressPoint ?? pendingHit.point) }
        if let space = keys.first(where: { $0.0 == "space" })?.1 {
            endSpace(at: CGPoint(x: space.midX, y: space.midY))
        }
    }

    func beginDeletePress(_ hit: KeyHit) {
        finishPendingInput()
        cancelDeletePress()
        deleteHit = hit
        deleteRepeated = false
        deleteDragging = false
        canDragDelete = onDeleteStart?() ?? false
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.startDeleteRepeat()
        }
    }

    func startDeleteRepeat() {
        guard let hit = deleteHit, !deleteDragging else { return }
        repeatTimer?.invalidate()
        deleteRepeated = true
        onDeleteCancel?()
        guard emitDelete(hit), deleteHit != nil else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.deleteHit != nil else { return }
            if !self.emitDelete(hit) { self.cancelDeletePress() }
        }
    }

    func moveDeletePress(to point: CGPoint) {
        guard let hit = deleteHit, canDragDelete, !deleteRepeated else { return }
        let count = max(0, min(10, Int((hit.point.x - point.x) / 24)))
        if count > 0 { deleteDragging = true; repeatTimer?.invalidate() }
        if deleteDragging { onDeletePreview?(abs(point.y - hit.point.y) <= hit.frame.height ? count : 0) }
    }

    func endDeletePress() {
        guard let hit = deleteHit else { return }
        let dragging = deleteDragging
        let repeated = deleteRepeated
        resetDeletePress()
        if dragging { onDeleteCommit?() }
        else {
            onDeleteCancel?()
            if !repeated { _ = emitDelete(hit) }
        }
    }

    private func emitDelete(_ hit: KeyHit) -> Bool {
        if let onDeleteKey { return onDeleteKey(hit) }
        onKey?(hit)
        return true
    }

    func cancelDeletePress() {
        let active = deleteHit != nil
        resetDeletePress()
        if active { onDeleteCancel?() }
    }

    private func resetDeletePress() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        deleteHit = nil
        deleteTouch = nil
        deleteDragging = false
        deleteRepeated = false
        canDragDelete = false
    }

    @discardableResult
    func beginSymbolDrag(_ hit: KeyHit) -> Bool {
        guard hit.key == "page", page == 0 else { return false }
        finishPendingInput()
        cancelPress()
        symbolOrigin = hit.point
        symbolMoved = false
        onKey?(hit)
        return true
    }

    func moveSymbolDrag(to point: CGPoint) {
        guard let origin = symbolOrigin else { return }
        if hypot(point.x - origin.x, point.y - origin.y) > 10 { symbolMoved = true }
        pressed = symbolMoved ? hit(at: point)?.key : "page"
        setNeedsDisplay()
    }

    func endSymbolDrag(at point: CGPoint) {
        guard symbolOrigin != nil else { return }
        moveSymbolDrag(to: point)
        let moved = symbolMoved
        symbolOrigin = nil
        symbolMoved = false
        if moved {
            if let hit = hit(at: point), hit.key.count == 1 { onKey?(hit) }
            if page != 0 { onKey?(KeyHit(key: "page", point: .zero, frame: .zero, physical: false)) }
        }
        pressed = nil
        setNeedsDisplay()
    }

    func cancelSymbolDrag() {
        let active = symbolOrigin != nil
        symbolOrigin = nil
        symbolTouch = nil
        symbolMoved = false
        if active && page != 0 { onKey?(KeyHit(key: "page", point: .zero, frame: .zero, physical: false)) }
        pressed = nil
        setNeedsDisplay()
    }

    func beginPress(_ hit: KeyHit) {
        if deleteHit != nil { endDeletePress() }
        if let previous = pendingHit { endPress(at: pressPoint ?? previous.point) }
        cancelPress()
        // Commit a pending space before this key.
        if cursorOrigin != nil { endSpace(at: keys.first(where: { $0.0 == "space" }).map { CGPoint(x: $0.1.midX, y: $0.1.midY) } ?? hit.point) }
        pendingHit = hit
        pressPoint = hit.point
        alternateTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.showAlternates()
        }
    }

    func showAlternates() {
        guard let hit = pendingHit else { return }
        alternateOptions = AlternateCharacters.options(for: hit.key, uppercase: shifted && page == 0)
        guard !alternateOptions.isEmpty else { return }
        let width = min(bounds.width, CGFloat(alternateOptions.count) * 36)
        alternateFrame = CGRect(x: min(max(0, hit.frame.midX - width / 2), bounds.width - width),
                                y: max(-alternateTopInset, hit.frame.minY - 68), width: width, height: 44)
        if hit.key == "," || hit.key == "." {
            // Place the default alternate under the current touch.
            let point = pressPoint ?? hit.point
            let index = min(alternateOptions.count - 1,
                max(0, Int((point.x - alternateFrame.minX) / (width / CGFloat(alternateOptions.count)))))
            let preferred = alternateOptions.removeFirst()
            alternateOptions.insert(preferred, at: index)
        }
        movePress(to: pressPoint ?? hit.point)
    }

    func movePress(to point: CGPoint) {
        guard let hit = pendingHit else { return }
        pressPoint = point
        if alternateOptions.isEmpty {
            if !hit.frame.insetBy(dx: -10, dy: -10).contains(point) { cancelPress() }
        } else {
            let area = alternateFrame.union(hit.frame).insetBy(dx: -12, dy: -16)
            if !area.contains(point) { cancelPress(); return }
            alternateIndex = min(alternateOptions.count - 1,
                max(0, Int((point.x - alternateFrame.minX) / (alternateFrame.width / CGFloat(alternateOptions.count)))))
            updateAlternateDisplay()
        }
    }

    private func updateAlternateDisplay() {
        onAlternatesChange?(alternateOptions, alternateFrame, alternateIndex)
        setNeedsDisplay()
    }

    func endPress(at point: CGPoint) {
        guard let hit = pendingHit else { return }
        let selected: String?
        let literal = !alternateOptions.isEmpty
        if alternateOptions.isEmpty { selected = hit.frame.insetBy(dx: -10, dy: -10).contains(point) ? hit.key : nil }
        else {
            movePress(to: point)
            guard pendingHit != nil else { return }
            selected = alternateIndex.map { alternateOptions[$0] }
        }
        cancelPress()
        if let selected { beginKey(KeyHit(key: selected, point: hit.point, frame: hit.frame, physical: hit.physical, literal: literal)) }
    }

    func cancelPress() {
        alternateTimer?.invalidate()
        alternateTimer = nil
        pendingHit = nil
        pressPoint = nil
        alternateOptions = []
        alternateIndex = nil
        updateAlternateDisplay()
    }

    func beginKey(_ keyHit: KeyHit) {
        if deleteHit != nil { endDeletePress() }
        if keyHit.key == "space" {
            cursorOrigin = keyHit.point
            movingCursor = false
            return
        }
        if cursorOrigin != nil, !movingCursor, let frame = keys.first(where: { $0.0 == "space" })?.1 {
            onKey?(KeyHit(key: "space", point: CGPoint(x: frame.midX, y: frame.midY), frame: frame))
            cursorOrigin = nil
            spaceTouch = nil
        }
        onKey?(keyHit)
    }

    func endSpace(at point: CGPoint) {
        if cursorOrigin != nil, !movingCursor, let hit = hit(at: point), hit.key == "space" { onKey?(hit) }
        cancelCursor()
    }

    func cancelCursor() {
        cursorOrigin = nil
        movingCursor = false
        spaceTouch = nil
        setNeedsDisplay()
    }

    func cancelInteractions() {
        cancelPress()
        cancelCursor()
        cancelDeletePress()
        cancelSymbolDrag()
        alternateTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { endContact(ObjectIdentifier(touch)) }
        cancelDeletePress()
        cancelSymbolDrag()
        cancelPress()
        alternateTouch = nil
        repeatTimer?.invalidate()
        deleteTouch = nil
        spaceTouch = nil
        pressed = nil
        cancelCursor()
        setNeedsDisplay()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            activeContacts.removeAll()
            pressed = nil
            cancelCursor()
            cancelDeletePress()
            cancelSymbolDrag()
            cancelPress()
        }
    }

    func train(original: String, replacement: String, hits: [KeyHit]) {
        guard page == 0, original.count == hits.count else { return }
        for assignment in TouchAlignment.assignments(original: original, replacement: replacement) {
            let hit = hits[assignment.sourceIndex]
            guard hit.physical, let frame = keys.first(where: { $0.0 == assignment.intended })?.1,
                  hit.frame.width > 0, hit.frame.height > 0 else { continue }
            let point = hit.point
            let x = Double((point.x - frame.midX) / frame.width)
            let y = Double((point.y - frame.midY) / frame.height)
            guard x.isFinite, y.isFinite, abs(x) <= 1.5, abs(y) <= 1 else { continue }
            if touchModel.shouldValidateNext {
                touchModel.validate(baselineCorrect: resolvedKey(at: point, variant: .baseline)?.0 == assignment.intended,
                                    activeCorrect: resolvedKey(at: point)?.0 == assignment.intended,
                                    candidateCorrect: resolvedKey(at: point, variant: .candidate)?.0 == assignment.intended)
            } else {
                touchModel.learn(key: assignment.intended, x: x, y: y, observedKey: hit.key.lowercased())
            }
        }
    }
}


final class AlternatePopupView: UIView {
    var options: [String] = []
    var selected: Int?
    var highContrast = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 5
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ rect: CGRect) {
        Self.drawOptions(options, selected: selected, in: bounds, highContrast: highContrast)
    }

    static func drawOptions(_ options: [String], selected: Int?, in frame: CGRect, highContrast: Bool) {
        guard !options.isEmpty else { return }
        UIColor.secondarySystemBackground.setFill()
        let outline = UIBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 8)
        outline.fill()
        UIColor.label.setStroke()
        outline.lineWidth = highContrast ? 2 : 1
        outline.stroke()
        let width = frame.width / CGFloat(options.count)
        for (index, option) in options.enumerated() {
            let cell = CGRect(x: frame.minX + CGFloat(index) * width, y: frame.minY, width: width, height: frame.height)
            let active = selected == index
            if active {
                UIColor.label.setFill()
                UIBezierPath(roundedRect: cell.insetBy(dx: 2, dy: 3), cornerRadius: 6).fill()
            }
            let font = UIFont.systemFont(ofSize: active ? 27 : 23, weight: active ? .semibold : .regular)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (option as NSString).draw(in: CGRect(x: cell.minX, y: cell.midY - font.lineHeight / 2,
                                               width: cell.width, height: font.lineHeight),
                withAttributes: [.font: font, .paragraphStyle: style,
                                 .foregroundColor: active ? UIColor.systemBackground : UIColor.label])
        }
    }
}
