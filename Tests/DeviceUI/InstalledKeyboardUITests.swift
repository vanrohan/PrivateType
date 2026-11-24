import XCTest

final class InstalledKeyboardUITests: XCTestCase {

    private func fullyVisible(_ element: XCUIElement, in panel: XCUIElement) -> Bool {
        element.exists && element.isHittable && panel.frame.insetBy(dx: 0, dy: 4).contains(element.frame)
    }

    private func reveal(_ element: XCUIElement, in panel: XCUIElement) {
        for _ in 0..<24 {
            if fullyVisible(element, in: panel) { return }
            let direction: CGFloat = element.frame.midY < panel.frame.midY ? 1 : -1
            let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.55))
                .withOffset(CGVector(dx: 2, dy: 0))
            let end = start.withOffset(CGVector(dx: 0, dy: direction * min(50, panel.frame.height * 0.3)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func selectLayout(_ title: String, in app: XCUIApplication) {
        app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].tap()
        let panel = app.scrollViews["keyboardSettingsPanel"]
        let option = app.segmentedControls["Keyboard layout"].buttons[title]
        reveal(option, in: panel)
        option.tap()
        app.buttons["Back to keyboard"].tap()
    }

    private func setPrivateOn(_ app: XCUIApplication) throws {
        let panel = app.scrollViews["keyboardSettingsPanel"]
        let toggle = app.switches["Private typing"]
        reveal(toggle, in: panel)
        _ = try XCTUnwrap(fullyVisible(toggle, in: panel) ? toggle : nil,
                          "Private typing must fit inside the settings viewport.")
        let value = try XCTUnwrap(toggle.value as? String)
        _ = try XCTUnwrap(["0", "1"].contains(value) ? true : nil)
        if value == "0" { toggle.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        _ = try XCTUnwrap(XCTWaiter.wait(for: [enabled], timeout: 3) == .completed ? true : nil,
                          "Private typing must turn on before leaving settings.")
    }
    private func openKeyboard(withoutAutocorrection: Bool = false, urlField: Bool = false, emailField: Bool = false,
                              settingsGuide: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        if withoutAutocorrection { app.launchArguments = ["--test-no-autocorrection"] }
        if urlField { app.launchArguments.append("--test-url-field") }
        if emailField { app.launchArguments.append("--test-email-field") }
        app.launch()
        if settingsGuide {
            let guide = app.buttons["Keyboard settings"]
            for _ in 0..<4 where !guide.isHittable { app.swipeUp() }
            guide.tap()
        }
        let fieldID = settingsGuide ? "settingsTypingField" : "keyboardTestField"
        let field = app.descendants(matching: .any).matching(identifier: fieldID).firstMatch
        for _ in 0..<4 where !field.isHittable { app.swipeUp() }
        field.tap()
        let gear = app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"]
        if !gear.waitForExistence(timeout: 3) {
            let globes = [app.buttons["Next keyboard"], app.buttons["Switch keyboard"]]
            guard let globe = globes.first(where: { $0.waitForExistence(timeout: 2) }) else {
                XCTFail("No keyboard switch key. " + app.debugDescription)
                return app
            }
            globe.press(forDuration: 1)
            let name = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "PrivateType", "PrivateType,")
            let choice = app.buttons.matching(name).firstMatch
            if choice.waitForExistence(timeout: 2) { choice.tap() }
            else {
                let navigationBottom = app.navigationBars.firstMatch.frame.maxY
                guard let text = app.staticTexts.matching(name).allElementsBoundByIndex.first(where: {
                    $0.isHittable && $0.frame.minY > navigationBottom
                }) else {
                    XCTFail("PrivateType is absent from the keyboard switcher. " + app.debugDescription)
                    return app
                }
                text.tap()
            }
        }
        XCTAssertTrue(gear.waitForExistence(timeout: 5), app.debugDescription)
        return app
    }

    func testInstalledSuggestionPunctuationRemovesOnlyTheAutomaticSpace() {
        for punctuation in [".", "?"] {
            let app = openKeyboard()
            let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
            for letter in ["m", "o", "m"] {
                app.keys[app.keys[letter].exists ? letter : letter.uppercased()].tap()
            }
            let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Insert ")).firstMatch
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            let word = String(suggestion.label.dropFirst("Insert ".count))
            suggestion.tap()
            XCTAssertEqual(field.value as? String, word + " ")
            if punctuation == "?" { app.keys["Numbers"].tap() }
            app.keys[punctuation].tap()
            XCTAssertEqual(field.value as? String, word + punctuation)
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "Installed suggestion punctuation " + punctuation
            image.lifetime = .keepAlways
            add(image)
            app.terminate()
        }
    }

    func testInstalledPrivateWordDeletionRestoreSearchAndDismissal() throws {
        var app = openKeyboard()
        defer { app.terminate() }
        func enablePrivateTyping() throws -> String {
            app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].tap()
            let learning = try XCTUnwrap(app.switches["Local learning"].value as? String)
            _ = try XCTUnwrap(["0", "1"].contains(learning) ? learning : nil, "Learning must report an explicit state.")
            try setPrivateOn(app)
            app.buttons["Back to keyboard"].tap()
            let indicator = app.buttons["privateTypingIndicator"]
            let active = indicator.waitForExistence(timeout: 3) && indicator.isHittable
            _ = try XCTUnwrap(active ? indicator : nil, "Private typing must be active before sample input.")
            return learning
        }
        let learning = try enablePrivateTyping()
        for value in ["O", "n", "e", "space", "t", "w", "o", "space", "t", "h", "r", "e", "e", "space"] {
            let key = value == "space" && !app.keys["space"].exists ? "Leerzeichen" : value
            app.keys[key].tap()
        }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertEqual(field.value as? String, "One two three ")
        let delete = app.keys["Delete"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        delete.press(forDuration: 0.1, thenDragTo: delete.withOffset(CGVector(dx: -54, dy: 0)))
        XCTAssertEqual(field.value as? String, "One ")
        app.buttons["Restore deleted text"].tap()
        XCTAssertEqual(field.value as? String, "One two three ")
        app.buttons["searchEmoji"].tap()
        let search = app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch
        search.tap()
        for value in ["c", "a", "t"] { app.keys[value].tap() }
        XCTAssertEqual(search.value as? String, "cat")
        XCTAssertEqual(field.value as? String, "One two three ")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Installed private emoji search"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["privateTypingIndicator"].tap()
        XCTAssertFalse(app.buttons["privateTypingIndicator"].exists)
        XCTAssertEqual(search.value as? String, "cat")
        app.buttons["Browse emoji"].tap()
        app.buttons["Back to typing"].tap()
        XCTAssertEqual(try enablePrivateTyping(), learning)
        app.terminate()
        app = openKeyboard()
        XCTAssertFalse(app.buttons["privateTypingIndicator"].exists)
        app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].tap()
        XCTAssertEqual(app.switches["Local learning"].value as? String, learning)
    }

