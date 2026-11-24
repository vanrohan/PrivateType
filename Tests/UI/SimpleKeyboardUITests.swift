import XCTest

final class SimpleKeyboardUITests: XCTestCase {

    func testFourShortSuggestionsStayVisibleAndTheFourthInsertsItsWord() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let choices = keyboard.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Insert "))
        let four = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            choices.allElementsBoundByIndex.filter(\.isHittable).count == 4
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [four], timeout: 5), .completed)
        let visible = choices.allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visible.count, 4)
        XCTAssertTrue(visible.allSatisfy { $0.frame.width >= 44 })
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Four short suggestions"
        image.lifetime = .keepAlways
        add(image)
        guard let fourth = visible.last else {
            XCTFail("The fourth suggestion must exist.")
            return
        }
        let word = String(fourth.label.dropFirst("Insert ".count))
        fourth.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, word + " ")
    }

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
    private func preview(landscape: Bool = false, largestText: Bool = false, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if largestText { app.launchArguments.append("--test-accessibility-text") }
        if largestText || dark { app.launchArguments.append("--test-dark-appearance") }
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        app.launch()
        XCTAssertTrue(app.navigationBars["PrivateType"].waitForExistence(timeout: 5))
        let button = app.buttons["Try the demo"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where !button.isHittable {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        button.tap()
        XCTAssertTrue(app.staticTexts["Keyboard preview"].waitForExistence(timeout: 5))
        return app
    }

    private func selectLayout(_ title: String, in app: XCUIApplication) {
        app.otherElements["simpleKeysKeyboard"].buttons["Preview settings"].tap()
        let panel = app.scrollViews["keyboardSettingsPanel"]
        let option = app.segmentedControls["Keyboard layout"].buttons[title]
        reveal(option, in: panel)
        option.tap()
        app.buttons["Back to keyboard"].tap()
    }

    func testFinnishPreferencePersistsWithoutChangingQwertzLayout() {
        let app = preview()
        selectLayout("QWERTZ", in: app)
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        keyboard.buttons["Preview settings"].tap()
        let panel = app.scrollViews["keyboardSettingsPanel"]
        let preference = app.buttons["preferredLanguageButton"]
        reveal(preference, in: panel)
        preference.tap()
        let finnish = app.buttons["preferredLanguage.finnish"]
        reveal(finnish, in: panel)
        finnish.tap()
        XCTAssertEqual(preference.label, "Preferred language: Finnish")
        app.buttons["Back to keyboard"].tap()
        keyboard.buttons["Preview settings"].tap()
        XCTAssertTrue(app.segmentedControls["Keyboard layout"].buttons["QWERTZ"].isSelected)
        reveal(preference, in: panel)
        XCTAssertEqual(preference.label, "Preferred language: Finnish")
        app.buttons["Back to keyboard"].tap()
        for value in ["K", "i", "i", "t", "o", "s", "Leerzeichen"] { app.keys[value].tap() }
        XCTAssertEqual(app.staticTexts["previewText"].label, "Kiitos ")
    }

    func testHomeAndAboutShowLanguageScope() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["Prediction and correction. On your device."].exists)
        XCTAssertFalse(app.staticTexts["English, Afrikaans, German"].exists)
        let about = app.buttons["About"]
        let list = app.collectionViews.firstMatch
        reveal(about, in: list)
        about.tap()
        XCTAssertTrue(app.staticTexts["Supported languages use word tables and phrase predictions."].exists)
        let finnish = app.staticTexts["Finnish"]
        for _ in 0..<8 where !(finnish.exists && finnish.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(finnish.isHittable)
    }

    func testHeaderButtonsStaySeparateFromLettersAndAcceptDeliberateTaps() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let plane = app.otherElements["keyPlane"]
        let emoji = keyboard.buttons["searchEmoji"]
        let gear = keyboard.buttons["keyboardSettingsToggle"]
        XCTAssertEqual(gear.frame.minX, plane.frame.minX + 6, accuracy: 1)
        XCTAssertEqual(emoji.frame.maxX, plane.frame.maxX - 6, accuracy: 1)
        for button in [emoji, gear] {
            XCTAssertEqual(button.frame.width, 44, accuracy: 1)
            XCTAssertEqual(button.frame.height, 44, accuracy: 1)
            XCTAssertEqual(plane.frame.minY - button.frame.maxY, 8, accuracy: 1)
            let center = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let gap = center.withOffset(CGVector(dx: 0, dy: 26))
            gap.tap()
            XCTAssertTrue(app.keys["Numbers"].exists)
            let letter = center.withOffset(CGVector(dx: 0, dy: 42))
            letter.press(forDuration: 0.05, thenDragTo: center)
            XCTAssertTrue(app.keys["Numbers"].exists)
            center.press(forDuration: 0.05, thenDragTo: letter)
            XCTAssertTrue(app.keys["Numbers"].exists)
        }
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Separated header buttons"
        image.lifetime = .keepAlways
        add(image)
        emoji.tap()
        XCTAssertTrue(app.staticTexts["Popular"].exists)
        app.buttons["Back to typing"].tap()
        gear.tap()
        XCTAssertTrue(app.scrollViews["keyboardSettingsPanel"].exists)
        app.buttons["Back to keyboard"].tap()
        XCTAssertTrue(app.keys["Numbers"].exists)
    }

    func testPrivateTypingStaysVisibleThroughCorrectionRestoreAndEmojiSearch() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        func enablePrivateTyping() {
            keyboard.buttons["Preview settings"].tap()
            let toggle = app.switches["Private typing"]
            for _ in 0..<3 where !toggle.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
            toggle.tap()
            XCTAssertFalse(app.switches["Local learning"].isEnabled)
            app.buttons["Back to keyboard"].tap()
        }
        enablePrivateTyping()
        let indicator = keyboard.buttons["privateTypingIndicator"]
        XCTAssertEqual(indicator.label, "End private typing")
        XCTAssertEqual(indicator.value as? String, "On")
        XCTAssertTrue(indicator.isHittable)
        for value in ["S", "e", "n", "d", "space", "t", "e", "h", "space"] { app.keys[value].tap() }
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send the ")
        XCTAssertTrue(indicator.isHittable)
        XCTAssertTrue(app.buttons["Undo correction"].isHittable)
        let correction = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        correction.name = "Private correction feedback"
        correction.lifetime = .keepAlways
        add(correction)
        app.buttons["Undo correction"].tap()
        app.keys["space"].tap()
        let delete = app.keys["Delete"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        delete.press(forDuration: 0.1, thenDragTo: delete.withOffset(CGVector(dx: -30, dy: 0)))
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send ")
        XCTAssertTrue(indicator.isHittable)
        let restore = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        restore.name = "Private word deletion Restore"
        restore.lifetime = .keepAlways
        add(restore)
        app.buttons["Restore deleted text"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send teh ")
        app.buttons["searchEmoji"].tap()
        XCTAssertTrue(indicator.isHittable)
        XCTAssertTrue(app.staticTexts["Popular"].exists)
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["c", "a", "t"] { app.keys[value].tap() }
        XCTAssertTrue(indicator.isHittable)
        let search = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        search.name = "Private emoji search"
        search.lifetime = .keepAlways
        add(search)
        indicator.tap()
        XCTAssertFalse(indicator.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "cat")
        app.buttons["Browse emoji"].tap()
        app.buttons["Back to typing"].tap()
        enablePrivateTyping()
        app.buttons["Close preview"].tap()
        app.buttons["Try the demo"].tap()
        XCTAssertTrue(app.staticTexts["Keyboard preview"].waitForExistence(timeout: 3))
        XCTAssertFalse(keyboard.buttons["privateTypingIndicator"].exists)
    }

    func testWordDeletionInOneHandLayoutAndRotationCancelRestore() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        for value in ["O", "n", "e", "space", "t", "w", "o", "space", "t", "h", "r", "e", "e", "space"] { app.keys[value].tap() }
        keyboard.buttons["Preview settings"].tap()
        let size = app.segmentedControls["Keyboard size"].buttons["Compact"]
        for _ in 0..<8 where !size.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        size.tap()
        let hand = app.segmentedControls["One-hand layout"].buttons["Left"]
        for _ in 0..<8 where !hand.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        hand.tap()
        let speed = app.segmentedControls["Cursor speed"].buttons["Fast"]
        for _ in 0..<8 where !speed.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        speed.tap()
        app.buttons["Back to keyboard"].tap()
        let delete = app.keys["Delete"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        delete.press(forDuration: 0.1, thenDragTo: delete.withOffset(CGVector(dx: -54, dy: 0)))
        XCTAssertEqual(app.staticTexts["previewText"].label, "One ")
        XCTAssertTrue(app.buttons["Restore deleted text"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(keyboard.frame.height - 180) < 1 && keyboard.frame.width > 700
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed, "Keyboard frame: \(keyboard.frame)")
        XCTAssertFalse(app.buttons["Restore deleted text"].exists)
        app.keys["f"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "One f")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Word deletion after one-hand rotation"
        image.lifetime = .keepAlways
        add(image)
    }

    func testCorrectionFeedbackAndHeldWordControlsStayInsideKeyboard() {
        let app = preview()
        for value in ["S", "e", "n", "d", "space", "t", "e", "h", "space"] { app.keys[value].tap() }
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send the ")
        XCTAssertTrue(app.staticTexts["correctionFeedback"].exists)
        let correction = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        correction.name = "Correction feedback"
        correction.lifetime = .keepAlways
        add(correction)
        app.buttons["Undo correction"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send teh")
        app.buttons["Insert teh"].press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Never correct this"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.alerts.count, 0)
        let options = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        options.name = "Word options"
        options.lifetime = .keepAlways
        add(options)
        app.buttons["Never correct this"].tap()
        app.keys["space"].tap()
        for value in ["t", "e", "h"] { app.keys[value].tap() }
        app.buttons["Insert teh"].press(forDuration: 0.6)
        app.buttons["Allow correction"].tap()
        app.keys["space"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send teh the ")
        app.buttons["Undo correction"].tap()
        app.buttons["Insert teh"].press(forDuration: 0.6)
        app.buttons["Forget word"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send teh teh")
        XCTAssertTrue(app.keys["space"].exists)
    }

    func testLayoutOptionsResizePreviewAndSymbolDragReturnsToLetters() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let plane = app.otherElements["keyPlane"]
        keyboard.buttons["Preview settings"].tap()
        app.segmentedControls["Keyboard size"].buttons["Tall"].tap()
        let hand = app.segmentedControls["One-hand layout"].buttons["Right"]
        for _ in 0..<3 where !hand.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        hand.tap()
        let numbers = app.switches["Number row"]
        for _ in 0..<3 where !numbers.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        numbers.tap()
        app.buttons["Back to keyboard"].tap()
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(keyboard.frame.height - 332) < 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed)
        XCTAssertGreaterThan(plane.frame.minX, keyboard.frame.minX + 20)
        app.keys["7"].tap()
        let target = plane.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.375))
        app.keys["Numbers"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: target)
        XCTAssertEqual(app.staticTexts["previewText"].label, "7@")
        XCTAssertTrue(app.keys["Numbers"].exists)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "Tall right-hand keyboard with numbers"
        portrait.lifetime = .keepAlways
        add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(keyboard.frame.height - 252) < 1 && keyboard.frame.width > 700
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed, "Keyboard frame: \(keyboard.frame)")
        XCTAssertLessThanOrEqual(plane.frame.width, 340)
        XCTAssertLessThanOrEqual(plane.frame.maxX, keyboard.frame.maxX)
        app.keys["8"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "7@8")
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Tall keyboard with numbers landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        keyboard.buttons["Preview settings"].tap()
        let size = app.segmentedControls["Keyboard size"].buttons["Compact"]
        for _ in 0..<3 where !size.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        size.tap()
        let left = app.segmentedControls["One-hand layout"].buttons["Left"]
        for _ in 0..<3 where !left.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        left.tap()
        app.buttons["Back to keyboard"].tap()
        XCTAssertLessThan(plane.frame.maxX, keyboard.frame.maxX - 20)
        XCTAssertLessThanOrEqual(keyboard.buttons["Preview settings"].frame.maxX, plane.frame.maxX)
        XCUIDevice.shared.orientation = .portrait
        let compact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(keyboard.frame.height - 272) < 1 && keyboard.frame.width < 500
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [compact], timeout: 5), .completed)
        app.keys["9"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "7@89")
        app.buttons["Use full keyboard width"].tap()
        XCTAssertEqual(plane.frame.width, keyboard.frame.width - 4, accuracy: 1)
    }

    func testHomeKeepsHelpBehindLinksAndReturnsToPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.navigationBars["PrivateType"].waitForExistence(timeout: 5))
        let setup = app.buttons["setupChecklistLink"]
        let demo = app.buttons["Try the demo"]
        XCTAssertTrue(setup.label.contains("Set up PrivateType"))
        XCTAssertTrue(setup.label.contains("0 of 3 steps (self-reported)"))
        XCTAssertTrue(demo.isHittable)
        XCTAssertLessThan(setup.frame.minY, demo.frame.minY)
        XCTAssertFalse(app.otherElements["simpleKeysKeyboard"].exists)
        XCTAssertTrue(app.textFields["keyboardTestField"].exists || app.textViews["keyboardTestField"].exists)
        XCTAssertFalse(app.staticTexts["First development version"].exists)
        XCTAssertFalse(app.staticTexts["Tap the gear above the keys"].exists)
        XCTAssertFalse(app.staticTexts["Word pairs can reveal parts of messages."].exists)
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        home.name = "PrivateType home"
        home.lifetime = .keepAlways
        add(home)

        let field = app.descendants(matching: .any).matching(identifier: "keyboardTestField").firstMatch
        field.tap()
        field.typeText("Test note")

        for (title, content) in [
            ("Keyboard settings", "Tap the gear above the keys"),
            ("Typing tips", "Settings: choose QWERTY or QWERTZ"),
            ("Privacy", "No Full Access required"),
            ("About", "On-device prediction")
        ] {
            let link = app.collectionViews.firstMatch.buttons[title]
            for _ in 0..<3 where !link.isHittable { app.collectionViews.firstMatch.swipeUp() }
            link.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts[content].exists)
            if title == "Keyboard settings" {
                let settingsField = app.textFields["settingsTypingField"]
                XCTAssertTrue(settingsField.isHittable)
                settingsField.tap()
                settingsField.typeText("123")
                XCTAssertEqual(settingsField.value as? String, "123")
            }
            if title == "About" {
                let licenses = app.buttons["Dictionary sources and licenses"]
                for _ in 0..<3 where !licenses.isHittable { app.collectionViews.firstMatch.swipeUp() }
                licenses.tap()
                XCTAssertTrue(app.navigationBars["Dictionary licenses"].waitForExistence(timeout: 3))
                app.navigationBars.buttons.firstMatch.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["PrivateType"].exists)
            XCTAssertEqual(field.value as? String, "Test note")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let privacy = app.collectionViews.firstMatch.buttons["Privacy"]
        for _ in 0..<3 where !privacy.isHittable { app.collectionViews.firstMatch.swipeUp() }
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "PrivateType home landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        let preview = app.buttons["Try the demo"]
        for _ in 0..<3 where !preview.isHittable { app.collectionViews.firstMatch.swipeDown() }
        preview.tap()
        XCTAssertTrue(app.staticTexts["Keyboard preview"].waitForExistence(timeout: 3))
        app.buttons["Close preview"].tap()
        XCTAssertTrue(app.navigationBars["PrivateType"].exists)
    }

    func testLongPressAccentAndEmojiSearch() {
        let app = preview()
        let plane = app.otherElements["keyPlane"]
        let letter = app.keys["E"]
        let menuWidth: CGFloat = 7 * 36
        let menuX = min(max(plane.frame.minX, letter.frame.midX - menuWidth / 2), plane.frame.maxX - menuWidth)
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: menuX + 2.5 * 36, dy: max(plane.frame.minY - 50, letter.frame.minY - 68) + 22))
        letter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: target)
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00ca}")
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["c", "a", "t"] { app.keys[value].tap() }
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00ca}")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "cat")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Emoji search results"
        image.lifetime = .keepAlways
        add(image)
        let cat = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert cat face")).firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 3))
        cat.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00ca}\u{1F431}")
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Preview settings"].exists)
        app.keys["x"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00ca}\u{1F431}x")
    }

    func testSharpSLongPressAndGermanKeyKeepTheExactCharacters() {
        let app = preview()
        let plane = app.otherElements["keyPlane"]
        func choose(_ key: String, index: CGFloat) {
            let letter = app.keys[key]
            let width: CGFloat = 4 * 36
            let x = min(max(plane.frame.minX, letter.frame.midX - width / 2), plane.frame.maxX - width)
            let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: x + (index + 0.5) * 36, dy: max(plane.frame.minY - 50, letter.frame.minY - 68) + 22))
            letter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: target)
        }
        choose("S", index: 0)
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00df}")
        app.keys["a"].tap()
        choose("s", index: 1)
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00df}a\u{1e9e}")
        selectLayout("QWERTZ", in: app)
        app.keys["Shift"].tap()
        XCTAssertTrue(app.keys["\u{1e9e}"].exists)
        app.keys["\u{1e9e}"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00df}a\u{1e9e}\u{1e9e}")
    }

    func testTappingPreviewTextEndsSearchAndResumesMessageTyping() {
        let app = preview()
        for value in ["H", "e", "l", "l", "o"] { app.keys[value].tap() }
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["c", "a", "t"] { app.keys[value].tap() }
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hello")
        app.staticTexts["previewText"].tap()
        XCTAssertTrue(app.otherElements["simpleKeysKeyboard"].buttons["Preview settings"].waitForExistence(timeout: 3))
        app.keys["x"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hellox")
    }

    func testEmojiBrowseFrequentsSearchClearAndReturnToTyping() {
        let app = preview()
        XCTAssertFalse(app.buttons["Dictation"].exists)
        app.buttons["searchEmoji"].tap()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        XCTAssertEqual(keyboard.frame.height, 244, accuracy: 1)
        XCTAssertTrue(app.staticTexts["Popular"].exists)
        let smile = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert grinning face")).firstMatch
        smile.tap()
        smile.tap()
        app.buttons["Back to typing"].tap()
        app.buttons["searchEmoji"].tap()
        XCTAssertTrue(app.staticTexts["Frequently Used"].exists)
        let browse = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        browse.name = "Frequently Used emoji grid"
        browse.lifetime = .keepAlways
        add(browse)
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["c", "a", "x", "Delete", "t"] { app.keys[value].tap() }
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "cat")
        app.buttons["Clear emoji search"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "Empty")
        app.buttons["Browse emoji"].tap()
        XCTAssertTrue(app.staticTexts["Frequently Used"].exists)
        app.buttons["Clear frequently used emojis"].tap()
        app.buttons["Confirm clear emoji history"].tap()
        XCTAssertTrue(app.staticTexts["Popular"].exists)
        app.buttons["Delete last character"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{1F600}")
        app.buttons["Back to typing"].tap()
        XCTAssertEqual(keyboard.frame.height, 244, accuracy: 1)
        app.keys["x"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{1F600}x")
    }

    func testEmojiHeaderMarginsAndSearchPaddingSurviveRotation() {
        let app = preview()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["searchEmoji"].tap()
        let search = app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch
        let delete = app.buttons["Delete last character"]
        let abc = app.buttons["Back to typing"]
        let grid = app.collectionViews["emojiResults"]
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        for landscape in [false, true] {
            if landscape {
                XCUIDevice.shared.orientation = .landscapeLeft
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    keyboard.frame.width > 700 && abs(keyboard.frame.height - 196) < 1
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed, "Keyboard frame: \(keyboard.frame)")
            }
            XCTAssertEqual(delete.frame.width, 44, accuracy: 1)
            XCTAssertEqual(delete.frame.height, 44, accuracy: 1)
            XCTAssertEqual(abc.frame.minX - delete.frame.maxX, 4, accuracy: 1)
            XCTAssertEqual(delete.frame.maxX, grid.frame.maxX - 48, accuracy: 1)
            XCTAssertEqual(delete.frame.minX - search.frame.maxX, 4, accuracy: 1)
            XCTAssertGreaterThanOrEqual(abc.frame.minX - keyboard.frame.minX, 8)
            XCTAssertLessThanOrEqual(delete.frame.maxX, keyboard.frame.maxX - (landscape ? 44 : 8))
            let browse = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            browse.name = landscape ? "Emoji margins landscape" : "Emoji margins portrait"
            browse.lifetime = .keepAlways
            add(browse)
            for edge: CGFloat in [0.02, 0.98] {
                search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: edge)).tap()
                let browse = app.buttons["Browse emoji"]
                XCTAssertTrue(browse.waitForExistence(timeout: 3))
                XCTAssertFalse(delete.exists)
                app.keys["c"].tap()
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "c")
                let clear = app.buttons["Clear emoji search"]
                XCTAssertGreaterThanOrEqual(browse.frame.width, 44)
                XCTAssertGreaterThanOrEqual(browse.frame.height, 44)
                XCTAssertGreaterThanOrEqual(clear.frame.width, 44)
                XCTAssertLessThanOrEqual(clear.frame.maxX, browse.frame.minX)
                browse.tap()
                XCTAssertTrue(delete.waitForExistence(timeout: 3))
            }
        }
    }

    func testEmojiSearchSurvivesRotationAndOffersClearForNoMatches() {
        let app = preview()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.keys["H"].tap()
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["q", "q", "q", "q"] { app.keys[value].tap() }
        XCTAssertTrue(app.staticTexts["No emoji found. Try another word."].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let size = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(keyboard.frame.height - 240) < 1 && keyboard.frame.width > 700
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [size], timeout: 5), .completed)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "qqqq")
        app.buttons["Clear search"].tap()
        app.keys["c"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.value as? String, "c")
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Emoji search landscape"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Close preview"].tap()
        let demo = app.buttons["Try the demo"]
        reveal(demo, in: app.collectionViews.firstMatch)
        demo.tap()
        XCTAssertTrue(app.staticTexts["previewText"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Browse emoji"].exists)
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
        app.keys["i"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hi")
    }

    func testPreviewTypesAndSwitchesLanguage() {
        let app = preview()
        app.keys["H"].tap()
        app.keys["e"].tap()
        app.keys["l"].tap()
        app.keys["l"].tap()
        app.keys["o"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hello")
        app.keys["space"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hello ")
        selectLayout("QWERTZ", in: app)
        XCTAssertTrue(app.keys["ü"].exists)
        app.keys["ü"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hello ü")
        app.keys["Delete"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hello ")
        app.buttons["Close preview"].tap()
        app.buttons["Try the demo"].tap()
        app.keys["b"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hello b")
    }

    func testSettingsOpensRepeatedlyWithoutAHeightChangeOrAnAlert() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        XCTAssertEqual(keyboard.frame.height, 244, accuracy: 1)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "PrivateType portrait"
        image.lifetime = .keepAlways
        add(image)
        for _ in 0..<3 {
            app.otherElements["simpleKeysKeyboard"].buttons["Preview settings"].tap()
            XCTAssertTrue(app.switches["Spell correction"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            XCTAssertEqual(keyboard.frame.height, 244, accuracy: 1)
            app.buttons["Back to keyboard"].tap()
        }
        app.keys["H"].tap()
        app.keys["i"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Hi")
    }

    func testLandscapeKeepsSettingsInsideTheCompactKeyboard() {
        let app = preview(landscape: true)
        defer { XCUIDevice.shared.orientation = .portrait }
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let size = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(keyboard.frame.height - 196) < 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [size], timeout: 5), .completed)
        XCTAssertGreaterThan(keyboard.frame.width, 700)
        XCTAssertLessThanOrEqual(keyboard.frame.maxX, app.windows.firstMatch.frame.maxX)
        app.otherElements["simpleKeysKeyboard"].buttons["Preview settings"].tap()
        XCTAssertTrue(app.switches["Neural predictions"].exists)
        XCTAssertEqual(keyboard.frame.height, 196, accuracy: 1)
        let delete = app.buttons["Delete learned data"]
        for _ in 0..<2 where !delete.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        delete.tap()
        XCTAssertTrue(app.buttons["Confirm deletion"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Delete learned data"].exists)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "PrivateType landscape settings"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Back to keyboard"].tap()
        app.keys["H"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
    }

    func testTouchDiagnosticsOpensInlineAndSurvivesRotation() {
        let app = preview()
        defer { XCUIDevice.shared.orientation = .portrait }
        app.otherElements["simpleKeysKeyboard"].buttons["Preview settings"].tap()
        let diagnostics = app.buttons["Touch zones and statistics"]
        for _ in 0..<4 where !diagnostics.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        diagnostics.tap()
        XCTAssertTrue(app.staticTexts["Touch zones"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["Touch zone map"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        XCUIDevice.shared.orientation = .landscapeLeft
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            keyboard.frame.width > 700 && abs(keyboard.frame.height - 196) < 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed, "Keyboard frame: \(keyboard.frame)")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Touch zones landscape"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Back to settings"].tap()
        XCTAssertTrue(app.switches["Local learning"].exists)
        app.buttons["Back to keyboard"].tap()
        app.keys["H"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
    }

    func testOpenPreviewResizesWhenRotated() {
        let app = preview()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let size = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(keyboard.frame.height - 196) < 1 && keyboard.frame.width > 700
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [size], timeout: 5), .completed)
        XCTAssertEqual(keyboard.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
        app.keys["H"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "PrivateType rotated keyboard"
        image.lifetime = .keepAlways
        add(image)
    }

    func testSetupChecklistPersistsConfirmationsAndResetKeepsTypingAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let checklist = app.buttons["setupChecklistLink"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 5))
        checklist.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.otherElements["simpleKeysKeyboard"].exists)
        XCTAssertTrue(app.staticTexts["Tap the sample field to open the keyboard. Hold the globe key and select PrivateType."].exists)
        let enabled = app.buttons["I enabled PrivateType"]
        let selected = app.buttons["I selected PrivateType"]
        let field = app.textFields["setupTypingField"]
        let learningNote = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Local learning starts on.")).firstMatch
        XCTAssertTrue(learningNote.exists)
        XCTAssertLessThan(learningNote.frame.minY, field.frame.minY)
        field.tap()
        field.typeText("123")
        XCTAssertTrue(app.staticTexts["Text entered"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(checklist.label.contains("1 of 3 steps (self-reported)"))
        XCTAssertTrue(app.buttons["Try the demo"].isHittable)
        checklist.tap()
        XCTAssertEqual(enabled.value as? String, "Not confirmed")
        XCTAssertEqual(selected.value as? String, "Not confirmed")
        enabled.tap()
        selected.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(checklist.label.contains("Review setup"))
        XCTAssertTrue(checklist.label.contains("3 of 3 steps (self-reported)"))
        app.terminate()
        app.launchArguments.append("--keep-setup-progress")
        app.launch()
        checklist.tap()
        XCTAssertEqual(enabled.value as? String, "Confirmed")
        XCTAssertEqual(selected.value as? String, "Confirmed")
        XCTAssertTrue(app.staticTexts["Text entered"].exists)
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.placeholderValue, "Type a short sample")
        field.tap()
        field.typeText("456")
        XCTAssertEqual(field.value as? String, "456")
        let retry = app.buttons["Retry typing"]
        retry.tap()
        XCTAssertFalse(app.staticTexts["Text entered"].exists)
        let reset = app.buttons["Reset checklist"]
        for _ in 0..<4 where !reset.isHittable { app.collectionViews.firstMatch.swipeUp() }
        reset.tap()
        for _ in 0..<4 where !enabled.isHittable { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertEqual(enabled.value as? String, "Not confirmed")
        XCTAssertEqual(selected.value as? String, "Not confirmed")
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Optional setup checklist"
        image.lifetime = .keepAlways
        add(image)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(checklist.label.contains("Set up PrivateType"))
    }

    func testCorrectionPracticeCompletesRetriesAndKeepsNormalSettings() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        XCTAssertTrue(app.staticTexts["Hold E for accents."].exists)
        XCTAssertTrue(app.staticTexts["Preview settings apply here only."].exists)
        keyboard.buttons["Preview settings"].tap()
        XCTAssertTrue(keyboard.staticTexts["Preview settings"].exists)
        app.switches["Spell correction"].tap()
        app.buttons["Back to keyboard"].tap()
        app.keys["H"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
        app.buttons["Practice correction and Undo"].tap()
        XCTAssertTrue(app.staticTexts["Correction practice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["previewText"].exists)
        XCTAssertEqual(app.otherElements.matching(identifier: "simpleKeysKeyboard").count, 1)
        for key in ["t", "e", "h", "space"] { app.keys[key].tap() }
        XCTAssertEqual(app.staticTexts["practiceText"].label, "Send the ")
        XCTAssertEqual(app.staticTexts["practiceInstruction"].label, "Tap Undo to restore teh.")
        app.buttons["Undo correction"].tap()
        XCTAssertEqual(app.staticTexts["practiceInstruction"].label, "Original restored. Try again when ready.")
        app.buttons["Try again"].tap()
        XCTAssertEqual(app.staticTexts["practiceText"].label, "Send ")
        for key in ["t", "h", "e", "space"] { app.keys[key].tap() }
        XCTAssertFalse(app.buttons["Undo correction"].exists)
        XCTAssertEqual(app.staticTexts["practiceInstruction"].label, "Tap Try again. Then type teh.")
        app.buttons["Close practice"].tap()
        XCTAssertTrue(app.staticTexts["previewText"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["previewText"].label, "H")
        app.buttons["Close preview"].tap()
        app.buttons["setupChecklistLink"].tap()
        let practice = app.buttons["Practice correction and Undo"]
        for _ in 0..<4 where !practice.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(practice.waitForExistence(timeout: 3))
        practice.tap()
        XCTAssertEqual(app.staticTexts["practiceText"].label, "Send ")
        app.buttons["Close practice"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Try the demo"].tap()
        XCTAssertTrue(app.staticTexts["previewText"].waitForExistence(timeout: 3))
        keyboard.buttons["Preview settings"].tap()
        XCTAssertTrue(app.switches["Spell correction"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches["Spell correction"].value as? String, "0")
        XCTAssertEqual(app.switches["Local learning"].value as? String, "0")
    }

    func testPreferredLanguageAndAfrikaansEmojiSearch() {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        keyboard.buttons["Preview settings"].tap()
        let preference = app.buttons["preferredLanguageButton"]
        for _ in 0..<4 where !preference.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        preference.tap()
        let afrikaans = app.buttons["preferredLanguage.afrikaans"]
        for _ in 0..<4 where !afrikaans.isHittable { app.scrollViews["keyboardSettingsPanel"].swipeUp() }
        XCTAssertEqual(afrikaans.label, "Afrikaans")
        XCTAssertGreaterThanOrEqual(afrikaans.frame.height, 44)
        afrikaans.tap()
        XCTAssertEqual(preference.label, "Preferred language: Afrikaans")
        app.buttons["Back to keyboard"].tap()
        XCTAssertFalse(app.keys["Language: English. Switch language."].exists)
        XCTAssertTrue(app.keys["Q"].exists)
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for key in ["k", "o", "f", "f", "e", "i"] { app.keys[key].tap() }
        let coffee = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert hot beverage")).firstMatch
        XCTAssertTrue(coffee.waitForExistence(timeout: 3))
        coffee.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{2615}")
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for key in ["w", "o", "m", "a", "n", "space", "d", "o", "c", "t", "o", "r"] { app.keys[key].tap() }
        let doctor = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@",
            "Insert woman health worker doctor nurse")).firstMatch
        XCTAssertTrue(doctor.waitForExistence(timeout: 3))
        doctor.press(forDuration: 0.6)
        let variant = app.otherElements["emojiTonePanel"].buttons["Insert woman health worker doctor nurse dark skin tone"]
        XCTAssertTrue(variant.waitForExistence(timeout: 3))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Compound emoji search"
        image.lifetime = .keepAlways
        add(image)
        variant.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{2615}\u{1F469}\u{1F3FF}\u{200D}\u{2695}\u{FE0F}")
    }

    func testAccessibilityOptionsKeepGeometryAndPrivateEditingControls() {
        let app = preview(dark: true)
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        let plane = app.otherElements["keyPlane"]
        let frame = plane.frame
        keyboard.buttons["Preview settings"].tap()
        let panel = app.scrollViews["keyboardSettingsPanel"]
        let privateToggle = app.switches["Private typing"]
        for _ in 0..<6 where !privateToggle.isHittable { panel.swipeUp() }
        privateToggle.tap()
        for name in ["Larger key labels", "High contrast"] {
            let toggle = app.switches[name]
            reveal(toggle, in: panel)
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        app.buttons["Back to keyboard"].tap()
        XCTAssertEqual(plane.frame, frame)
        XCTAssertTrue(keyboard.buttons["privateTypingIndicator"].exists)
        for key in ["S", "e", "n", "d", "space", "t", "e", "h", "space"] { app.keys[key].tap() }
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send the ")
        let correction = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        correction.name = "Larger labels and high contrast correction"
        correction.lifetime = .keepAlways
        add(correction)
        app.buttons["Undo correction"].tap()
        app.keys["space"].tap()
        let delete = app.keys["Delete"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        delete.press(forDuration: 0.1, thenDragTo: delete.withOffset(CGVector(dx: -30, dy: 0)))
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send ")
        app.buttons["Restore deleted text"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "Send teh ")
        XCTAssertTrue(keyboard.buttons["privateTypingIndicator"].exists)
        app.buttons["Close preview"].tap()
        app.buttons["Try the demo"].tap()
        keyboard.buttons["Preview settings"].tap()
        let learning = app.switches["Local learning"]
        for _ in 0..<4 where !learning.isHittable { panel.swipeUp() }
        let settings = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        settings.name = "High contrast dark settings with on and off switches"
        settings.lifetime = .keepAlways
        add(settings)
        for name in ["Larger key labels", "High contrast"] {
            let toggle = app.switches[name]
            reveal(toggle, in: panel)
            XCTAssertEqual(toggle.value as? String, "1")
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
        app.buttons["Back to keyboard"].tap()
        XCTAssertEqual(plane.frame, frame)
    }

    func testLargestSettingsTextStaysScrollableInDarkLandscape() {
        let app = preview(landscape: true, largestText: true)
        defer { XCUIDevice.shared.orientation = .portrait }
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        keyboard.buttons["Preview settings"].tap()
        let touch = app.buttons["Touch zones and statistics"]
        let panel = app.scrollViews["keyboardSettingsPanel"]
        for _ in 0..<30 where !touch.isHittable { panel.swipeUp() }
        XCTAssertTrue(touch.isHittable)
        XCTAssertGreaterThanOrEqual(touch.frame.height, 44)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Largest settings text in dark landscape"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Back to keyboard"].tap()
        XCTAssertTrue(app.keys["Q"].exists)
    }

    func testPrivateSettingsKeepsBackBeforeStatusThroughRotationAndDiagnostics() throws {
        let app = preview()
        let keyboard = app.otherElements["simpleKeysKeyboard"]
        keyboard.buttons["Preview settings"].tap()
        try setPrivateOn(app)
        let back = app.buttons["Back to keyboard"]
        let status = keyboard.buttons["privateTypingIndicator"]
        XCTAssertLessThanOrEqual(back.frame.maxX, status.frame.minX)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        XCTAssertGreaterThanOrEqual(status.frame.height, 44)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        portrait.name = "Private settings with stable close control"
        portrait.lifetime = .keepAlways
        add(portrait)
        let panel = app.scrollViews["keyboardSettingsPanel"]
        let diagnostics = app.buttons["Touch zones and statistics"]
        reveal(diagnostics, in: panel)
        diagnostics.tap()
        let diagnosticsBack = app.buttons["Back to settings"]
        XCTAssertGreaterThanOrEqual(diagnosticsBack.frame.minX, status.frame.maxX)
        diagnosticsBack.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(back.frame.maxX, status.frame.minX)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Private settings landscape with stable close control"
        landscape.lifetime = .keepAlways
        add(landscape)
        back.tap()
        XCTAssertTrue(status.exists)
        XCTAssertTrue(keyboard.buttons["Preview settings"].exists)
    }

    func testTypingBenchmarkSavesMetricsAndDeletesResults() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["typingBenchmarkLink"].tap()
        XCTAssertTrue(app.buttons["benchmarkStart"].waitForExistence(timeout: 3))
        let ready = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        ready.name = "Typing test ready"
        ready.lifetime = .keepAlways
        add(ready)
        app.buttons["benchmarkStart"].tap()
        let field = app.textViews["benchmarkInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Please send ")
        field.typeText("the meeting details tomorrow morning.")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let nativeKeyboard = app.keyboards.firstMatch
        let customKeyboard = app.otherElements["simpleKeysKeyboard"]
        func visible(_ keyboard: XCUIElement) -> Bool {
            keyboard.exists && !keyboard.frame.isEmpty && app.windows.firstMatch.frame.contains(keyboard.frame)
        }
        if !visible(nativeKeyboard) && !visible(customKeyboard) { field.tap() }
        let keyboardReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            visible(nativeKeyboard) || visible(customKeyboard)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardReady], timeout: 5), .completed)
        let keyboard = try XCTUnwrap(visible(nativeKeyboard) ? nativeKeyboard : (visible(customKeyboard) ? customKeyboard : nil))
        XCTAssertGreaterThanOrEqual(field.frame.height, 44)
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(app.staticTexts["benchmarkTarget"].frame.maxY, field.frame.minY)
        let running = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        running.name = "Typing test landscape input"
        running.lifetime = .keepAlways
        add(running)
        app.buttons["benchmarkFinish"].tap()
        XCTAssertTrue(app.buttons["benchmarkSave"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["benchmarkSave"].isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["benchmarkSave"].frame))
        XCTAssertFalse(field.exists)
        app.buttons["benchmarkSave"].tap()
        XCTAssertFalse(app.buttons["benchmarkSave"].isEnabled)
        app.terminate()
        app.launchArguments.append("--keep-benchmark-results")
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.buttons["typingBenchmarkLink"].tap()
        app.buttons["benchmarkResults"].tap()
        XCTAssertTrue(app.staticTexts["Automated check"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Export CSV"].exists)
        app.buttons["Delete all results"].tap()
        app.buttons.matching(identifier: "benchmarkConfirmDeleteAll").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No saved results"].waitForExistence(timeout: 3))
    }

    func testTypingBenchmarkCancelEmptyFinishAndInterruption() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["typingBenchmarkLink"].tap()
        app.buttons["benchmarkStart"].tap()
        app.buttons["benchmarkFinish"].tap()
        XCTAssertTrue(app.staticTexts["benchmarkError"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["benchmarkSave"].exists)
        app.buttons["benchmarkStart"].tap()
        let field = app.textViews["benchmarkInput"]
        field.tap()
        field.typeText("Temporary text")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["benchmarkStart"].exists)
        app.buttons["benchmarkStart"].tap()
        XCTAssertEqual(field.value as? String, "")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["benchmarkStart"].waitForExistence(timeout: 3))
        XCTAssertFalse(field.exists)
        XCTAssertTrue(app.staticTexts["benchmarkError"].exists)
    }

    func testTypingBenchmarkRepairAndRetryClearTaskInput() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["typingBenchmarkLink"].tap()
        app.buttons["benchmarkTask"].tap()
        app.buttons["Repair a typo"].tap()
        app.buttons["benchmarkStart"].tap()
        let field = app.textViews["benchmarkInput"]
        XCTAssertEqual(field.value as? String, "Please send teh details.")
        field.tap()
        field.press(forDuration: 1.1)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) { selectAll.tap() }
        else { app.buttons["Select All"].tap() }
        field.typeText("Please send the details.")
        XCTAssertEqual(field.value as? String, "Please send the details.")
        app.buttons["benchmarkFinish"].tap()
        XCTAssertTrue(app.staticTexts["Time includes keyboard opening."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Words per minute"].exists)
        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        result.name = "Typing test repair result"
        result.lifetime = .keepAlways
        add(result)
        app.buttons["Try again"].tap()
        app.buttons["benchmarkTask"].tap()
        app.buttons["German"].tap()
        app.buttons["benchmarkStart"].tap()
        XCTAssertEqual(field.value as? String, "")
        app.buttons["Cancel"].tap()
    }

    func testReturnIconKeyKeepsNewlineInputInBothOrientations() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for landscape in [false, true] {
            let app = preview(landscape: landscape, dark: landscape)
            app.keys["Numbers"].tap()
            app.keys["1"].tap()
            app.keys["return"].tap()
            app.keys["2"].tap()
            XCTAssertEqual(app.staticTexts["previewText"].label, "1\n2")
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = landscape ? "Return icon dark landscape" : "Return icon light portrait"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testMovingEmojiContactDoesNotSwitchAndIntentionalTapStillOpens() {
        let app = preview()
        let button = app.otherElements["simpleKeysKeyboard"].buttons["searchEmoji"]
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            .press(forDuration: 0.05, thenDragTo: button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertFalse(app.buttons["Back to typing"].exists)
        XCTAssertTrue(button.exists)
        app.keys["S"].tap()
        button.tap()
        XCTAssertTrue(app.buttons["Back to typing"].waitForExistence(timeout: 3))
        app.buttons["Back to typing"].tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "S")
    }

    func testRepeatedModeTapsKeepControlsTextSettingsAndEmojiHistory() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        for landscape in [false, true] {
            let app = preview(landscape: landscape)
            let keyboard = app.otherElements["simpleKeysKeyboard"]
            let gear = keyboard.buttons["keyboardSettingsToggle"]
            let emoji = keyboard.buttons["searchEmoji"]
            emoji.tap()
            app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert grinning face")).firstMatch.tap()
            emoji.tap()
            let originalEmojiPoint = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: emoji.frame.midX, dy: emoji.frame.midY))
            originalEmojiPoint.tap()
            XCTAssertEqual(app.buttons["emojiCategory.0"].label, "Frequently Used")
            originalEmojiPoint.tap()
            XCTAssertTrue(app.keys["Numbers"].exists)
            gear.tap()
            try setPrivateOn(app)
            gear.tap()
            let gearPoint = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: gear.frame.midX, dy: gear.frame.midY))
            let emojiPoint = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: emoji.frame.midX, dy: emoji.frame.midY))
            let gearFrame = gear.frame
            let emojiFrame = emoji.frame
            gearPoint.tap()
            let neural = app.switches["Neural predictions"].value as? String
            gearPoint.tap()
            XCTAssertTrue(app.keys["Numbers"].exists)
            gearPoint.tap()
            XCTAssertEqual(app.switches["Neural predictions"].value as? String, neural)
            gearPoint.tap()
            emojiPoint.tap()
            XCTAssertEqual(emoji.frame, emojiFrame)
            XCTAssertTrue(app.staticTexts["Popular"].exists)
            emojiPoint.tap()
            XCTAssertTrue(app.keys["Numbers"].exists)
            emojiPoint.tap()
            app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
            XCTAssertTrue(app.buttons["Browse emoji"].waitForExistence(timeout: 3))
            XCTAssertEqual(emoji.frame, emojiFrame)
            XCTAssertEqual(gear.frame, gearFrame)
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = landscape ? "Stable controls in landscape search" : "Stable controls in portrait search"
            image.lifetime = .keepAlways
            add(image)
            emojiPoint.tap()
            XCTAssertTrue(app.keys["Numbers"].exists)
            XCTAssertEqual(app.staticTexts["previewText"].label, "\u{1F600}")
            XCTAssertTrue(keyboard.buttons["privateTypingIndicator"].exists)
            keyboard.buttons["privateTypingIndicator"].tap()
            emojiPoint.tap()
            XCTAssertEqual(app.buttons["emojiCategory.0"].label, "Frequently Used")
        }
    }

    func testEmojiHistoryClearNeedsSeparateConfirmationAndNavigationCancelsIt() {
        let app = preview()
        let emoji = app.buttons["searchEmoji"]
        emoji.tap()
        app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert grinning face")).firstMatch.tap()
        emoji.tap()
        emoji.tap()
        let clear = app.buttons["Clear frequently used emojis"]
        XCTAssertTrue(clear.exists)
        let clearPoint = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: clear.frame.midX, dy: clear.frame.midY))
        clearPoint.tap()
        XCTAssertTrue(app.buttons["Confirm clear emoji history"].exists)
        clearPoint.tap()
        XCTAssertTrue(app.buttons["Confirm clear emoji history"].exists)
        app.buttons["Cancel clear emoji history"].tap()
        XCTAssertTrue(app.staticTexts["Frequently Used"].exists)
        clear.tap()
        emoji.tap()
        emoji.tap()
        XCTAssertFalse(app.buttons["Confirm clear emoji history"].exists)
        XCTAssertTrue(app.staticTexts["Frequently Used"].exists)
        clear.tap()
        app.buttons["Confirm clear emoji history"].tap()
        XCTAssertTrue(app.staticTexts["Popular"].exists)
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{1F600}")
    }

    func testTypingBenchmarkNextSampleRetryAndUsageCategories() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["typingBenchmarkLink"].tap()
        let first = app.staticTexts["benchmarkTarget"].label
        app.buttons["benchmarkNextSample"].tap()
        let second = app.staticTexts["benchmarkTarget"].label
        XCTAssertNotEqual(first, second)
        app.buttons["benchmarkStart"].tap()
        XCTAssertEqual(app.staticTexts["benchmarkTarget"].label, second)
        XCTAssertFalse(app.buttons["benchmarkNextSample"].exists)
        let input = app.textViews["benchmarkInput"]
        input.tap()
        input.typeText("Can ")
        input.typeText("you send 3 files by 09:30? Thanks!")
        app.buttons["benchmarkFinish"].tap()
        app.buttons["Try again"].tap()
        XCTAssertEqual(app.staticTexts["benchmarkTarget"].label, second)
        for category in ["Punctuation", "Numbers", "Symbols", "Emoji"] {
            let picker = app.buttons["benchmarkTask"]
            let option = app.buttons[category]
            picker.tap()
            if !option.waitForExistence(timeout: 2) { picker.tap() }
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.tap()
            XCTAssertEqual(app.staticTexts["benchmarkSampleNumber"].label, "Sample 1 of 3")
            let target = app.staticTexts["benchmarkTarget"].label
            app.buttons["benchmarkNextSample"].tap()
            XCTAssertNotEqual(app.staticTexts["benchmarkTarget"].label, target)
            app.buttons["benchmarkStart"].tap()
            XCTAssertTrue(input.waitForExistence(timeout: 3))
            XCTAssertEqual(input.value as? String ?? "", "")
            app.buttons["Cancel"].tap()
        }
    }

    func testEmojiToneLongPressRequiresSeparateTapAndCategoryBrowseWorks() {
        let app = preview()
        app.buttons["searchEmoji"].tap()
        let categories = app.scrollViews["emojiCategories"]
        XCTAssertTrue(categories.waitForExistence(timeout: 3))
        app.buttons["emojiCategory.1"].tap()
        app.buttons["emojiCategory.0"].tap()
        let thumbs = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert thumbs up sign")).firstMatch
        XCTAssertTrue(thumbs.waitForExistence(timeout: 3))
        let textBeforeHold = app.staticTexts["previewText"].label
        thumbs.press(forDuration: 0.6)
        let cancel = app.buttons["Cancel skin tone selection"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["previewText"].label, textBeforeHold)
        let before = textBeforeHold
        let panel = app.otherElements["emojiTonePanel"]
        let tone = panel.buttons.matching(NSPredicate(format: "label CONTAINS %@", "dark skin tone")).allElementsBoundByIndex.last!
        XCTAssertGreaterThanOrEqual(tone.frame.width, 44)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Emoji tone choices"
        image.lifetime = .keepAlways
        add(image)
        cancel.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, before)
        thumbs.press(forDuration: 0.6)
        tone.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{1F44D}\u{1F3FF}")
        XCTAssertTrue(categories.exists)
        app.buttons["Back to typing"].tap()
        app.buttons["searchEmoji"].tap()
        app.descendants(matching: .any).matching(identifier: "emojiSearchField").firstMatch.tap()
        for value in ["t", "h", "u", "m", "b", "s"] { app.keys[value].tap() }
        let result = app.collectionViews["emojiResults"].cells.matching(NSPredicate(format: "label == %@", "Insert thumbs up sign")).firstMatch
        result.press(forDuration: 0.6)
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        panel.buttons.matching(NSPredicate(format: "label CONTAINS %@", "dark skin tone")).allElementsBoundByIndex.last!.tap()
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{1F44D}\u{1F3FF}\u{1F44D}\u{1F3FF}")
        XCTAssertTrue(app.keys["Numbers"].exists)
    }

    func testStationaryLongPressSelectsNearestAlternateAndCurrencyMenuWorks() {
        let app = preview()
        app.keys["Shift"].tap()
        app.keys["u"].press(forDuration: 0.6)
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00fb}")
        app.keys["Numbers"].tap()
        app.keys["More symbols"].tap()
        let dollar = app.keys["$"]
        let plane = app.otherElements["keyPlane"]
        let width: CGFloat = 144
        let x = min(max(plane.frame.minX, dollar.frame.midX - width / 2), plane.frame.maxX - width)
        let target = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: x + 18, dy: max(plane.frame.minY - 50, dollar.frame.minY - 68) + 22))
        dollar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6, thenDragTo: target)
        XCTAssertEqual(app.staticTexts["previewText"].label, "\u{00fb}\u{20ac}")
    }

    func testDarkLandscapeEmojiCategoriesKeepCompleteRowsAndToneChoices() {
        let app = preview(landscape: true, dark: true)
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["searchEmoji"].tap()
        let categories = app.scrollViews["emojiCategories"]
        let flags = app.buttons["emojiCategory.9"]
        for _ in 0..<4 where !flags.isHittable { categories.swipeLeft() }
        XCTAssertTrue(flags.isHittable)
        flags.tap()
        let grid = app.collectionViews["emojiResults"]
        let cell = grid.cells.matching(NSPredicate(format: "label CONTAINS %@", "flag")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 3))
        XCTAssertTrue(cell.isHittable)
        XCTAssertGreaterThanOrEqual(grid.frame.height, 44)
        XCTAssertTrue(grid.frame.contains(cell.frame))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Dark landscape category grid"
        image.lifetime = .keepAlways
        add(image)
        let frequent = app.buttons["emojiCategory.0"]
        for _ in 0..<4 where !frequent.isHittable { categories.swipeRight() }
        frequent.tap()
        let thumb = grid.cells.matching(NSPredicate(format: "label == %@", "Insert thumbs up sign")).firstMatch
        thumb.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Cancel skin tone selection"].waitForExistence(timeout: 3))
        app.buttons["Cancel skin tone selection"].tap()
    }

}