    func testInstalledCursorInsertionDoesNotKeepSentenceStartCapitalization() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        selectLayout("QWERTY", in: app)
        for value in ["H", "e", "l", "l", "o", "space", "w", "o", "r", "l", "d", ".", "space"] { app.keys[value].tap() }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertEqual(field.value as? String, "Hello world. ")
        XCTAssertTrue(app.keys["X"].exists)
        let space = app.keys["space"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        space.press(forDuration: 0.2, thenDragTo: space.withOffset(CGVector(dx: -87, dy: 0)))
        XCTAssertTrue(app.keys["x"].waitForExistence(timeout: 3), app.debugDescription)
        app.keys["x"].tap()
        XCTAssertEqual(field.value as? String, "Hello xworld. ")
        app.keys["Shift"].doubleTap()
        XCTAssertTrue(app.keys["Caps lock"].exists)
        app.keys["A"].tap()
        XCTAssertEqual(field.value as? String, "Hello xAworld. ")
        app.keys["Caps lock"].tap()
    }

    func testInstalledSharpSMenuAndGermanKeyUseUnicodeCharacters() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        selectLayout("QWERTY", in: app)
        if !app.keys["S"].exists { app.keys["Shift"].tap() }
        let plane = app.otherElements["keyPlane"]
        let letter = app.keys["S"]
        let width: CGFloat = 4 * 36
        let x = min(max(plane.frame.minX, letter.frame.midX - width / 2), plane.frame.maxX - width)
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: x + 0.5 * 36, dy: max(plane.frame.minY - 50, letter.frame.minY - 68) + 22))
        letter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: target)
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertEqual(field.value as? String, "\u{00df}")
        selectLayout("QWERTZ", in: app)
        app.keys["Shift"].tap()
        XCTAssertTrue(app.keys["\u{1e9e}"].exists)
        app.keys["\u{1e9e}"].tap()
        XCTAssertEqual(field.value as? String, "\u{00df}\u{1e9e}")
    }

    func testInstalledTouchDiagnosticsStaysInlineAndReturnsToTyping() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].tap()
        let button = app.buttons["Touch zones and statistics"]
        for _ in 0..<4 where !button.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        button.tap()
        XCTAssertTrue(app.staticTexts["Touch zones"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["Touch zone map"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["Back to settings"].tap()
        XCTAssertTrue(app.switches["Local learning"].exists)
        app.buttons["Back to keyboard"].tap()
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists)
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        app.keys[app.keys["A"].exists ? "A" : "a"].tap()
        XCTAssertFalse((field.value as? String ?? "").isEmpty)
    }

    func testInstalledBackspaceRepairUpdatesTouchStatistics() throws {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        func readSamples(returnToTyping: Bool = true) throws -> Int {
            app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].tap()
            let learning = app.switches["Local learning"]
            XCTAssertTrue(learning.waitForExistence(timeout: 3))
            guard learning.value as? String == "1" else { throw XCTSkip("Local learning is off.") }
            let button = app.buttons["Touch zones and statistics"]
            for _ in 0..<4 where !button.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
            button.tap()
            let label = app.staticTexts["touchStatistics"]
            XCTAssertTrue(label.waitForExistence(timeout: 3))
            let line = try XCTUnwrap(label.label.components(separatedBy: "\n").first { $0.hasPrefix("Confirmed samples: ") })
            let count = try XCTUnwrap(Int(line.replacingOccurrences(of: "Confirmed samples: ", with: "")))
            if returnToTyping {
                app.buttons["Back to settings"].tap()
                app.buttons["Back to keyboard"].tap()
            }
            return count
        }
        let before = try readSamples()
        app.keys[app.keys["G"].exists ? "G" : "g"].tap()
        app.keys["Delete"].tap()
        app.keys[app.keys["F"].exists ? "F" : "f"].tap()
        app.keys[app.keys["space"].exists ? "space" : "Leerzeichen"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertEqual((field.value as? String)?.lowercased(), "f ")
        XCTAssertEqual(try readSamples(returnToTyping: false), before + 1)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Confirmed touch repair"
        image.lifetime = .keepAlways
        add(image)
    }

    func testInstalledMultilingualWordsAndAfrikaansSuggestionWorkOnBothLayouts() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        selectLayout("QWERTY", in: app)
        var expected = ""
        for layout in 0..<2 {
            if layout == 1 { selectLayout("QWERTZ", in: app) }
            for word in ["dag", "dankie", "morgen"] {
                let first = String(word.prefix(1)).uppercased()
                if app.keys[first].exists { app.keys["Shift"].tap() }
                for character in word { app.keys[String(character)].tap() }
                app.keys[app.keys["space"].exists ? "space" : "Leerzeichen"].tap()
                expected += word + " "
                XCTAssertEqual(field.value as? String, expected)
            }
        }
        for character in "danki" { app.keys[String(character)].tap() }
        let suggestion = app.buttons["Insert dankie"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), app.debugDescription)
        suggestion.tap()
        XCTAssertEqual(field.value as? String, expected + "dankie ")
    }

    func testInstalledEmojiSearchReleasesFocusWhenHostIsTapped() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        app.keys[app.keys["A"].exists ? "A" : "a"].tap()
        app.keys["b"].tap()
        app.keys["c"].tap()
        let original = field.value as? String ?? ""
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["c", "a", "t"] { app.keys[value].tap() }
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "cat")
        XCTAssertEqual(field.value as? String, original)
        field.tap()
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].waitForExistence(timeout: 3), app.debugDescription)
        if app.keys["X"].exists { app.keys["Shift"].tap() }
        app.keys["x"].tap()
        XCTAssertEqual(field.value as? String, original + "x")
    }

    func testInstalledEmptyEmojiSearchReleasesFocusWhenHostIsTapped() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        field.tap()
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].waitForExistence(timeout: 3), app.debugDescription)
        if app.keys["X"].exists { app.keys["Shift"].tap() }
        app.keys["x"].tap()
        XCTAssertEqual(field.value as? String, "x")
    }

    func testInstalledEmojiSearchKeepsQueryOutOfHostAndShowsFrequentlyUsed() {
        let app = openKeyboard()
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        let before = field.value as? String
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["c", "a", "t"] { app.keys[value].tap() }
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "cat")
        XCTAssertEqual(field.value as? String, before)
        let cat = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert cat face")).firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 3))
        cat.tap()
        XCTAssertEqual(field.value as? String, "\u{1F431}")
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists)
        app.buttons["searchEmoji"].tap()
        XCTAssertTrue(app.staticTexts["Frequently Used"].exists)
        app.buttons["Delete last character"].tap()
        XCTAssertEqual(field.value as? String, before)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Installed emoji grid"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Back to typing"].tap()
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists)
    }

    func testInstalledEmojiHeaderFitsSafeAreasAndDeletesFromHost() {
        let app = openKeyboard()
        defer { XCUIDevice.shared.orientation = .portrait }
        guard app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].exists else { return }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        let before = field.value as? String
        app.keys[app.keys["A"].exists ? "A" : "a"].tap()
        XCTAssertNotEqual(field.value as? String, before)
        app.buttons["searchEmoji"].tap()
        let delete = app.buttons["Delete last character"]
        delete.tap()
        XCTAssertEqual(field.value as? String, before)
        let grid = app.collectionViews["emojiResults"]
        let abc = app.buttons["Back to typing"]
        let search = app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch
        for landscape in [false, true] {
            if landscape {
                XCUIDevice.shared.orientation = .landscapeLeft
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            }
            XCTAssertEqual(delete.frame.width, 44, accuracy: 1)
            XCTAssertEqual(delete.frame.height, 44, accuracy: 1)
            XCTAssertEqual(abc.frame.minX - delete.frame.maxX, 4, accuracy: 1)
            XCTAssertEqual(delete.frame.maxX, grid.frame.maxX - 48, accuracy: 1)
            XCTAssertEqual(delete.frame.minX - search.frame.maxX, 4, accuracy: 1)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(abc.frame.minX, window.minX + (landscape ? 44 : 8))
            XCTAssertLessThanOrEqual(delete.frame.maxX, window.maxX - (landscape ? 44 : 8))
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = landscape ? "Installed emoji margins landscape" : "Installed emoji margins portrait"
            image.lifetime = .keepAlways
            add(image)
        }
    }

    func testInstalledKeyboardSettingsStaysInTheExtension() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = openKeyboard(settingsGuide: true)
        XCTAssertTrue(app.navigationBars["Keyboard settings"].exists)
        let gear = app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"]
        guard gear.exists else { return }
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        if keyboard.exists { XCTAssertEqual(keyboard.frame.height, 244, accuracy: 1) }
        for _ in 0..<3 {
            gear.tap()
            XCTAssertTrue(app.switches["Neural predictions"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.alerts.count, 0)
            app.buttons["Back to keyboard"].tap()
            XCTAssertTrue(gear.waitForExistence(timeout: 3))
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        gear.tap()
        let back = app.buttons["Back to keyboard"]
        let toggle = app.switches["Neural predictions"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if keyboard.exists { XCTAssertEqual(keyboard.frame.height, 196, accuracy: 1) }
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height)
        XCTAssertGreaterThanOrEqual(back.frame.minX, window.minX + 44)
        XCTAssertLessThanOrEqual(toggle.frame.maxX, window.maxX - 44)
        back.tap()
        XCTAssertTrue(gear.waitForExistence(timeout: 3))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Installed PrivateType keyboard"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testEnglishSuggestionsWorkWhenTheHostDisablesAutocorrection() {
        checkEnglishSuggestions(urlField: false)
    }

    func testURLFieldAllowsManualSearchSuggestions() {
        checkEnglishSuggestions(urlField: true)
    }

    func testURLSuffixSuggestionInsertsAnAddressWithoutASpace() {
        let app = openKeyboard(urlField: true)
        selectLayout("QWERTY", in: app)
        if app.keys["E"].exists { app.keys["Shift"].tap() }
        for key in ["e", "x", "a", "m", "p", "l", "e", ".", "d"] { app.keys[key].tap() }
        let suggestion = app.buttons["Insert example.de"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), app.debugDescription)
        suggestion.tap()
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertEqual(field.value as? String, "example.de")
    }

    private func checkEnglishSuggestions(urlField: Bool) {
        let app = openKeyboard(withoutAutocorrection: true, urlField: urlField)
        selectLayout("QWERTY", in: app)
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        if app.keys["W"].exists { app.keys["Shift"].tap() }
        for key in ["w", "e", "space"] { app.keys[key].tap() }
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Insert ")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), app.debugDescription)
        guard suggestion.exists else { return }
        let selected = String(suggestion.label.dropFirst("Insert ".count))
        XCTAssertFalse(selected.isEmpty)
        suggestion.tap()
        XCTAssertEqual(field.value as? String, "we " + selected + " ")
        for key in ["t", "e", "h", "space"] { app.keys[key].tap() }
        XCTAssertEqual(field.value as? String, "we " + selected + " teh ")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "English suggestions with host correction off"
        image.lifetime = .keepAlways
        add(image)
    }
    func testSafariEmojiQueryStaysInsideTheKeyboard() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        guard app.state != .unknown else { throw XCTSkip("Safari app state is unavailable.") }
        app.activate()
        func nativeControls(_ query: XCUIElementQuery) -> [XCUIElement] {
            let webFrames = app.webViews.allElementsBoundByIndex.map(\.frame)
            return query.allElementsBoundByIndex.filter { element in
                let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                return element.isHittable && !webFrames.contains { $0.contains(center) }
            }
        }
        let addressNames = NSPredicate(format: "identifier IN %@ OR label IN %@",
                                       ["URL", "Address and Search"], ["URL", "Address and Search"])
        let cancelNames = NSPredicate(format: "identifier == %@ OR label == %@", "Cancel", "Cancel")
        guard nativeControls(app.buttons.matching(cancelNames)).isEmpty else {
            throw XCTSkip("Safari already has an editing session.")
        }
        let fields = nativeControls(app.textFields.matching(addressNames))
        guard fields.count == 1, let field = fields.first else {
            throw XCTSkip("Safari has no unique ready native address field.")
        }
        field.tap()
        let cancelControls = nativeControls(app.buttons.matching(cancelNames))
        guard cancelControls.count == 1, let cancel = cancelControls.first else {
            throw XCTSkip("Safari has no unique native Cancel control.")
        }
        defer { if cancel.isHittable { cancel.tap() } }
        try checkHostEmojiIsolation(app: app, field: field)
    }

    func testMessagesEmojiQueryStaysInsideTheKeyboard() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        guard app.state != .unknown else { throw XCTSkip("Messages app state is unavailable.") }
        app.activate()
        guard app.textViews.count == 0 else { throw XCTSkip("Messages has an existing editor.") }
        let compose = app.buttons["Compose"]
        guard compose.waitForExistence(timeout: 3), compose.isHittable else {
            throw XCTSkip("Messages has no ready conversation list.")
        }
        compose.tap()
        let field = app.textViews.firstMatch
        guard field.waitForExistence(timeout: 3), field.isHittable,
              let value = field.value as? String, value.isEmpty else {
            throw XCTSkip("Messages has no confirmed empty body field without a recipient.")
        }
        defer { if app.buttons["Cancel"].isHittable { app.buttons["Cancel"].tap() } }
        field.tap()
        try checkHostEmojiIsolation(app: app, field: field)
    }

    func testNotesEmojiQueryStaysInsideTheKeyboard() throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        guard app.state != .unknown else { throw XCTSkip("Notes app state is unavailable.") }
        app.activate()
        guard app.textViews.count == 0 else { throw XCTSkip("Notes has an existing editor.") }
        let create = app.buttons["New note"]
        guard create.waitForExistence(timeout: 3), create.isHittable else {
            throw XCTSkip("Notes has no ready note list.")
        }
        create.tap()
        let back = app.navigationBars.buttons.firstMatch
        let field = app.textViews.firstMatch
        guard field.waitForExistence(timeout: 3), field.isHittable,
              let value = field.value as? String, value.isEmpty,
              back.isHittable else { throw XCTSkip("Notes has no confirmed safe empty editor.") }
        defer { if back.isHittable { back.tap() } }
        field.tap()
        try checkHostEmojiIsolation(app: app, field: field)
    }

    private func checkHostEmojiIsolation(app: XCUIApplication, field: XCUIElement) throws {
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let gear = keyboard.buttons["Keyboard settings"]
        if !gear.waitForExistence(timeout: 2) {
            let globes = [app.buttons["Next keyboard"], app.buttons["Switch keyboard"]]
            guard let globe = globes.first(where: { $0.exists && $0.isHittable }) else {
                throw XCTSkip("The host has no keyboard switch key.")
            }
            globe.press(forDuration: 1)
            let name = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "PrivateType", "PrivateType,")
            let choice = app.buttons.matching(name).firstMatch
            guard choice.waitForExistence(timeout: 2) else {
                throw XCTSkip("PrivateType is not available in the host keyboard switcher.")
            }
            choice.tap()
        }
        guard gear.waitForExistence(timeout: 3) else { throw XCTSkip("PrivateType is not ready in this host.") }
        gear.tap()
        try setPrivateOn(app)
        app.buttons["Back to keyboard"].tap()
        _ = try XCTUnwrap(keyboard.buttons["privateTypingIndicator"].waitForExistence(timeout: 3) ? true : nil,
                          "Private typing must be active before a query.")
        let original = try XCTUnwrap(field.value as? String, "The host value must be readable before the query.")
        app.buttons["searchEmoji"].tap()
        let search = app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch
        search.tap()
        for key in ["k", "a", "t"] { app.keys[key].tap() }
        XCTAssertTrue(search.value as? String == "kat", "The keyboard must keep its query.")
        let after = try XCTUnwrap(field.value as? String, "The host value must be readable after the query.")
        XCTAssertTrue(after == original, "The host field must stay unchanged.")
        XCTAssertTrue(app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert cat face")).firstMatch.exists)
        app.buttons["Browse emoji"].tap()
        app.buttons["Back to typing"].tap()
    }

    func testInstalledAccessibilityOptionsPreservePrivateCorrectionAndGeometry() throws {
        let app = openKeyboard()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let gear = keyboard.buttons["Keyboard settings"]
        _ = try XCTUnwrap(gear.waitForExistence(timeout: 3) ? gear : nil)
        let originalFrame = keyboard.frame
        gear.tap()
        let panel = app.scrollViews["keyboardSettingsPanel"]
        try setPrivateOn(app)
        var originalOptions: [(String, String)] = []
        defer {
            if app.state == .runningForeground, keyboard.exists {
                if gear.isHittable { gear.tap() }
                let first = app.switches["Neural predictions"]
                reveal(first, in: panel)
                for (name, value) in originalOptions {
                    let toggle = app.switches[name]
                    reveal(toggle, in: panel)
                    XCTAssertTrue(fullyVisible(toggle, in: panel), "The original option must be reachable during cleanup.")
                    if fullyVisible(toggle, in: panel), toggle.value as? String != value { toggle.tap() }
                    XCTAssertEqual(toggle.value as? String, value)
                }
                if app.buttons["Back to keyboard"].isHittable { app.buttons["Back to keyboard"].tap() }
            }
            app.terminate()
        }
        for name in ["Larger key labels", "High contrast"] {
            let toggle = app.switches[name]
            reveal(toggle, in: panel)
            let value = try XCTUnwrap(toggle.value as? String)
            _ = try XCTUnwrap(["0", "1"].contains(value) && fullyVisible(toggle, in: panel) ? true : nil)
            originalOptions.append((name, value))
            if value == "0" { toggle.tap() }
        }
        app.buttons["Back to keyboard"].tap()
        _ = try XCTUnwrap(keyboard.buttons["privateTypingIndicator"].waitForExistence(timeout: 3) ? true : nil,
                          "Private typing must be active before sample input.")
        XCTAssertEqual(keyboard.frame, originalFrame)
        for value in ["S", "e", "n", "d", "space", "t", "e", "h", "space"] {
            let key = value == "space" && !app.keys["space"].exists ? "Leerzeichen" : value
            app.keys[key].tap()
        }
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertEqual(field.value as? String, "Send the ")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Installed high contrast correction"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Undo correction"].tap()
        XCTAssertEqual(field.value as? String, "Send teh")
        XCTAssertTrue(keyboard.buttons["privateTypingIndicator"].exists)
        XCTAssertEqual(keyboard.frame, originalFrame)
    }

    func testInstalledKeyboardPresentationAfterPreviewDismissal() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        func capture(_ name: String) {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = name + " hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        capture("Installed keyboard before preview")
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        app.buttons["Try the demo"].tap()
        XCTAssertTrue(app.staticTexts["Keyboard preview"].waitForExistence(timeout: 5))
        app.buttons["Close preview"].tap()
        field.tap()
        let gear = keyboard.buttons["Keyboard settings"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            keyboard.exists && !keyboard.frame.isEmpty && gear.exists && gear.isHittable && app.windows.firstMatch.frame.contains(keyboard.frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        capture("Installed keyboard after preview")
        XCTAssertTrue(gear.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(keyboard.frame))
    }

    func testInstalledRaisedPopupFieldKeysAndGroupedEmojiTones() throws {
        for email in [true, false] {
            let app = openKeyboard(urlField: !email, emailField: email)
            defer { app.terminate() }
            let keyboard = app.otherElements["simpleKeysKeyboard"]
            keyboard.buttons["Keyboard settings"].tap()
            try setPrivateOn(app)
            app.buttons["Back to keyboard"].tap()
            let plane = app.otherElements["keyPlane"]
            let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
            let punctuation = app.keys[email ? "@" : "/"]
            XCTAssertTrue(punctuation.waitForExistence(timeout: 3))
            punctuation.tap()
            XCTAssertEqual(field.value as? String, email ? "@" : "/")
            let letter = app.keys[app.keys["e"].exists ? "e" : "E"]
            let width: CGFloat = 252
            let x = min(max(plane.frame.minX, letter.frame.midX - width / 2), plane.frame.maxX - width)
            let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: x + 90, dy: max(plane.frame.minY - 50, letter.frame.minY - 68) + 22))
            letter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: target)
            XCTAssertEqual(field.value as? String, (email ? "@" : "/") + "\u{00ea}")
            keyboard.buttons["searchEmoji"].tap()
            app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
            for value in ["t", "h", "u", "m", "b", "s"] { app.keys[value].tap() }
            XCTAssertTrue(app.keys[","].exists)
            let result = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert thumbs up sign")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 3))
            let before = field.value as? String
            result.press(forDuration: 0.6)
            let cancel = app.buttons["Cancel skin tone selection"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 3))
            XCTAssertEqual(field.value as? String, before)
            let panel = app.otherElements["emojiTonePanel"]
            let variant = try XCTUnwrap(panel.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "dark skin tone")).allElementsBoundByIndex.last)
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "Installed tone picker " + (email ? "email" : "URL")
            image.lifetime = .keepAlways
            add(image)
            variant.tap()
            XCTAssertEqual(field.value as? String, (before ?? "") + "\u{1F44D}\u{1F3FF}")
            XCTAssertTrue(app.keys[email ? "@" : "/"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["privateTypingIndicator"].exists)
            app.terminate()
        }
    }

    func testInstalledLongPressUSelectsAnAlternateAtTheSourceKey() throws {
        let app = openKeyboard(withoutAutocorrection: true)
        defer { app.terminate() }
        app.otherElements["simpleKeysKeyboard"].buttons["Keyboard settings"].tap()
        try setPrivateOn(app)
        app.buttons["Back to keyboard"].tap()
        if !app.keys["u"].exists { app.keys["Shift"].tap() }
        let u = app.keys["u"]
        XCTAssertTrue(u.waitForExistence(timeout: 3))
        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        u.tap()
        XCTAssertEqual(field.value as? String, "u")
        u.press(forDuration: 0.6)
        XCTAssertEqual(field.value as? String, "u\u{00fb}")
        let gap = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: u.frame.midX, dy: u.frame.minY - 2))
        u.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: gap)
        XCTAssertEqual(field.value as? String, "u\u{00fb}\u{00fb}")
    }

}
