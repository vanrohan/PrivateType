import XCTest
import UIKit
@testable import SimpleKeyboard

@MainActor
private class TestDocumentProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var contextAvailable = true
    var documentContextBeforeInput: String? { contextAvailable ? text : nil }
    var documentContextAfterInput: String? { after }
    var selection: String?
    var after: String? = ""
    var selectedText: String? { selection }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty || !(after ?? "").isEmpty || !(selection ?? "").isEmpty }
    var keyboardType: UIKeyboardType = .default
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    func insertText(_ value: String) { text += value; selection = nil }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    var cursorOffsets: [Int] = []
    func adjustTextPosition(byCharacterOffset offset: Int) { cursorOffsets.append(offset) }
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}

private final class DelayedCapitalizationModel: NeuralWordModel {
    let name = "Delayed capitalization test"
    let started: XCTestExpectation
    let gate: DispatchSemaphore
    let finished: XCTestExpectation?
    init(started: XCTestExpectation, gate: DispatchSemaphore, finished: XCTestExpectation? = nil) {
        self.started = started; self.gate = gate; self.finished = finished
    }
    func words(context: String, prefix: String, candidates: [String]) throws -> [String] {
        started.fulfill()
        _ = gate.wait(timeout: .now() + 2)
        finished?.fulfill()
        return ["zebra"]
    }
}

private final class CorrectionCandidateModel: NeuralWordModel {
    let name = "Correction candidate test"
    let started: XCTestExpectation
    let gate: DispatchSemaphore
    init(started: XCTestExpectation, gate: DispatchSemaphore) {
        self.started = started
        self.gate = gate
    }
    func words(context: String, prefix: String, candidates: [String]) throws -> [String] {
        XCTAssertEqual(prefix, "atuff")
        XCTAssertTrue(candidates.contains("stuff"))
        started.fulfill()
        _ = gate.wait(timeout: .now() + 2)
        return ["stuff"]
    }
}

private final class SymbolInputModel: NeuralWordModel {
    let name = "Symbol input test"
    let received: XCTestExpectation
    init(received: XCTestExpectation) { self.received = received }
    func words(context: String, prefix: String, candidates: [String]) throws -> [String] {
        XCTAssertEqual(context, "on my ")
        XCTAssertEqual(prefix, "ze")
        received.fulfill()
        return ["zebra"]
    }
}

private final class FixedSuggestionModel: NeuralWordModel {
    let name = "Fixed suggestion test"
    let output: [String]
    init(_ output: [String]) { self.output = output }
    func words(context: String, prefix: String, candidates: [String]) throws -> [String] { output }
}

@MainActor
final class KeyboardInteractionTests: XCTestCase {
    private var suite: String!
    private var controller: KeyboardViewController!

    func testSuggestionRowFitsFourShortWordsAndAcceptsTheFourthWord() async throws {
        try await loadSuggestions(["a", "to", "we", "is"])
        let visible = controller.suggestionButtons.filter { !$0.isHidden }
        XCTAssertEqual(visible.count, 4)
        XCTAssertTrue(visible.allSatisfy { $0.bounds.width >= 44 })
        let fourth = try XCTUnwrap(visible.last)
        let word = try XCTUnwrap(fourth.currentTitle)
        let options = try XCTUnwrap(fourth.accessibilityCustomActions?.first)
        XCTAssertEqual(options.actionHandler?(options), true)
        XCTAssertTrue(controller.isShowingWordOptions)
        controller.hideWordOptions()
        fourth.sendActions(for: .touchDown)
        fourth.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, word + " ")
    }

    func testSymbolSuggestionsPreserveTheEarlierText() async throws {
        controller.storage.preferredLanguage = .english
        for (context, expected) in [("International-ze", "International-zebra "),
                                    ("2026-ze", "2026-zebra "),
                                    ("International_--ze", "International_--zebra "),
                                    ("International-send/", "International-send/zebra "),
                                    ("International-", "International-zebra ")] {
            try await loadSuggestions(["zebra"], context: context)
            let button = try XCTUnwrap(controller.suggestionButtons.first { !$0.isHidden && $0.currentTitle == "zebra" })
            button.sendActions(for: .touchDown)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.context, expected, context)
        }
    }

    func testDictionarySuggestionAfterSymbolPreservesTheEarlierText() throws {
        controller.demoText = "only-seeing-atuff"
        controller.textDidChange(nil)
        controller.view.layoutIfNeeded()
        let button = try XCTUnwrap(controller.suggestionButtons.first { !$0.isHidden && $0.currentTitle == "stuff" })
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "only-seeing-stuff ")
    }

    func testNeuralInputTreatsSymbolsAsSpaces() async {
        let received = expectation(description: "The model receives the active word")
        controller.neuralService = NeuralPredictionService { _, _ in
            SymbolInputModel(received: received)
        }
        controller.storage.neuralPrediction = true
        controller.demoText = "on-my-ze"
        controller.textDidChange(nil)
        await fulfillment(of: [received], timeout: 3)
    }

    func testFourthSuggestionReplacesTheActiveToken() async throws {
        try await loadSuggestions(["cat", "can", "car"], context: "c")
        let visible = controller.suggestionButtons.filter { !$0.isHidden }
        XCTAssertEqual(visible.count, 4)
        XCTAssertEqual(visible.first?.currentTitle, "c")
        let fourth = try XCTUnwrap(visible.last)
        let word = try XCTUnwrap(fourth.currentTitle)
        fourth.sendActions(for: .touchDown)
        fourth.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, word + " ")
    }

    func testNarrowRowKeepsTheLikelyCompletionBeforeWeakCorrections() {
        controller.view.frame.size.width = 320
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.demoText = "please send it tomorr"
        controller.textDidChange(nil)
        controller.view.layoutIfNeeded()
        let visible = controller.suggestionButtons.filter { !$0.isHidden }
        XCTAssertEqual(visible.first?.currentTitle, "tomorr")
        XCTAssertEqual(visible.dropFirst().first?.currentTitle, "tomorrow")
    }

    func testSuggestionRowReflowsForLongWordsWidthAndLargeText() async throws {
        try await loadSuggestions(["tomorrow", "morning", "meeting", "please"])
        XCTAssertEqual(controller.suggestionButtons.filter { !$0.isHidden }.count, 3)
        controller.view.frame.size.width = 844
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.suggestionButtons.filter { !$0.isHidden }.count, 4)
        let fourth = controller.suggestionButtons[3]
        fourth.sendActions(for: .touchDown)
        controller.view.frame.size.width = 320
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        fourth.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "")
        XCTAssertLessThan(controller.suggestionButtons.filter { !$0.isHidden }.count, 4)
        XCTAssertTrue(fourth.isHidden)
        let originalSize = try XCTUnwrap(controller.suggestionButtons.first?.titleLabel?.font.pointSize)
        controller.view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        controller.view.updateTraitsIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let visible = controller.suggestionButtons.filter { !$0.isHidden }
        XCTAssertLessThanOrEqual(visible.count, 3)
        XCTAssertTrue(visible.allSatisfy { $0.bounds.width >= 44 })
        XCTAssertGreaterThan(try XCTUnwrap(visible.first?.titleLabel?.font.pointSize), originalSize)
        XCTAssertTrue(visible.allSatisfy { ($0.titleLabel?.font.lineHeight ?? 0) <= $0.bounds.height })
    }

    private func loadSuggestions(_ words: [String], context: String = "") async throws {
        controller.neuralService = NeuralPredictionService(bundle: Bundle(for: Self.self)) { _, _ in
            FixedSuggestionModel(words)
        }
        controller.storage.neuralPrediction = true
        controller.demoText = context
        controller.textDidChange(nil)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.neuralEngine == "Fixed suggestion test"
        }, object: nil)
        await fulfillment(of: [updated], timeout: 3)
        controller.view.layoutIfNeeded()
    }

    func testCorrectionStaysVisibleAfterNeuralUpdateAndTapReplacesTheToken() async throws {
        let started = expectation(description: "Correction candidates reach the model")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        controller.neuralService = NeuralPredictionService { _, _ in
            CorrectionCandidateModel(started: started, gate: gate)
        }
        controller.storage.neuralPrediction = true
        controller.demoText = "only seeing AI generated atuff"
        controller.textDidChange(nil)
        XCTAssertTrue(controller.suggestionButtons.contains { $0.currentTitle == "stuff" })
        await fulfillment(of: [started], timeout: 3)
        gate.signal()
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.neuralEngine == "Correction candidate test"
        }, object: nil)
        await fulfillment(of: [updated], timeout: 3)
        let button = try XCTUnwrap(controller.suggestionButtons.first { $0.currentTitle == "stuff" })
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "only seeing AI generated stuff ")
    }

    func testSplitRepairSurvivesNeuralRefreshAndTapPreservesTheDocument() async throws {
        let proxy = TestDocumentProxy()
        proxy.text = "Please send Birtgcertificate"
        proxy.autocorrectionType = .yes
        proxy.after = "tomorrow"
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.storage.learning = true
        controller.view.frame.size.width = 320
        controller.neuralService = NeuralPredictionService { _, _ in FixedSuggestionModel(["birth", "certificate"]) }
        controller.storage.neuralPrediction = true
        controller.textDidChange(nil)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.suggestionButtons.filter { !$0.isHidden }.dropFirst().first?.currentTitle, "Birth certificate")
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.neuralEngine == "Fixed suggestion test"
        }, object: nil)
        await fulfillment(of: [updated], timeout: 3)
        controller.view.layoutIfNeeded()
        let button = try XCTUnwrap(controller.suggestionButtons.first { !$0.isHidden && $0.currentTitle == "Birth certificate" })
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(proxy.text, "Please send Birth certificate ")
        XCTAssertEqual(proxy.after, "tomorrow")
        key(".")
        XCTAssertEqual(proxy.text, "Please send Birth certificate.")
        XCTAssertEqual(proxy.after, "tomorrow")
        controller.viewWillDisappear(false)
        XCTAssertNil(controller.storage.multilingualMemory.words["birth certificate"])
    }

    func testProtectedJoinedTokenDoesNotReceiveSplitRepairs() {
        controller.storage.setProtected("birtgcertificate", enabled: true)
        controller.demoText = "Birtgcertificate"
        controller.textDidChange(nil)
        XCTAssertFalse(controller.suggestionButtons.contains { $0.currentTitle == "Birth certificate" })
        controller.storage.setProtected("birtgcertificate", enabled: false)
        controller.textDidChange(nil)
        XCTAssertTrue(controller.suggestionButtons.contains { $0.currentTitle == "Birth certificate" })
    }

    func testProtectedWordsBlockRepairsAndLearnedTyposKeepManualRepairs() {
        controller.storage.learning = true
        controller.storage.setProtected("atuff", enabled: true)
        controller.demoText = "we are seeing atuff"
        controller.textDidChange(nil)
        XCTAssertFalse(controller.suggestionButtons.contains { $0.currentTitle == "stuff" })
        key("space")
        controller.storage.setProtected("atuff", enabled: false)
        controller.demoText = "we are seeing atuff"
        controller.textDidChange(nil)
        XCTAssertTrue(controller.suggestionButtons.contains { $0.currentTitle == "stuff" })
        XCTAssertEqual(controller.suggestionButtons.first?.currentTitle, "atuff")
        key("space")
        XCTAssertEqual(controller.context, "we are seeing atuff ")
    }

    func testScreenshotRepairsStayVisibleAndReplaceTheToken() async throws {
        for (context, expected) in [("Ek ken die chuck vleis. Dis cheaoer", "cheaper"),
                                    ("Klnk", "Klink"), ("Blckchan", "Blockchain")] {
            controller.storage.neuralPrediction = false
            controller.demoText = context
            controller.textDidChange(nil)
            controller.view.layoutIfNeeded()
            XCTAssertTrue(controller.suggestionButtons.contains { !$0.isHidden && $0.currentTitle == expected }, context)
            if context == "Klnk" {
                try await loadSuggestions(["kink"], context: context)
                XCTAssertTrue(controller.suggestionButtons.contains { !$0.isHidden && $0.currentTitle == expected })
            }
            let button = try XCTUnwrap(controller.suggestionButtons.first { !$0.isHidden && $0.currentTitle == expected })
            button.sendActions(for: .touchDown)
            button.sendActions(for: .touchUpInside)
            let prefix = String(context.dropLast(TextRules.token(before: context).count))
            XCTAssertEqual(controller.context, prefix + expected + " ")
        }
    }

    func testCursorContextEditRejectsTheOldNextWordResult() async {
        let started = expectation(description: "Old context starts")
        let finished = expectation(description: "Old context finishes")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let oldService = NeuralPredictionService { _, _ in
            DelayedCapitalizationModel(started: started, gate: gate, finished: finished)
        }
        controller.neuralService = oldService
        controller.storage.neuralPrediction = true
        controller.demoText = "we should "
        controller.textDidChange(nil)
        await fulfillment(of: [started], timeout: 2)
        controller.neuralService = NeuralPredictionService { _, _ in FixedSuggestionModel(["coffee"]) }
        controller.demoText = "let us "
        controller.textDidChange(nil)
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.suggestionButtons.contains { $0.currentTitle == "zebra" }
        }, object: nil)
        stale.isInverted = true
        gate.signal()
        await fulfillment(of: [finished, stale], timeout: 0.3)
        let current = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.suggestionButtons.first?.currentTitle == "coffee"
        }, object: nil)
        await fulfillment(of: [current], timeout: 3)
        XCTAssertEqual(controller.suggestionButtons.first?.currentTitle, "coffee")
        oldService.clear()
    }

    func testLearningAValidWordKeepsItsContractionAvailable() {
        controller.storage.learning = true
        controller.demoText = "its"
        key("space")
        controller.switchLanguage()
        XCTAssertEqual(controller.storage.multilingualMemory.words["its"], 1)
        controller.demoText = "its"
        controller.textDidChange(nil)
        XCTAssertEqual(controller.suggestionButtons.first?.currentTitle, "its")
        XCTAssertEqual(controller.suggestionButtons.dropFirst().first?.currentTitle, "it's")
        controller.storage.setProtected("its", enabled: true)
        controller.textDidChange(nil)
        XCTAssertFalse(controller.suggestionButtons.contains { $0.currentTitle == "it's" })
        let spelling = MultilingualSpelling()
        XCTAssertEqual(spelling.automaticCorrection("youve", candidates: spelling.contractions("youve", language: .english)), "you've")
        controller.storage.setProtected("youve", enabled: true)
        controller.demoText = "youve"
        key("space")
        controller.switchLanguage()
        XCTAssertEqual(controller.storage.multilingualMemory.words["youve"], 1)
        controller.storage.setProtected("youve", enabled: false)
        controller.demoText = "youve"
        controller.textDidChange(nil)
        XCTAssertTrue(controller.suggestionButtons.contains { $0.currentTitle == "you've" })
        key("space")
        XCTAssertEqual(controller.context, "youve ")
    }

    override func setUp() async throws {
        suite = "SimpleKeyboardInteractionTests." + UUID().uuidString
        controller = KeyboardViewController()
        controller.demoMode = true
        controller.storage = KeyboardStorage(defaults: UserDefaults(suiteName: suite)!)
        controller.storage.neuralPrediction = false
        controller.loadViewIfNeeded()
        controller.beginAppearanceTransition(true, animated: false)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: KeyboardLayout.height(compact: false))
        controller.view.layoutIfNeeded()
        controller.endAppearanceTransition()
    }

    override func tearDown() async throws {
        controller.viewWillDisappear(false)
        controller = nil
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func key(_ key: String) {
        controller.type(KeyHit(key: key, point: .zero, frame: CGRect(x: 0, y: 0, width: 30, height: 45)))
    }

    func testDeleteDragPreviewsCancelsAndRestoresWithoutLearning() throws {
        controller.storage.learning = true
        controller.demoText = "one two three "
        controller.textDidChange(nil)
        let hit = try physicalHit("delete")
        controller.plane.beginDeletePress(hit)
        XCTAssertEqual(controller.context, "one two three ")
        controller.plane.moveDeletePress(to: CGPoint(x: hit.point.x - 48, y: hit.point.y))
        XCTAssertTrue(controller.deletionLabel.text?.hasPrefix("Delete 2 words:") == true)
        XCTAssertEqual(controller.context, "one two three ")
        controller.plane.moveDeletePress(to: hit.point)
        XCTAssertEqual(controller.deletionLabel.text, "Release to cancel")
        controller.plane.endDeletePress()
        XCTAssertEqual(controller.context, "one two three ")
        controller.plane.beginDeletePress(hit)
        controller.plane.moveDeletePress(to: CGPoint(x: hit.point.x - 48, y: hit.point.y))
        controller.plane.endDeletePress()
        XCTAssertEqual(controller.context, "one ")
        XCTAssertFalse(controller.restoreButton.isHidden)
        controller.restoreButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "one two three ")
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(controller.storage.multilingualMemory.pairs.isEmpty)
        XCTAssertTrue(controller.storage.touches(profile: try XCTUnwrap(controller.activeTouchProfile)).offsets.isEmpty)
    }

    func testDeleteTapHoldAndOverlappingInputKeepTheirOrder() throws {
        let plane = controller.plane
        controller.demoText = "send teh"
        key("space")
        plane.beginDeletePress(try physicalHit("delete"))
        XCTAssertEqual(controller.context, "send the ")
        plane.endDeletePress()
        XCTAssertEqual(controller.context, "send teh")
        plane.beginDeletePress(try physicalHit("delete"))
        plane.startDeleteRepeat()
        XCTAssertEqual(controller.context, "send te")
        plane.moveDeletePress(to: .zero)
        plane.endDeletePress()
        XCTAssertEqual(controller.context, "send te")
        controller.demoText = "word "
        controller.textDidChange(nil)
        plane.beginPress(try physicalHit("e"))
        plane.beginDeletePress(try physicalHit("delete"))
        plane.endDeletePress()
        XCTAssertEqual(controller.context, "word ")
        controller.demoText = "word e"
        controller.textDidChange(nil)
        let space = try physicalHit("space")
        plane.beginKey(space)
        plane.beginDeletePress(try physicalHit("delete"))
        plane.endDeletePress()
        plane.endSpace(at: space.point)
        XCTAssertEqual(controller.context, "word e")
    }

    func testBulkDeleteAndRestoreRejectChangedHostState() {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for change in 0..<4 {
            proxy.text = "first second third "
            proxy.after = ""
            proxy.selection = nil
            controller.textDidChange(nil)
            XCTAssertTrue(controller.beginWordDeletion())
            controller.previewWordDeletion(1)
            controller.commitWordDeletion()
            XCTAssertEqual(proxy.text, "first second ")
            if change == 0 { proxy.documentIdentifier = UUID() }
            if change == 1 { proxy.selection = "selected" }
            if change == 2 { proxy.after = "changed" }
            if change == 3 { proxy.text = "other text " }
            let text = proxy.text
            controller.restoreDeletedText()
            XCTAssertEqual(proxy.text, text)
        }
        proxy.text = "first second "
        proxy.selection = nil
        controller.textDidChange(nil)
        XCTAssertTrue(controller.beginWordDeletion())
        controller.previewWordDeletion(1)
        proxy.documentIdentifier = UUID()
        controller.commitWordDeletion()
        XCTAssertEqual(proxy.text, "first second ")
        proxy.contextAvailable = false
        XCTAssertFalse(controller.beginWordDeletion())
        proxy.contextAvailable = true
        proxy.selection = "second"
        XCTAssertFalse(controller.beginWordDeletion())
    }

    func testAccessibilityWordDeletionAndRotationCancelRestore() throws {
        controller.demoText = "one two "
        controller.textDidChange(nil)
        let delete = try XCTUnwrap(controller.plane.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }
            .first { $0.accessibilityLabel == "Delete" })
        let action = try XCTUnwrap(delete.accessibilityCustomActions?.first { $0.name == "Delete word" })
        XCTAssertEqual(action.actionHandler?(action), true)
        XCTAssertEqual(controller.context, "one ")
        controller.view.frame.size.width = 320
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.restoreDeletedText()
        XCTAssertEqual(controller.context, "one ")
    }

    func testCursorSpeedChangesDistanceWithoutInsertingSpace() throws {
        let plane = controller.plane
        var offsets: [Int] = []
        plane.onCursor = { offsets.append($0) }
        plane.cursorMovementEnabled = true
        let space = try physicalHit("space")
        for (speed, expected) in [(CursorSpeed.slow, 2), (.standard, 3), (.fast, 4)] {
            offsets = []
            plane.cursorSpeed = speed
            plane.beginKey(space)
            plane.moveSpace(to: CGPoint(x: space.point.x + 36, y: space.point.y))
            plane.endSpace(at: space.point)
            XCTAssertEqual(offsets, [expected])
            XCTAssertEqual(controller.context, "")
        }
    }

    func testPrivateTypingPreservesPendingNormalDataAndIsolatesNewInput() throws {
        controller.storage.learning = true
        controller.selectSuggestion("hedging")
        controller.plane.touchModel.learn(key: "a", x: 0.1, y: 0)
        controller.storage.recordEmoji("\u{1F431}")
        controller.storage.setProtected("teh", enabled: true)
        let profile = try XCTUnwrap(controller.activeTouchProfile)
        controller.setPrivateTyping(true)
        controller.view.layoutIfNeeded()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let baseline = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        XCTAssertTrue(controller.isPrivateTyping)
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        XCTAssertFalse(controller.privateIndicator.isHidden)
        XCTAssertFalse(controller.settingsPanel.learningSwitch.isEnabled)
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        key("space")
        XCTAssertEqual(controller.context, "send teh ")
        controller.selectSuggestion("blorf")
        controller.showEmoji()
        controller.view.layoutIfNeeded()
        XCTAssertFalse(controller.privateIndicator.isHidden)
        controller.selectEmoji("\u{1F600}")
        controller.startEmojiSearch()
        controller.view.layoutIfNeeded()
        XCTAssertFalse(controller.privateIndicator.isHidden)
        controller.hideEmoji()
        controller.showSettings()
        controller.settingsPanel.learningSwitch.isOn = false
        controller.settingsPanel.learningSwitch.sendActions(for: .valueChanged)
        XCTAssertTrue(controller.storage.learning)
        controller.hideSettings()
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(defaults.persistentDomain(forName: suite))).isEqual(to: baseline))
        controller.setPrivateTyping(false)
        XCTAssertEqual(controller.storage.multilingualMemory.words["hedging"], 1)
        XCTAssertNil(controller.storage.multilingualMemory.words["blorf"])
        XCTAssertEqual(controller.storage.touches(profile: profile).offsets["a"]?.count, 1)
        XCTAssertEqual(controller.storage.emojiUsage.ranked.first?.text, "\u{1F431}")
        XCTAssertTrue(controller.storage.learning)
    }

    func testPrivateTypingEndsOnDismissalAndKeepsLearningPreference() {
        for learning in [true, false] {
            controller.storage.learning = learning
            controller.setPrivateTyping(true)
            controller.demoText = "private "
            controller.textDidChange(nil)
            controller.selectSuggestion("blorf")
            controller.viewWillDisappear(false)
            XCTAssertFalse(controller.isPrivateTyping)
            XCTAssertEqual(controller.storage.learning, learning)
            XCTAssertNil(controller.storage.multilingualMemory.words["blorf"])
            controller.viewWillAppear(false)
        }
    }

    private func checkDelayedSuggestionPress(_ action: String) async throws {
        let started = expectation(description: "Delayed prediction starts")
        let gate = DispatchSemaphore(value: 0)
        controller.neuralService = NeuralPredictionService { _, _ in DelayedCapitalizationModel(started: started, gate: gate) }
        controller.storage.neuralPrediction = true
        controller.demoText = "go "
        controller.textDidChange(nil)
        await fulfillment(of: [started], timeout: 2)
        let buttons = controller.suggestionButtons
        let titles = buttons.map { $0.title(for: .normal) }
        let word = try XCTUnwrap(titles[0])
        buttons[0].sendActions(for: .touchDown)
        gate.signal()
        let received = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.neuralEngine == "Delayed capitalization test"
        }, object: nil)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(buttons.map { $0.title(for: .normal) }, titles)
        controller.storage.neuralPrediction = false
        if action == "tap" {
            buttons[0].sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.context, "go " + word + " ")
        } else if action == "hold" {
            let option = try XCTUnwrap(buttons[0].accessibilityCustomActions?.first)
            XCTAssertEqual(option.actionHandler?(option), true)
            controller.protectWordButton.sendActions(for: .touchUpInside)
            buttons[0].sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.context, "go ")
            XCTAssertTrue(controller.storage.protectedWords.contains(word.lowercased()))
        } else {
            buttons[0].sendActions(for: .touchCancel)
            XCTAssertEqual(controller.context, "go ")
            XCTAssertTrue(buttons.contains { $0.title(for: .normal)?.lowercased() == "zebra" })
        }
    }

    func testSuggestionTapKeepsTheWordFromTouchDown() async throws { try await checkDelayedSuggestionPress("tap") }
    func testSuggestionHoldKeepsTheWordFromTouchDown() async throws { try await checkDelayedSuggestionPress("hold") }
    func testCancelledSuggestionPressShowsDeferredResults() async throws { try await checkDelayedSuggestionPress("cancel") }

    func testSuggestionPressRejectsNewDocumentAndPrivateModeChanges() throws {
        let proxy = TestDocumentProxy()
        proxy.text = "go "
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        let button = try XCTUnwrap(controller.suggestionButtons.first)
        button.sendActions(for: .touchDown)
        proxy.documentIdentifier = UUID()
        controller.textDidChange(nil)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(proxy.text, "go ")
        button.sendActions(for: .touchDown)
        controller.setPrivateTyping(true)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(proxy.text, "go ")
    }

    func testPhysicalDeleteDuringEmojiSearchOnlyChangesTheQuery() throws {
        controller.demoText = "host text"
        controller.showEmoji()
        controller.startEmojiSearch()
        for value in ["c", "a", "t"] { key(value) }
        let hit = try physicalHit("delete")
        controller.plane.beginDeletePress(hit)
        controller.plane.moveDeletePress(to: CGPoint(x: hit.point.x - 48, y: hit.point.y))
        controller.plane.endDeletePress()
        XCTAssertEqual(controller.emojiQuery, "ca")
        XCTAssertEqual(controller.context, "host text")
        XCTAssertTrue(controller.isSearchingEmoji)
    }

    func testCancelledPhysicalDeleteNeverDeletesOnRelease() throws {
        controller.demoText = "one two three "
        controller.textDidChange(nil)
        let hit = try physicalHit("delete")
        for drag in [false, true] {
            controller.plane.beginDeletePress(hit)
            if drag { controller.plane.moveDeletePress(to: CGPoint(x: hit.point.x - 48, y: hit.point.y)) }
            controller.plane.cancelDeletePress()
            controller.plane.endDeletePress()
            XCTAssertEqual(controller.context, "one two three ")
        }
    }

    func testDeleteRepeatTimerStartsAndStopsWithThePhysicalPress() async throws {
        controller.demoText = "abcdefgh"
        controller.textDidChange(nil)
        let repeated = expectation(description: "Delete repeats")
        var fulfilled = false
        controller.onDemoTextChange = { text in
            if text.count <= 6, !fulfilled { fulfilled = true; repeated.fulfill() }
        }
        controller.plane.beginDeletePress(try physicalHit("delete"))
        await fulfillment(of: [repeated], timeout: 2)
        controller.plane.endDeletePress()
        let stopped = expectation(description: "No deletion after release")
        stopped.isInverted = true
        controller.onDemoTextChange = { _ in stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 0.2)
    }

    func testHostChangesCancelPhysicalDeleteTapDragAndRepeat() throws {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for mode in 0..<3 {
            proxy.text = "first second third "
            proxy.documentIdentifier = UUID()
            controller.textDidChange(nil)
            let hit = try physicalHit("delete")
            controller.plane.beginDeletePress(hit)
            if mode == 1 { controller.plane.moveDeletePress(to: CGPoint(x: hit.point.x - 48, y: hit.point.y)) }
            if mode == 2 { controller.plane.startDeleteRepeat() }
            proxy.text = "new document"
            proxy.documentIdentifier = UUID()
            controller.textDidChange(nil)
            controller.plane.startDeleteRepeat()
            controller.plane.endDeletePress()
            XCTAssertEqual(proxy.text, "new document")
        }
        proxy.text = "first second "
        controller.textDidChange(nil)
        controller.plane.beginDeletePress(try physicalHit("delete"))
        proxy.documentIdentifier = UUID()
        controller.plane.endDeletePress()
        XCTAssertEqual(proxy.text, "first second ")
    }

    func testPrivateExitDoesNotLearnPrivateWordsOrPreviousWordContext() {
        controller.storage.learning = true
        for (index, partial) in [false, true].enumerated() {
            controller.setPrivateTyping(true)
            controller.demoText = partial ? "secretna" : "secretname "
            controller.textDidChange(nil)
            controller.setPrivateTyping(false)
            if partial { for value in ["m", "e", "space"] { key(value) } }
            for word in ["hello", "world"] {
                for character in word { key(String(character)) }
                key("space")
            }
            controller.viewWillDisappear(false)
            let memory = controller.storage.multilingualMemory
            XCTAssertNil(memory.words["secretname"])
            XCTAssertNil(memory.words["secretna"])
            XCTAssertNil(memory.pairs["secretname hello"])
            XCTAssertNil(memory.pairs["me hello"])
            XCTAssertEqual(memory.words["hello"], index + 1)
            XCTAssertEqual(memory.pairs["hello world"], index + 1)
            controller.viewWillAppear(false)
        }
    }

    func testPrivateTypingDiscardsAnAlreadyRunningNeuralResult() async {
        let started = expectation(description: "Old prediction starts")
        let finished = expectation(description: "Old prediction finishes")
        let gate = DispatchSemaphore(value: 0)
        controller.neuralService = NeuralPredictionService { _, _ in
            DelayedCapitalizationModel(started: started, gate: gate, finished: finished)
        }
        controller.storage.neuralPrediction = true
        controller.demoText = "go "
        controller.textDidChange(nil)
        await fulfillment(of: [started], timeout: 2)
        controller.storage.neuralPrediction = false
        controller.setPrivateTyping(true)
        controller.storage.neuralPrediction = true
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.neuralEngine == "Delayed capitalization test"
        }, object: nil)
        stale.isInverted = true
        gate.signal()
        await fulfillment(of: [finished, stale], timeout: 0.3)
        XCTAssertTrue(controller.isPrivateTyping)
        XCTAssertEqual(controller.neuralEngine, "Basic predictions")
        XCTAssertEqual(controller.context, "go ")
    }

    func testRefusedSuggestionTouchCannotAcceptARefreshedWord() throws {
        let proxy = TestDocumentProxy()
        proxy.text = "go "
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        let button = try XCTUnwrap(controller.suggestionButtons.first)
        proxy.documentIdentifier = UUID()
        button.sendActions(for: .touchDown)
        controller.textDidChange(nil)
        let options = try XCTUnwrap(button.accessibilityCustomActions?.first)
        XCTAssertEqual(options.actionHandler?(options), false)
        XCTAssertFalse(controller.isShowingWordOptions)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(proxy.text, "go ")
    }

    func testVisibleUndoRestoresOriginalAndExpiresAfterTyping() {
        controller.demoText = "send teh"
        key("space")
        XCTAssertEqual(controller.correctionLabel.text, "teh > the")
        XCTAssertFalse(controller.undoButton.superview!.isHidden)
        controller.undoButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "send teh")
        key("space")
        XCTAssertEqual(controller.context, "send teh ")
        XCTAssertTrue(controller.undoButton.superview!.isHidden)
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        key("space")
        key("x")
        let text = controller.context
        controller.undoCorrection()
        XCTAssertEqual(controller.context, text)
    }

    func testUndoRejectsChangedDocumentSelectionAndTrailingContext() {
        let proxy = TestDocumentProxy()
        proxy.autocorrectionType = .yes
        controller.documentProxy = proxy
        controller.demoMode = false
        for change in 0..<3 {
            proxy.text = "send teh"
            proxy.after = ""
            proxy.selection = nil
            controller.textDidChange(nil)
            key("space")
            XCTAssertEqual(proxy.text, "send the ")
            if change == 0 { proxy.documentIdentifier = UUID() }
            if change == 1 { proxy.selection = "selected" }
            if change == 2 { proxy.after = "new text" }
            controller.undoCorrection()
            XCTAssertEqual(proxy.text, "send the ")
        }
    }

    func testWordProtectionCanBeReversedAcrossLayoutChanges() {
        controller.storage.learning = true
        controller.showWordOptions("Teh")
        XCTAssertTrue(controller.isShowingWordOptions)
        XCTAssertNil(controller.presentedViewController)
        controller.protectWordButton.sendActions(for: .touchUpInside)
        controller.switchLanguage()
        controller.demoText = "send teh"
        key("space")
        XCTAssertEqual(controller.context, "send teh ")
        controller.showWordOptions("teh")
        XCTAssertEqual(controller.protectWordButton.title(for: .normal), "Allow correction")
        controller.protectWordButton.sendActions(for: .touchUpInside)
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        key("space")
        XCTAssertEqual(controller.context, "send the ")
    }

    func testSymbolDragCommitsOverlappingLetterAndSpaceInOrder() throws {
        let plane = controller.plane
        for pendingSpace in [false, true] {
            controller.demoText = pendingSpace ? "word e" : "word "
            controller.textDidChange(nil)
            if pendingSpace {
                let space = try physicalHit("space")
                plane.beginKey(space)
            } else {
                plane.beginPress(try physicalHit("e"))
            }
            let page = try physicalHit("page")
            XCTAssertTrue(plane.beginSymbolDrag(page))
            let number = try XCTUnwrap(plane.keys.first { $0.0 == "1" }?.1)
            plane.endSymbolDrag(at: CGPoint(x: number.midX, y: number.midY))
            XCTAssertEqual(controller.context, pendingSpace ? "word e 1" : "word e1")
            XCTAssertEqual(plane.page, 0)
        }
    }

    func testForgetWordCancelsPendingSaveAndKeepsOtherHistory() {
        controller.storage.learning = true
        controller.demoText = "hello "
        controller.selectSuggestion("blorf")
        controller.selectSuggestion("again")
        controller.showWordOptions("blorf")
        controller.forgetWordButton.sendActions(for: .touchUpInside)
        XCTAssertFalse(controller.isShowingWordOptions)
        controller.switchLanguage()
        controller.viewWillDisappear(false)
        XCTAssertNil(controller.storage.multilingualMemory.words["blorf"])
        XCTAssertNil(controller.storage.multilingualMemory.pairs["hello blorf"])
        XCTAssertNil(controller.storage.multilingualMemory.pairs["blorf again"])
        XCTAssertEqual(controller.storage.multilingualMemory.words["again"], 1)
        XCTAssertEqual(controller.context, "hello blorf again ")
    }

    func testClosingWordOptionsKeepsTextAndWordChoices() {
        controller.storage.learning = true
        controller.demoText = "hello "
        controller.selectSuggestion("blorf")
        controller.storage.setProtected("blorf", enabled: true)
        controller.showWordOptions("blorf")
        controller.hideWordOptions()
        XCTAssertEqual(controller.context, "hello blorf ")
        XCTAssertTrue(controller.storage.protectedWords.contains("blorf"))
        controller.viewWillDisappear(false)
        XCTAssertEqual(controller.storage.multilingualMemory.words["blorf"], 1)
        XCTAssertFalse(controller.isShowingWordOptions)
        XCTAssertFalse(controller.plane.isHidden)
    }

    func testSizeNumberRowAndHandChangesUseSeparateTouchProfiles() throws {
        let original = try XCTUnwrap(controller.activeTouchProfile)
        controller.plane.touchModel.learn(key: "a", x: 0.1, y: 0)
        controller.showSettings()
        controller.settingsPanel.sizeControl.selectedSegmentIndex = 2
        controller.settingsPanel.sizeControl.sendActions(for: .valueChanged)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.storage.keyboardSize, .tall)
        XCTAssertNotEqual(controller.activeTouchProfile, original)
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        controller.settingsPanel.numberRowSwitch.isOn = true
        controller.settingsPanel.numberRowSwitch.sendActions(for: .valueChanged)
        controller.settingsPanel.handControl.selectedSegmentIndex = 2
        controller.settingsPanel.handControl.sendActions(for: .valueChanged)
        controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.plane.numberRow)
        XCTAssertLessThan(controller.plane.bounds.width, controller.view.bounds.width)
        XCTAssertGreaterThan(controller.plane.frame.minX, 0)
        controller.hideSettings()
        key("7")
        XCTAssertEqual(controller.context, "7")
        controller.expandKeyboard()
        controller.showSettings()
        controller.settingsPanel.sizeControl.selectedSegmentIndex = 1
        controller.settingsPanel.numberRowSwitch.isOn = false
        controller.settingsPanel.sizeControl.sendActions(for: .valueChanged)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.activeTouchProfile, original)
        XCTAssertEqual(controller.plane.touchModel.offsets["a"]?.count, 1)
    }

    func testSymbolDragTapCancelAndOutsideRelease() throws {
        let plane = controller.plane
        func begin() throws -> CGPoint {
            let frame = try XCTUnwrap(plane.keys.first { $0.0 == "page" }?.1)
            let point = CGPoint(x: frame.midX, y: frame.midY)
            XCTAssertTrue(plane.beginSymbolDrag(KeyHit(key: "page", point: point, frame: frame)))
            XCTAssertEqual(plane.page, 1)
            return point
        }
        let origin = try begin()
        plane.endSymbolDrag(at: origin)
        XCTAssertEqual(plane.page, 1)
        XCTAssertEqual(controller.context, "")
        key("page")
        _ = try begin()
        let currency = try XCTUnwrap(plane.keys.first { $0.0 == "\u{20ac}" }?.1)
        plane.endSymbolDrag(at: CGPoint(x: currency.midX, y: currency.midY))
        XCTAssertEqual(controller.context, "\u{20ac}")
        XCTAssertEqual(plane.page, 0)
        _ = try begin()
        plane.endSymbolDrag(at: CGPoint(x: -30, y: -30))
        XCTAssertEqual(controller.context, "\u{20ac}")
        XCTAssertEqual(plane.page, 0)
        _ = try begin()
        plane.cancelSymbolDrag()
        plane.endSymbolDrag(at: .zero)
        XCTAssertEqual(plane.page, 0)
        XCTAssertEqual(controller.context, "\u{20ac}")
        key("h")
        XCTAssertEqual(controller.context, "\u{20ac}h")
    }

    func testNumberRowGeometryFitsBothLayoutsAndSymbolPages() {
        let plane = controller.plane
        plane.numberRow = true
        for width in [264.0, 320, 390, 844] {
            for language in KeyboardLanguage.allCases {
                plane.language = language
                for page in 0...2 {
                    plane.page = page
                    plane.frame = CGRect(x: 0, y: 0, width: width, height: 240)
                    plane.layoutIfNeeded()
                    for (key, frame) in plane.keys {
                        XCTAssertGreaterThan(frame.width, 0, key)
                        XCTAssertLessThanOrEqual(frame.maxX, width + 0.01, key)
                        XCTAssertLessThanOrEqual(frame.maxY, 240, key)
                        XCTAssertEqual(plane.hit(at: CGPoint(x: frame.midX, y: frame.midY))?.key, key)
                    }
                    if page == 0 {
                        XCTAssertEqual(plane.keys.filter { $0.0 == "1" }.count, 1)
                        XCTAssertEqual(plane.keys.first?.1.height, 48)
                    }
                }
            }
        }
        XCTAssertEqual(KeyboardLayout.height(compact: false, size: .tall, numberRow: true), 332)
        XCTAssertEqual(KeyboardLayout.height(compact: true, size: .compact), 180)
    }

    func testMissingCursorContextDoesNotCapitalizeMiddleSentenceInput() {
        let proxy = TestDocumentProxy()
        proxy.text = "We should "
        proxy.after = "meet tomorrow."
        proxy.autocapitalizationType = .sentences
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        XCTAssertFalse(controller.plane.shifted)
        proxy.contextAvailable = false
        controller.selectionWillChange(nil)
        controller.selectionDidChange(nil)
        XCTAssertFalse(controller.plane.shifted)
        key("x")
        XCTAssertEqual(proxy.text, "We should x")
        XCTAssertEqual(proxy.after, "meet tomorrow.")
    }

    func testCursorInsertionRefreshesAutomaticShiftBeforeTheKey() {
        let proxy = TestDocumentProxy()
        proxy.autocapitalizationType = .sentences
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        XCTAssertTrue(controller.plane.shifted)
        proxy.text = "We should "
        proxy.after = "meet tomorrow."
        key("x")
        XCTAssertEqual(proxy.text, "We should x")
    }

    func testCursorInsertionCanEnableSentenceShiftAndKeepsLiteralChoices() {
        let proxy = TestDocumentProxy()
        proxy.text = "we should "
        proxy.autocapitalizationType = .sentences
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        XCTAssertFalse(controller.plane.shifted)
        proxy.text = "Done. "
        key("x")
        XCTAssertEqual(proxy.text, "Done. X")
        proxy.text = "Done. "
        controller.type(KeyHit(key: "\u{00df}", point: .zero, frame: .zero, physical: false, literal: true))
        XCTAssertEqual(proxy.text, "Done. \u{00df}")
    }

    func testHostCapitalizationModesAndSelectedWordReplacement() {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for (mode, before, after, expected) in [(UITextAutocapitalizationType.none, "", "", "a"),
                                                (.sentences, "we ", "should meet", "we a"),
                                                (.sentences, "", "existing text", "A"),
                                                (.words, "we ", "should meet", "we A"),
                                                (.words, "wo", "rd", "woa"),
                                                (.allCharacters, "we ", "should meet", "we A")] {
            proxy.autocapitalizationType = mode
            proxy.text = before
            proxy.after = after
            proxy.selection = "old"
            controller.selectionDidChange(nil)
            key("a")
            XCTAssertEqual(proxy.text, expected)
            XCTAssertNil(proxy.selection)
            XCTAssertEqual(proxy.after, after)
        }
    }

    func testCursorMoveClearsOneShotShiftButKeepsExplicitCapsLock() {
        controller.now = { Date(timeIntervalSince1970: 100) }
        let proxy = TestDocumentProxy()
        proxy.text = "we "
        proxy.autocapitalizationType = .sentences
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        key("shift")
        key("a")
        XCTAssertEqual(proxy.text, "we A")
        key("b")
        XCTAssertEqual(proxy.text, "we Ab")
        key("shift")
        proxy.text = "another "
        controller.selectionWillChange(nil)
        controller.selectionDidChange(nil)
        XCTAssertFalse(controller.plane.shifted)
        key("c")
        XCTAssertEqual(proxy.text, "another c")
        controller.plane.capsLocked = true
        controller.plane.shifted = true
        proxy.text = "middle "
        controller.selectionWillChange(nil)
        controller.selectionDidChange(nil)
        key("x")
        XCTAssertEqual(proxy.text, "middle X")
    }

    func testCapsLockRequiresConsecutiveShiftTaps() {
        controller.now = { Date(timeIntervalSince1970: 100) }
        controller.demoText = "word "
        controller.textDidChange(nil)
        key("shift")
        key("a")
        key("shift")
        XCTAssertFalse(controller.plane.capsLocked)
        key("b")
        XCTAssertEqual(controller.context, "word AB")
        key("shift")
        key("shift")
        XCTAssertTrue(controller.plane.capsLocked)
        key("c")
        XCTAssertEqual(controller.context, "word ABC")
        key("shift")
        controller.selectSuggestion("hello")
        key("shift")
        XCTAssertFalse(controller.plane.capsLocked)
        key("d")
        XCTAssertEqual(controller.context, "word hello D")
    }

    func testNewDocumentClearsStaleManualShiftWithTheSameText() {
        let proxy = TestDocumentProxy()
        proxy.text = "we "
        proxy.autocapitalizationType = .sentences
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        key("shift")
        proxy.documentIdentifier = UUID()
        controller.textDidChange(nil)
        XCTAssertFalse(controller.plane.shifted)
        key("x")
        XCTAssertEqual(proxy.text, "we x")
    }

    func testDelayedNeuralSuggestionUsesTheCurrentCursorCapitalization() async {
        let started = expectation(description: "Prediction starts at an empty field")
        let gate = DispatchSemaphore(value: 0)
        controller.neuralService = NeuralPredictionService { _, _ in DelayedCapitalizationModel(started: started, gate: gate) }
        controller.storage.neuralPrediction = true
        let proxy = TestDocumentProxy()
        proxy.autocapitalizationType = .sentences
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        await fulfillment(of: [started], timeout: 2)
        proxy.text = "existing sentence"
        proxy.contextAvailable = false
        controller.selectionWillChange(nil)
        XCTAssertFalse(controller.plane.shifted)
        func labels(_ view: UIView) -> [String] {
            (view as? UIButton).flatMap { $0.accessibilityLabel }.map { [$0] } ?? view.subviews.flatMap(labels)
        }
        let received = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let values = labels(controller.view)
            return values.contains("Insert zebra") || values.contains("Insert Zebra")
        }, object: nil)
        gate.signal()
        await fulfillment(of: [received], timeout: 2)
        XCTAssertTrue(labels(controller.view).contains("Insert zebra"))
        XCTAssertFalse(labels(controller.view).contains("Insert Zebra"))
        XCTAssertFalse(controller.plane.shifted)
    }

    func testAlternatePressCommitsOnlyTheSelectedCharacter() throws {
        controller.demoText = "x"
        controller.textDidChange(nil)
        let plane = controller.plane
        let frame = try XCTUnwrap(plane.keys.first { $0.0 == "u" }?.1)
        let hit = KeyHit(key: "u", point: CGPoint(x: frame.midX, y: frame.midY), frame: frame)
        plane.beginPress(hit)
        XCTAssertEqual(controller.context, "x")
        plane.endPress(at: hit.point)
        XCTAssertEqual(controller.context, "xu")
        plane.beginPress(hit)
        plane.showAlternates()
        let index = try XCTUnwrap(plane.alternateOptions.firstIndex(of: "\u{00fc}"))
        let menu = plane.alternateFrame
        let point = CGPoint(x: menu.minX + (CGFloat(index) + 0.5) * menu.width / CGFloat(plane.alternateOptions.count), y: menu.midY)
        plane.endPress(at: point)
        XCTAssertEqual(controller.context, "xu\u{00fc}")
        plane.beginPress(hit)
        plane.showAlternates()
        plane.endPress(at: CGPoint(x: -100, y: -100))
        XCTAssertEqual(controller.context, "xu\u{00fc}")
        plane.beginPress(hit)
        plane.cancelPress()
        plane.endPress(at: hit.point)
        XCTAssertEqual(controller.context, "xu\u{00fc}")
    }

    func testPunctuationHoldDefaultsToTheOtherKeyAcrossWidthsPagesAndTouchPositions() throws {
        let plane = controller.plane
        for width in [264.0, 390, 844] {
            plane.frame = CGRect(x: 0, y: 0, width: width, height: 192)
            plane.layoutIfNeeded()
            for page in [0, 1, 2] {
                plane.page = page
                for (value, expected) in [(".", ","), (",", ".")] {
                    let frames = plane.keys.filter { $0.0 == value }.map { $0.1 }
                    XCTAssertFalse(frames.isEmpty)
                    for frame in frames {
                        for offset in [-0.4, 0, 0.4] {
                            for moved in [false, true] {
                                controller.demoText = "word"
                                controller.textDidChange(nil)
                                let point = CGPoint(x: frame.midX + frame.width * offset, y: frame.midY)
                                let start = moved ? CGPoint(x: frame.midX, y: frame.midY) : point
                                plane.beginPress(KeyHit(key: value, point: start, frame: frame))
                                if moved { plane.movePress(to: point) }
                                plane.showAlternates()
                                let index = try XCTUnwrap(plane.alternateIndex)
                                XCTAssertEqual(plane.alternateOptions[index], expected)
                                XCTAssertGreaterThanOrEqual(plane.alternateFrame.minX, 0)
                                XCTAssertLessThanOrEqual(plane.alternateFrame.maxX, width)
                                plane.endPress(at: point)
                                XCTAssertEqual(controller.context, "word" + expected)
                            }
                        }
                    }
                }
            }
        }
    }

    func testPunctuationMenusKeepSlideSelectionCancellationAndNormalTaps() throws {
        let plane = controller.plane
        for value in [",", "."] {
            controller.demoText = "word"
            controller.textDidChange(nil)
            let hit = try physicalHit(value)
            plane.beginPress(hit)
            plane.endPress(at: hit.point)
            XCTAssertEqual(controller.context, "word" + value)
            for selected in AlternateCharacters.options(for: value) {
                plane.beginPress(hit)
                plane.showAlternates()
                let index = try XCTUnwrap(plane.alternateOptions.firstIndex(of: selected))
                let menu = plane.alternateFrame
                let point = CGPoint(x: menu.minX + (CGFloat(index) + 0.5) * menu.width / CGFloat(plane.alternateOptions.count), y: menu.midY)
                let before = controller.context
                plane.endPress(at: point)
                XCTAssertEqual(controller.context, before + selected)
            }
            let before = controller.context
            plane.beginPress(hit)
            plane.showAlternates()
            plane.endPress(at: CGPoint(x: -100, y: -100))
            XCTAssertEqual(controller.context, before)
            XCTAssertTrue(controller.alternatePopup.isHidden)
        }
    }

    func testShiftedSharpSMenuInsertsTheExactSelectedGlyph() throws {
        for selected in ["\u{00df}", "\u{1e9e}"] {
            controller.hideEmoji()
            controller.demoText = "word "
            controller.textDidChange(nil)
            controller.plane.shifted = true
            let plane = controller.plane
            let frame = try XCTUnwrap(plane.keys.first { $0.0 == "s" }?.1)
            plane.beginPress(KeyHit(key: "s", point: CGPoint(x: frame.midX, y: frame.midY), frame: frame))
            plane.showAlternates()
            let index = try XCTUnwrap(plane.alternateOptions.firstIndex(of: selected))
            let menu = plane.alternateFrame
            plane.endPress(at: CGPoint(x: menu.minX + (CGFloat(index) + 0.5) * menu.width / CGFloat(plane.alternateOptions.count), y: menu.midY))
            XCTAssertEqual(controller.context, "word " + selected)
        }
    }

    func testLiteralAlternativesPreserveCaseAndShiftRulesInTypingAndSearch() {
        for search in [false, true] {
          for capsLock in [false, true] {
            controller.hideEmoji()
            controller.demoText = "word "
            controller.textDidChange(nil)
            if search { controller.showEmoji(); controller.startEmojiSearch() }
            controller.plane.shifted = true
            controller.plane.capsLocked = capsLock
            controller.type(KeyHit(key: "\u{00df}", point: .zero, frame: .zero, physical: false, literal: true))
            XCTAssertEqual(controller.plane.shifted, capsLock)
            key("a")
            let expected = "\u{00df}" + (capsLock ? "A" : "a")
            if search {
                XCTAssertEqual(controller.emojiQuery, expected)
                XCTAssertEqual(controller.context, "word ")
            } else { XCTAssertEqual(controller.context, "word " + expected) }
          }
        }
    }

    func testShiftedGermanSharpSKeyAndAccessibilityUseTheCapitalGlyph() throws {
        controller.storage.language = .german
        controller.viewWillAppear(false)
        controller.demoText = "word "
        controller.textDidChange(nil)
        key("shift")
        let elements = controller.plane.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement } ?? []
        let sharpS = try XCTUnwrap(elements.first { $0.accessibilityLabel == "\u{1e9e}" })
        XCTAssertFalse(elements.contains { $0.accessibilityLabel == "SS" })
        XCTAssertTrue(sharpS.accessibilityActivate())
        XCTAssertEqual(controller.context, "word \u{1e9e}")
        controller.plane.shifted = true
        let shiftedS = try XCTUnwrap(controller.plane.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }.first { $0.accessibilityLabel == "S" })
        let actions = shiftedS.accessibilityCustomActions?.map(\.name) ?? []
        XCTAssertTrue(actions.contains("Insert \u{00df}"))
        XCTAssertTrue(actions.contains("Insert \u{1e9e}"))
    }

    func testShiftedAccentsAndSymbolMenusFitNarrowKeyboards() throws {
        let plane = controller.plane
        for width in [264.0, 390, 844] {
            plane.frame = CGRect(x: 0, y: 0, width: width, height: 144)
            plane.layoutIfNeeded()
            for value in ["e", ",", "."] {
                let frame = try XCTUnwrap(plane.keys.last { $0.0 == value }?.1)
                plane.shifted = true
                plane.beginPress(KeyHit(key: value, point: CGPoint(x: frame.midX, y: frame.midY), frame: frame))
                plane.showAlternates()
                XCTAssertGreaterThanOrEqual(plane.alternateFrame.minX, 0)
                XCTAssertLessThanOrEqual(plane.alternateFrame.maxX, width)
                XCTAssertGreaterThanOrEqual(plane.alternateFrame.minY, -plane.alternateTopInset)
                let index = value == "e" ? 2 : 0
                let selected = plane.alternateOptions[index]
                let menu = plane.alternateFrame
                let point = CGPoint(x: menu.minX + (CGFloat(index) + 0.5) * menu.width / CGFloat(plane.alternateOptions.count), y: menu.midY)
                let before = controller.context
                plane.endPress(at: point)
                XCTAssertEqual(controller.context, before + selected)
                if value == "e" { XCTAssertEqual(selected, "\u{00ca}") }
            }
        }
    }

    func testSpaceAndDeferredVowelKeepInputOrder() throws {
        controller.demoText = "word"
        controller.textDidChange(nil)
        let plane = controller.plane
        func hit(_ key: String) throws -> KeyHit {
            let frame = try XCTUnwrap(plane.keys.first { $0.0 == key }?.1)
            return KeyHit(key: key, point: CGPoint(x: frame.midX, y: frame.midY), frame: frame)
        }
        let space = try hit("space"), vowel = try hit("a"), second = try hit("e")
        plane.beginKey(space)
        plane.beginPress(vowel)
        plane.endSpace(at: space.point)
        plane.beginPress(second)
        plane.endPress(at: second.point)
        XCTAssertEqual(controller.context, "word ae")
    }

    func testEmojiSearchKeepsTheQueryOutOfTheDocumentAndLearning() throws {
        controller.demoText = "hello "
        controller.showEmoji()
        controller.startEmojiSearch()
        for value in ["c", "a", "x", "delete", "t"] { key(value) }
        XCTAssertEqual(controller.emojiQuery, "cat")
        XCTAssertEqual(controller.context, "hello ")
        let cat = try XCTUnwrap(controller.emojiResults.results.first { $0.text == "\u{1F431}" })
        controller.selectEmoji(cat.text)
        controller.selectEmoji(cat.text)
        XCTAssertEqual(controller.context, "hello " + cat.text)
        XCTAssertFalse(controller.isShowingEmoji)
        controller.showEmoji()
        controller.startEmojiSearch()
        controller.clearEmojiSearch()
        XCTAssertEqual(controller.emojiQuery, "")
        for value in ["n", "o", "m", "a", "t", "c", "h", "q", "u", "e", "r", "y"] { key(value) }
        XCTAssertTrue(controller.emojiResults.results.isEmpty)
        key("return")
        XCTAssertFalse(controller.isSearchingEmoji)
        XCTAssertFalse(controller.isShowingEmoji)
        key("delete")
        XCTAssertEqual(controller.context, "hello ")
        key("a")
        XCTAssertEqual(controller.context, "hello a")
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testHostEmojiSearchAndCompoundEmojiDeletion() throws {
        let proxy = TestDocumentProxy()
        proxy.text = "hello "
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.showEmoji()
        controller.startEmojiSearch()
        for value in ["f", "l", "a", "g", "space", "g", "e", "r", "m", "a", "n", "y"] { key(value) }
        XCTAssertEqual(proxy.text, "hello ")
        let flag = try XCTUnwrap(controller.emojiResults.results.first)
        controller.selectEmoji(flag.text)
        controller.hideEmoji()
        XCTAssertEqual(proxy.text, "hello " + flag.text)
        key("delete")
        XCTAssertEqual(proxy.text, "hello ")
        controller.showEmoji()
        controller.startEmojiSearch()
        XCTAssertEqual(controller.emojiSearch.accessibilityValue, "Empty")
        key("c")
        XCTAssertEqual(controller.emojiSearch.accessibilityValue, "c")
        controller.hideEmoji()
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testEmojiModeClosesForSettingsAndReopensWithAnEmptyQuery() {
        controller.showEmoji()
        controller.startEmojiSearch()
        key("h")
        XCTAssertEqual(controller.emojiQuery, "h")
        XCTAssertEqual(controller.context, "")
        controller.showSettings()
        XCTAssertFalse(controller.isSearchingEmoji)
        XCTAssertTrue(controller.isShowingSettings)
        controller.hideSettings()
        controller.showEmoji()
        XCTAssertEqual(controller.emojiQuery, "")
        controller.viewWillDisappear(false)
        XCTAssertFalse(controller.isSearchingEmoji)
        XCTAssertFalse(controller.isShowingEmoji)
        XCTAssertEqual(controller.emojiSearch.accessibilityValue, "Empty")
    }

    func testEmojiBrowseSearchClearAndHistoryRemainSeparateFromTyping() {
        controller.demoText = "hello "
        controller.storage.learning = true
        controller.showEmoji()
        XCTAssertTrue(controller.isShowingEmoji)
        XCTAssertFalse(controller.isSearchingEmoji)
        XCTAssertTrue(controller.plane.isHidden)
        let smile = "\u{1F600}"
        controller.selectEmoji("not an emoji")
        XCTAssertTrue(controller.storage.emojiUsage.ranked.isEmpty)
        controller.selectEmoji(smile)
        controller.selectEmoji(smile)
        XCTAssertEqual(controller.context, "hello " + smile + smile)
        XCTAssertEqual(controller.storage.emojiUsage.ranked.first?.text, smile)
        XCTAssertTrue(controller.emojiSearch.accessibilityActivate())
        for value in ["c", "a", "t"] { key(value) }
        XCTAssertEqual(controller.emojiSearch.query, "cat")
        XCTAssertEqual(controller.context, "hello " + smile + smile)
        controller.clearEmojiSearch()
        XCTAssertTrue(controller.isSearchingEmoji)
        XCTAssertEqual(controller.emojiQuery, "")
        key("delete")
        XCTAssertEqual(controller.context, "hello " + smile + smile)
        controller.showEmojiBrowse()
        XCTAssertFalse(controller.isSearchingEmoji)
        controller.clearEmojiHistory()
        XCTAssertTrue(controller.storage.emojiUsage.ranked.isEmpty)
        controller.hideEmoji()
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testEmojiSearchBoundsLongQueriesAndRetainsCompoundSelections() {
        controller.showEmoji()
        controller.startEmojiSearch()
        for _ in 0..<100 { key("a") }
        XCTAssertEqual(controller.emojiQuery.count, 64)
        XCTAssertEqual(controller.emojiSearch.accessibilityValue?.count, 64)
        controller.clearEmojiSearch()
        for value in ["r", "a", "i", "n", "b", "o", "w"] { key(value) }
        let rainbow = "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"
        controller.selectEmoji(rainbow)
        controller.selectEmoji(rainbow)
        XCTAssertEqual(controller.context, rainbow)
        XCTAssertFalse(controller.isSearchingEmoji)
        XCTAssertEqual(controller.emojiQuery, "")
        XCTAssertEqual(controller.storage.emojiUsage.ranked.first?.text, rainbow)
        key("x")
        XCTAssertEqual(controller.context, rainbow + "x")
    }

    func testSearchCapsLockDoesNotChangeTypingAndGermanSearchUsesTheSameField() {
        controller.demoText = "word "
        controller.textDidChange(nil)
        controller.showEmoji()
        controller.startEmojiSearch()
        key("shift")
        key("shift")
        XCTAssertTrue(controller.plane.capsLocked)
        key("h")
        controller.hideEmoji()
        XCTAssertFalse(controller.plane.capsLocked)
        key("a")
        XCTAssertEqual(controller.context, "word a")
        controller.showEmoji()
        controller.startEmojiSearch()
        key("language")
        for value in ["k", "a", "t", "z", "e"] { key(value) }
        XCTAssertEqual(controller.emojiQuery, "katze")
        XCTAssertTrue(controller.emojiResults.results.contains { $0.text == "\u{1F431}" })
        XCTAssertEqual(controller.context, "word a")
    }

    func testSearchFieldOwnsFocusAndReleasesItForAnotherField() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        let search = EmojiSearchControl(frame: CGRect(x: 0, y: 100, width: 300, height: 44))
        let message = UITextField(frame: CGRect(x: 0, y: 40, width: 300, height: 44))
        message.inputView = UIView(frame: .zero)
        root.view.addSubview(search)
        root.view.addSubview(message)
        var losses = 0
        search.onFocusLost = { losses += 1 }
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        search.focus()
        XCTAssertTrue(search.hasFocus)
        XCTAssertTrue(message.becomeFirstResponder())
        XCTAssertFalse(search.hasFocus)
        XCTAssertEqual(losses, 1)
        message.resignFirstResponder()
    }

    func testMissingHostDocumentIdentifierStillAllowsTypingAndSearch() {
        final class MissingIdentifierProxy: TestDocumentProxy {
            override func value(forKey key: String) -> Any? {
                key == "documentIdentifier" ? nil : super.value(forKey: key)
            }
        }
        let proxy = MissingIdentifierProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        key("a")
        controller.showEmoji()
        controller.startEmojiSearch()
        key("c")
        XCTAssertEqual(controller.emojiQuery, "c")
        XCTAssertEqual(proxy.text, "a")
        proxy.text = "changed"
        controller.textDidChange(nil)
        XCTAssertFalse(controller.isShowingEmoji)
        key("x")
        XCTAssertEqual(proxy.text, "changedx")
    }

    func testHostChangesExitSearchButUnchangedCallbacksKeepItOpen() {
        let proxy = TestDocumentProxy()
        proxy.text = "same"
        controller.documentProxy = proxy
        controller.demoMode = false
        for change in 0..<4 {
            controller.showEmoji()
            controller.startEmojiSearch()
            key("c")
            controller.textDidChange(nil)
            controller.selectionDidChange(nil)
            XCTAssertTrue(controller.isSearchingEmoji)
            switch change {
            case 0: proxy.after = "after cursor"
            case 1: proxy.selection = "same"
            case 2: proxy.documentIdentifier = UUID()
            default: proxy.text = "new message"
            }
            if change == 3 { controller.textDidChange(nil) }
            else { controller.selectionDidChange(nil) }
            XCTAssertFalse(controller.isShowingEmoji)
            XCTAssertEqual(controller.emojiQuery, "")
            let before = proxy.text
            key("x")
            XCTAssertEqual(proxy.text, before + "x")
        }
    }

    func testFocusedSearchWithMissingIdentifiersDistinguishesQueryFromHostChanges() {
        final class MissingIdentifierProxy: TestDocumentProxy {
            var omitIdentifier = false
            override func value(forKey key: String) -> Any? {
                key == "documentIdentifier" && omitIdentifier ? nil : super.value(forKey: key)
            }
        }
        let proxy = MissingIdentifierProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { controller.hideEmoji(); window.isHidden = true }
        for selectionChange in [false, true] {
            proxy.omitIdentifier = selectionChange
            proxy.text = "message"
            proxy.after = ""
            proxy.selection = nil
            controller.showEmoji()
            controller.startEmojiSearch()
            XCTAssertTrue(controller.emojiSearch.hasFocus)
            proxy.omitIdentifier = true
            controller.textWillChange(nil)
            XCTAssertTrue(controller.isSearchingEmoji)
            key("c")
            proxy.text = "c"
            proxy.after = nil
            controller.textDidChange(nil)
            XCTAssertTrue(controller.isSearchingEmoji)
            proxy.text = "message"
            if selectionChange { proxy.selection = "word" }
            else { proxy.after = " changed" }
            controller.selectionDidChange(nil)
            XCTAssertFalse(controller.isShowingEmoji)
        }
    }

    func testKnownSearchDocumentReturnsToHostWithoutAnIdentifier() {
        final class OptionalIdentifierProxy: TestDocumentProxy {
            var omitIdentifier = true
            override func value(forKey key: String) -> Any? {
                key == "documentIdentifier" && omitIdentifier ? nil : super.value(forKey: key)
            }
        }
        let proxy = OptionalIdentifierProxy()
        proxy.text = "message"
        controller.documentProxy = proxy
        controller.demoMode = false
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { controller.hideEmoji(); window.isHidden = true }
        controller.showEmoji()
        controller.startEmojiSearch()
        proxy.omitIdentifier = false
        controller.textDidChange(nil)
        XCTAssertTrue(controller.isSearchingEmoji)
        key("c")
        proxy.omitIdentifier = true
        proxy.text = "c"
        controller.textDidChange(nil)
        XCTAssertTrue(controller.isSearchingEmoji)
        proxy.text = "message"
        controller.textDidChange(nil)
        XCTAssertFalse(controller.isShowingEmoji)
    }

    func testSearchDocumentCallbacksKeepSearchUntilHostInputReturns() {
        let proxy = TestDocumentProxy()
        proxy.text = "message"
        controller.documentProxy = proxy
        controller.demoMode = false
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { controller.hideEmoji(); window.isHidden = true }
        for differentField in [false, true] {
            let hostDocument = proxy.documentIdentifier
            controller.showEmoji()
            controller.startEmojiSearch()
            XCTAssertTrue(controller.emojiSearch.hasFocus)
            // Search activation sends callbacks before and after the document changes.
            controller.textWillChange(nil)
            proxy.documentIdentifier = UUID()
            controller.textWillChange(nil)
            controller.textDidChange(nil)
            key("c")
            controller.selectionWillChange(nil)
            controller.selectionDidChange(nil)
            XCTAssertTrue(controller.isSearchingEmoji)
            XCTAssertEqual(controller.emojiQuery, "c")
            proxy.documentIdentifier = differentField ? UUID() : hostDocument
            controller.textWillChange(nil)
            XCTAssertFalse(controller.isShowingEmoji)
            XCTAssertEqual(proxy.text, "message")
        }
    }

    func testBrowseInsertAndDeleteCallbacksDoNotEndBrowse() {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.showEmoji()
        controller.selectEmoji("\u{1F600}")
        controller.textDidChange(nil)
        controller.selectionDidChange(nil)
        XCTAssertTrue(controller.isShowingEmoji)
        controller.emojiDelete.sendActions(for: .touchUpInside)
        controller.textDidChange(nil)
        controller.selectionDidChange(nil)
        XCTAssertTrue(controller.isShowingEmoji)
        XCTAssertEqual(proxy.text, "")
    }

    func testQueryEditingUsesItsSelectionAndClearKeepsSearchActive() throws {
        controller.demoText = "message"
        controller.showEmoji()
        controller.startEmojiSearch()
        for value in ["c", "a", "t"] { key(value) }
        let field = try XCTUnwrap(controller.emojiSearch.subviews.compactMap { $0 as? UISearchTextField }.first)
        let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 1))
        let end = try XCTUnwrap(field.position(from: start, offset: 1))
        field.selectedTextRange = field.textRange(from: start, to: end)
        key("o")
        XCTAssertEqual(controller.emojiQuery, "cot")
        key("delete")
        XCTAssertEqual(controller.emojiQuery, "ct")
        controller.clearEmojiSearch()
        XCTAssertTrue(controller.isSearchingEmoji)
        XCTAssertEqual(controller.emojiQuery, "")
        XCTAssertEqual(controller.context, "message")
    }

    func testEmojiLayoutsKeepTheResultStripAndKeysInsideTheKeyboard() throws {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for width in [264.0, 320, 390, 430, 844] {
          for globe in [false, true] {
            controller.plane.showsGlobe = globe
            controller.showEmoji()
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 244)
            controller.view.layoutIfNeeded()
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let browse = try XCTUnwrap(descendants(controller.view).first { $0 is UIButton && $0.accessibilityIdentifier == "emojiSearchField" })
            let search = browse.convert(browse.bounds, to: controller.view)
            let delete = controller.emojiDelete.convert(controller.emojiDelete.bounds, to: controller.view)
            let results = controller.emojiResults.convert(controller.emojiResults.bounds, to: controller.view)
            XCTAssertEqual(delete.width, 44, accuracy: 0.5)
            XCTAssertEqual(delete.height, 44, accuracy: 0.5)
            XCTAssertEqual(delete.maxX, width - 56, accuracy: 0.5)
            XCTAssertEqual(delete.minX - search.maxX, 4, accuracy: 0.5)
            XCTAssertEqual(results.minX, 8, accuracy: 0.5)
            XCTAssertEqual(results.maxX, width - 8, accuracy: 0.5)
            XCTAssertEqual(results.maxY, 244 - 44, accuracy: 0.5)
            let collection = try XCTUnwrap(controller.emojiResults.subviews.compactMap { $0 as? UICollectionView }.first)
            let section = collection.numberOfSections - 1
            let last = IndexPath(item: collection.numberOfItems(inSection: section) - 1, section: section)
            collection.scrollToItem(at: last, at: .bottom, animated: false)
            collection.layoutIfNeeded()
            let cell = try XCTUnwrap(collection.layoutAttributesForItem(at: last))
            XCTAssertLessThanOrEqual(cell.frame.maxY, collection.contentOffset.y + collection.bounds.height + 0.5)
            collection.contentOffset.y = max(0, collection.contentSize.height - collection.bounds.height)
            XCTAssertLessThanOrEqual(cell.frame.maxY, collection.contentOffset.y + collection.bounds.height - 8 + 0.5)
            controller.startEmojiSearch()
            controller.view.frame.size.height = 288
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            XCTAssertTrue(controller.emojiDelete.isHidden)
            XCTAssertEqual(controller.emojiResults.frame.height, 44, accuracy: 0.5)
            XCTAssertEqual(controller.plane.frame.height, 192, accuracy: 0.5)
            XCTAssertEqual(controller.plane.convert(controller.plane.bounds, to: controller.view).minY, 96, accuracy: 0.5)
            XCTAssertFalse(controller.plane.isHidden)
            XCTAssertGreaterThanOrEqual(controller.emojiSearch.frame.width, 120)
            let field = try XCTUnwrap(controller.emojiSearch.subviews.compactMap { $0 as? UISearchTextField }.first)
            let emptyWidth = field.frame.width
            key("c")
            controller.view.layoutIfNeeded()
            XCTAssertEqual(emptyWidth - field.frame.width, 44, accuracy: 0.5)
            controller.showEmojiBrowse()
            controller.view.frame.size.height = 244
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            XCTAssertFalse(controller.emojiDelete.isHidden)
            XCTAssertTrue(controller.plane.isHidden)
            XCTAssertEqual(controller.emojiResults.frame.height, 148, accuracy: 0.5)
            controller.hideEmoji()
          }
        }
    }

    func testHostCorrectionPreferenceDoesNotDisableManualSuggestions() {
        for type in [UIKeyboardType.default, .asciiCapable, .webSearch, .twitter] {
            for correction in [UITextAutocorrectionType.default, .yes, .no] {
                let policy = KeyboardInputPolicy(keyboardType: type, autocorrectionType: correction)
                XCTAssertTrue(policy.allowsPredictions)
                XCTAssertEqual(policy.allowsCorrectionAndLearning, correction != .no)
            }
        }
        let unspecified = KeyboardInputPolicy(keyboardType: nil, autocorrectionType: nil)
        XCTAssertTrue(unspecified.allowsPredictions)
        XCTAssertTrue(unspecified.allowsCorrectionAndLearning)
        for correction in [UITextAutocorrectionType.default, .yes, .no] {
            let policy = KeyboardInputPolicy(keyboardType: .URL, autocorrectionType: correction)
            XCTAssertTrue(policy.allowsPredictions)
            XCTAssertFalse(policy.allowsCorrectionAndLearning)
        }
        for type in [UIKeyboardType.emailAddress, .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad] {
            let policy = KeyboardInputPolicy(keyboardType: type, autocorrectionType: .yes)
            XCTAssertFalse(policy.allowsPredictions)
            XCTAssertFalse(policy.allowsCorrectionAndLearning)
        }
    }

    func testManualReplacementDoesNotLearnWhenTheHostDisablesCorrection() throws {
        try checkManualReplacementDoesNotLearn(keyboardType: .default, correction: .no)
    }

    func testManualReplacementDoesNotLearnInURLFields() throws {
        try checkManualReplacementDoesNotLearn(keyboardType: .URL, correction: .yes)
    }

    func testURLInputPreservesPunctuationDigitsAndRepeatedSpaces() {
        let proxy = TestDocumentProxy()
        proxy.keyboardType = .URL
        proxy.autocorrectionType = .yes
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.storage.learning = true
        controller.textDidChange(nil)
        for character in "teh https://example.com/path2?q=3" { key(character == " " ? "space" : String(character)) }
        key("space")
        key("space")
        XCTAssertEqual(proxy.text, "teh https://example.com/path2?q=3  ")
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(controller.storage.touches(for: .english).offsets.isEmpty)
    }

    func testSelectingURLCompletionReplacesTheAddressWithoutASpaceOrLearning() {
        let proxy = TestDocumentProxy()
        proxy.keyboardType = .URL
        proxy.text = "https://example.d"
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.storage.learning = true
        controller.textDidChange(nil)
        controller.selectSuggestion("https://example.de")
        XCTAssertEqual(proxy.text, "https://example.de")
        for character in "/path2" { key(String(character)) }
        XCTAssertEqual(proxy.text, "https://example.de/path2")
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(controller.storage.touches(for: .english).offsets.isEmpty)
    }

    private func checkManualReplacementDoesNotLearn(keyboardType: UIKeyboardType, correction: UITextAutocorrectionType) throws {
        let proxy = TestDocumentProxy()
        proxy.keyboardType = keyboardType
        proxy.autocorrectionType = correction
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.storage.learning = true
        let target = try XCTUnwrap(controller.plane.keys.first { $0.0 == "f" }?.1)
        for _ in 0..<3 {
            proxy.text = ""
            controller.textDidChange(nil)
            controller.type(KeyHit(key: "g", point: CGPoint(x: target.midX + target.width * 0.1, y: target.midY), frame: target))
            controller.selectSuggestion("f")
            XCTAssertEqual(proxy.text, "f ")
        }
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(controller.storage.touches(for: .english).offsets.isEmpty)
    }

    func testCorrectionUndoAndKeepOriginalOnSecondSpace() {
        controller.demoText = "send teh"
        key("space")
        XCTAssertEqual(controller.context, "send the ")
        key("delete")
        XCTAssertEqual(controller.context, "send teh")
        key("space")
        XCTAssertEqual(controller.context, "send teh ")
    }

    func testCursorContextChangeCancelsCorrectionUndo() {
        controller.demoText = "send teh"
        key("space")
        controller.demoText = "different the "
        controller.textDidChange(nil)
        key("delete")
        XCTAssertEqual(controller.context, "different the")
    }

    func testSymbolsContractionNewlineAndCorrectionOff() {
        controller.storage.autocorrection = false
        for keyValue in ["d", "o", "n", "'", "t", "space", "t", "e", "h", "space", "page", "1", "2", ".", "return"] {
            key(keyValue)
        }
        XCTAssertEqual(controller.context, "Don't teh 12.\n")
    }

    func testRapidDoubleSpaceInsertsPeriodButOrdinarySpacesDoNot() {
        controller.demoText = "hello"
        key("space")
        key("space")
        XCTAssertEqual(controller.context, "hello. ")
        key("space")
        key("space")
        XCTAssertEqual(controller.context, "hello.   ")
    }

    func testSpacesOutsideTheShortcutIntervalStayAsSpaces() {
        var instant = Date(timeIntervalSince1970: 100)
        controller.now = { instant }
        controller.demoText = "hello"
        key("space")
        instant += 0.5
        key("space")
        XCTAssertEqual(controller.context, "hello  ")
    }

    func testOverlappingSpaceAndLetterKeepInputOrder() throws {
        let plane = controller.plane
        let space = try XCTUnwrap(plane.keys.first { $0.0 == "space" }?.1)
        let letter = try XCTUnwrap(plane.keys.first { $0.0 == "n" }?.1)
        controller.demoText = "word"
        plane.beginKey(KeyHit(key: "space", point: CGPoint(x: space.midX, y: space.midY), frame: space))
        plane.beginKey(KeyHit(key: "n", point: CGPoint(x: letter.midX, y: letter.midY), frame: letter))
        plane.endSpace(at: CGPoint(x: space.midX, y: space.midY))
        XCTAssertEqual(controller.context, "word n")
    }

    func testMultilingualWordsSurviveSpaceOnEitherKeyboardLayout() {
        for layout in KeyboardLanguage.allCases {
            controller.storage.language = layout
            controller.viewWillAppear(false)
            for word in ["dag", "Dag", "DAG", "dankie", "m\u{00f4}re", "Gr\u{00fc}\u{00df}e", "Stra\u{00df}e", "tomorrow"] {
                controller.demoText = "say " + word
                controller.textDidChange(nil)
                key("space")
                XCTAssertEqual(controller.context, "say " + word + " ", word + " / " + layout.rawValue)
            }
        }
    }

    func testMixedMessagePreservesWordsAndStillSupportsCorrectionUndo() {
        controller.storage.learning = false
        controller.demoText = ""
        for word in ["hello", "dag", "dankie", "Gr\u{00fc}\u{00df}e", "tomorrow"] {
            if controller.plane.shifted { key("shift") }
            for character in word { key(String(character)) }
            key("space")
        }
        let message = "hello dag dankie Gr\u{00fc}\u{00df}e tomorrow "
        XCTAssertEqual(controller.context, message)
        for value in ["t", "e", "h", "space"] { key(value) }
        XCTAssertEqual(controller.context, message + "the ")
        key("delete")
        XCTAssertEqual(controller.context, message + "teh")
        key("space")
        XCTAssertEqual(controller.context, message + "teh ")
    }

    func testAfrikaansSuggestionOnGermanLayoutUsesSharedLearningAndLocalTouches() {
        controller.storage.learning = true
        controller.storage.language = .german
        controller.viewWillAppear(false)
        controller.demoText = "baie danki"
        controller.textDidChange(nil)
        controller.selectSuggestion("dankie")
        XCTAssertEqual(controller.context, "baie dankie ")
        controller.switchLanguage()
        XCTAssertEqual(controller.storage.multilingualMemory.words["dankie"], 1)
        XCTAssertTrue(controller.storage.touches(for: .english).offsets.isEmpty)
        XCTAssertTrue(controller.storage.touches(for: .german).offsets.isEmpty)
        controller.demoText = "baie dank"
        controller.textDidChange(nil)
        controller.selectSuggestion("dankie")
        controller.viewWillDisappear(false)
        XCTAssertEqual(controller.storage.multilingualMemory.words["dankie"], 2)
    }

    func testLanguageSwitchSharesLearnedWords() {
        controller.storage.learning = true
        controller.demoText = "portfolio "
        controller.selectSuggestion("hedging")
        controller.switchLanguage()
        controller.demoText = "portfolio "
        controller.selectSuggestion("Absicherung")
        controller.switchLanguage()
        XCTAssertEqual(controller.storage.multilingualMemory.words["hedging"], 1)
        XCTAssertEqual(controller.storage.multilingualMemory.words["absicherung"], 1)
        XCTAssertEqual(controller.storage.multilingualMemory.words["absicherung"], 1)
    }

    private func physicalHit(_ key: String, near target: String? = nil, dx: CGFloat = 0) throws -> KeyHit {
        let frame = try XCTUnwrap(controller.plane.keys.first { $0.0 == key }?.1)
        let intended = try XCTUnwrap(controller.plane.keys.first { $0.0 == (target ?? key) }?.1)
        return KeyHit(key: key, point: CGPoint(x: intended.midX + intended.width * dx, y: intended.midY), frame: frame)
    }

    func testBackspaceCorrectionsTrainOnlyAfterWordConfirmation() throws {
        controller.storage.learning = true
        controller.storage.autocorrection = false
        for afterSpace in [false, true] {
            controller.demoText = "word "
            controller.textDidChange(nil)
            let before = controller.plane.touchModel.observations
            controller.type(try physicalHit("g", near: "f", dx: 0.55))
            if afterSpace { key("space"); key("delete") }
            key("delete")
            controller.type(try physicalHit("f"))
            XCTAssertEqual(controller.plane.touchModel.observations, before)
            key("space")
            XCTAssertEqual(controller.context, "word f ")
            XCTAssertEqual(controller.plane.touchModel.observations, before + 1)
        }
        XCTAssertEqual(controller.plane.touchModel.offsets["f"]?.confusions["g"], 2)
        XCTAssertEqual(controller.plane.touchModel.offsets["f"]?.x ?? 0, 0.55, accuracy: 0.001)
        controller.viewWillDisappear(false)
        let profile = try XCTUnwrap(controller.activeTouchProfile)
        XCTAssertEqual(controller.storage.touches(profile: profile).offsets["f"]?.count, 2)
    }

    func testUnconfirmedAutomaticAndAccessibilityEditsDoNotTrainTouchZones() throws {
        controller.storage.learning = true
        controller.demoText = "send "
        controller.textDidChange(nil)
        for value in ["t", "e", "h"] { controller.type(try physicalHit(value)) }
        key("space")
        XCTAssertEqual(controller.context, "send the ")
        key("delete")
        key("space")
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        let frame = try XCTUnwrap(controller.plane.keys.first { $0.0 == "f" }?.1)
        let synthetic = KeyHit(key: "g", point: CGPoint(x: frame.midX, y: frame.midY), frame: frame, physical: false)
        controller.plane.train(original: "g", replacement: "f", hits: [synthetic])
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        controller.storage.learning = false
        controller.demoText = "word "
        controller.textDidChange(nil)
        controller.type(try physicalHit("g", near: "f", dx: 0.55))
        key("delete")
        controller.type(try physicalHit("f"))
        key("space")
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
    }

    func testHostSelectionAndGeometryChangesDiscardPendingTouchCorrections() throws {
        controller.storage.learning = true
        controller.storage.autocorrection = false
        controller.demoText = "word "
        controller.textDidChange(nil)
        controller.type(try physicalHit("g", near: "f", dx: 0.55))
        key("delete")
        controller.selectionDidChange(nil)
        controller.type(try physicalHit("f"))
        key("space")
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        let original = try XCTUnwrap(controller.activeTouchProfile)
        for _ in 0..<3 { controller.plane.touchModel.learn(key: "a", x: 0.1, y: 0) }
        controller.view.frame.size.width = 320
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertNotEqual(controller.activeTouchProfile, original)
        XCTAssertTrue(controller.plane.touchModel.offsets.isEmpty)
        controller.view.frame.size.width = 390
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.activeTouchProfile, original)
        XCTAssertEqual(controller.plane.touchModel.offsets["a"]?.count, 3)
    }

    func testTouchDiagnosticsStaysInlineAndRestoresTheTypingPage() {
        key("page")
        controller.showSettings()
        controller.showTouchDiagnostics()
        controller.showTouchDiagnostics()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.isShowingTouchDiagnostics)
        XCTAssertFalse(controller.touchDiagnostics.isHidden)
        XCTAssertNil(controller.presentedViewController)
        XCTAssertEqual(controller.plane.page, 0)
        controller.hideSettings()
        XCTAssertFalse(controller.isShowingTouchDiagnostics)
        XCTAssertTrue(controller.isShowingSettings)
        XCTAssertEqual(controller.plane.page, 1)
        controller.hideSettings()
        controller.showSettings()
        controller.showTouchDiagnostics()
        controller.showEmoji()
        XCTAssertFalse(controller.isShowingSettings)
        XCTAssertFalse(controller.isShowingTouchDiagnostics)
        XCTAssertTrue(controller.isShowingEmoji)
    }

    func testTouchTrainingChangesResolutionOnlyWithValidSamples() throws {
        let plane = controller.plane
        let frame = try XCTUnwrap(plane.keys.first { $0.0 == "f" }?.1)
        let nextFrame = try XCTUnwrap(plane.keys.first { $0.0 == "g" }?.1)
        let point = CGPoint(x: frame.midX + (nextFrame.midX - frame.midX) * 0.55, y: frame.midY)
        let hit = KeyHit(key: "g", point: point, frame: nextFrame)
        XCTAssertEqual(plane.hit(at: point)?.key, "g")
        plane.train(original: "g", replacement: "foo", hits: [hit])
        plane.train(original: "g", replacement: "f", hits: [])
        XCTAssertTrue(plane.touchModel.offsets.isEmpty)
        for _ in 0..<3 { plane.train(original: "g", replacement: "f", hits: [hit]) }
        XCTAssertEqual(plane.hit(at: point)?.key, "g")
        for _ in 0..<150 where !plane.touchModel.hasApprovedModel {
            plane.train(original: "g", replacement: "f", hits: [hit])
        }
        XCTAssertTrue(plane.touchModel.hasApprovedModel)
        XCTAssertEqual(plane.hit(at: point)?.key, "f")
        XCTAssertTrue(plane.isMultipleTouchEnabled)
    }

    func testMemoryWarningPausesNeuralRequestsUntilNextAppearance() {
        controller.storage.neuralPrediction = true
        controller.didReceiveMemoryWarning()
        XCTAssertTrue(controller.neuralSuspended)
        key("h")
        XCTAssertTrue(controller.neuralSuspended)
        controller.switchLanguage()
        XCTAssertTrue(controller.neuralSuspended)
        controller.viewWillAppear(false)
        XCTAssertFalse(controller.neuralSuspended)
    }

    func testSettingsUsesTheKeyboardBoundsAndTypingResumes() {
        let height = controller.view.bounds.height
        for _ in 0..<3 {
            controller.showSettings()
            controller.showSettings()
            controller.view.layoutIfNeeded()
            XCTAssertTrue(controller.isShowingSettings)
            XCTAssertTrue(controller.plane.isHidden)
            XCTAssertFalse(controller.settingsPanel.isHidden)
            XCTAssertNil(controller.presentedViewController)
            XCTAssertEqual(controller.view.bounds.height, height)
            controller.hideSettings()
            XCTAssertFalse(controller.plane.isHidden)
        }
        key("h")
        key("i")
        XCTAssertEqual(controller.context, "Hi")
    }

    func testSettingsTextWrapsInsideAlignedMarginsOnNarrowScreens() throws {
        for width in [264.0, 390, 844] {
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 244)
            controller.showSettings()
            controller.view.layoutIfNeeded()
            controller.settingsPanel.layoutIfNeeded()
            let stack = try XCTUnwrap(controller.settingsPanel.subviews.compactMap { $0 as? UIStackView }.first)
            for row in stack.arrangedSubviews where (row as? UIStackView)?.arrangedSubviews.last is UISwitch {
                let rowFrame = row.convert(row.bounds, to: controller.view)
                XCTAssertEqual(rowFrame.minX, 8, accuracy: 0.5)
                XCTAssertEqual(rowFrame.maxX, width - 8, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(rowFrame.height, 44)
                let labels = try XCTUnwrap((row as? UIStackView)?.arrangedSubviews.first as? UIStackView)
                for label in labels.arrangedSubviews.compactMap({ $0 as? UILabel }) {
                    let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                    XCTAssertLessThanOrEqual(needed.height, label.bounds.height + 0.5)
                }
            }
            controller.hideSettings()
        }
    }

    func testSettingsCorrectionToggleAppliesAfterReturningToKeys() {
        controller.showSettings()
        controller.settingsPanel.correctionSwitch.isOn = false
        controller.settingsPanel.correctionSwitch.sendActions(for: .valueChanged)
        controller.hideSettings()
        controller.demoText = "send teh"
        key("space")
        XCTAssertEqual(controller.context, "send teh ")
    }

    func testDeleteLearnedDataNeedsConfirmationAndClearsBothLanguages() {
        controller.storage.learning = true
        controller.demoText = "portfolio "
        controller.selectSuggestion("hedging")
        controller.switchLanguage()
        controller.demoText = "portfolio "
        controller.selectSuggestion("Absicherung")
        controller.switchLanguage()
        controller.showSettings()
        controller.settingsPanel.deleteButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.settingsPanel.deletionPending)
        XCTAssertNotNil(controller.storage.multilingualMemory.words["hedging"])
        controller.settingsPanel.resetConfirmation()
        XCTAssertFalse(controller.settingsPanel.deletionPending)
        XCTAssertNotNil(controller.storage.multilingualMemory.words["absicherung"])
        controller.settingsPanel.deleteButton.sendActions(for: .touchUpInside)
        controller.settingsPanel.deleteButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testClosingSettingsCancelsDeletionConfirmation() {
        controller.storage.learning = true
        controller.demoText = "portfolio "
        controller.selectSuggestion("hedging")
        controller.switchLanguage()
        controller.switchLanguage()
        controller.showSettings()
        controller.settingsPanel.deleteButton.sendActions(for: .touchUpInside)
        controller.hideSettings()
        controller.showSettings()
        XCTAssertFalse(controller.settingsPanel.deletionPending)
        controller.settingsPanel.deleteButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.settingsPanel.deletionPending)
        XCTAssertNotNil(controller.storage.multilingualMemory.words["hedging"])
    }

    func testCompactGeometryHasNoUnusedRowsOrOutOfBoundsKeys() {
        let plane = controller.plane
        XCTAssertEqual(KeyboardLayout.height(compact: false), 244)
        XCTAssertEqual(KeyboardLayout.height(compact: true), 196)
        for width in [264.0, 320, 390, 430, 844] {
            for compact in [false, true] {
                for language in KeyboardLanguage.allCases {
                    for globe in [false, true] {
                      for page in 0...2 {
                        plane.showsGlobe = globe
                        plane.language = language
                        plane.page = page
                        plane.frame = CGRect(x: 0, y: 0, width: width, height: KeyboardLayout.rowHeight(compact: compact) * 4)
                        plane.layoutIfNeeded()
                        for (key, frame) in plane.keys {
                            XCTAssertGreaterThan(frame.width, 0, key)
                            XCTAssertGreaterThanOrEqual(frame.minX, -0.01, key)
                            XCTAssertLessThanOrEqual(frame.maxX, width + 0.01, key)
                            XCTAssertEqual(frame.height, KeyboardLayout.rowHeight(compact: compact))
                            XCTAssertEqual(plane.hit(at: CGPoint(x: frame.midX, y: frame.midY))?.key, key)
                        }
                        XCTAssertEqual(plane.keys.last?.1.maxY, plane.bounds.height)
                        XCTAssertNil(plane.keys.first { $0.0 == "language" })
                        let bottom = plane.keys.filter { $0.1.maxY == plane.bounds.height }
                        let scale = min(1, width / 320)
                        for punctuation in [",", "."] {
                            let frame = bottom.first { $0.0 == punctuation }!.1
                            XCTAssertEqual(frame.width, 44 * scale, accuracy: 0.01)
                            for fraction in [0.02, 0.98] {
                                XCTAssertEqual(plane.hit(at: CGPoint(x: frame.minX + frame.width * fraction,
                                                                  y: frame.midY))?.key, punctuation)
                            }
                        }
                        XCTAssertEqual(bottom.reduce(0) { $0 + $1.1.width }, width, accuracy: 0.01)
                      }
                    }
                }
            }
        }
    }
    func testPracticeSessionPreservesNormalSettingsAndHistoryAfterCancellation() throws {
        let storage = controller.storage
        storage.language = .german
        storage.preferredLanguage = .afrikaans
        storage.keyboardSize = .tall
        storage.keyboardHand = .left
        storage.numberRow = true
        storage.learning = true
        storage.setProtected("teh", enabled: true)
        storage.recordEmoji("\u{1F431}")
        var memory = LearningMemory()
        memory.learn(word: "portfolio", previous: "risk")
        storage.saveWords(memory)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let original = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        var session: PracticeSession? = PracticeSession()
        weak var released = session
        let practice = KeyboardViewController()
        practice.demoMode = true
        practice.storage = try XCTUnwrap(session).storage
        practice.loadViewIfNeeded()
        practice.beginAppearanceTransition(true, animated: false)
        practice.endAppearanceTransition()
        XCTAssertEqual(practice.storage.language, .english)
        XCTAssertTrue(practice.storage.autocorrection)
        XCTAssertFalse(practice.storage.learning)
        XCTAssertTrue(practice.storage.protectedWords.isEmpty)
        XCTAssertTrue(practice.storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(practice.storage.emojiUsage.ranked.isEmpty)
        practice.demoText = "Send teh"
        practice.type(KeyHit(key: "space", point: .zero, frame: .zero))
        XCTAssertEqual(practice.context, "Send the ")
        practice.storage.language = .german
        practice.storage.preferredLanguage = .german
        practice.storage.learning = true
        practice.storage.setProtected("hello", enabled: true)
        practice.storage.recordEmoji("\u{1F436}")
        practice.viewWillDisappear(false)
        session = nil
        XCTAssertNil(released)
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(defaults.persistentDomain(forName: suite))).isEqual(to: original))
    }

    func testPreferenceChangeRejectsAnActiveNeuralResultAndPreservesPrivateTyping() async {
        controller.setPrivateTyping(true)
        let started = expectation(description: "Old language request starts")
        let finished = expectation(description: "Old language request finishes")
        let gate = DispatchSemaphore(value: 0)
        controller.neuralService = NeuralPredictionService { _, _ in
            DelayedCapitalizationModel(started: started, gate: gate, finished: finished)
        }
        controller.storage.neuralPrediction = true
        controller.demoText = "we should review "
        controller.textDidChange(nil)
        await fulfillment(of: [started], timeout: 2)
        controller.settingsPanel.onPreferredLanguageChange?(.afrikaans)
        let stale = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            controller.suggestionButtons.contains { $0.currentTitle?.lowercased() == "zebra" }
        }, object: nil)
        stale.isInverted = true
        gate.signal()
        await fulfillment(of: [finished, stale], timeout: 0.3)
        XCTAssertTrue(controller.isPrivateTyping)
        XCTAssertEqual(controller.storage.preferredLanguage, .afrikaans)
        XCTAssertEqual(controller.storage.language, .english)
        controller.storage.neuralPrediction = false
        key("a")
        key("space")
        controller.viewWillDisappear(false)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testLargerLabelsFitBothLayoutsWithoutChangingKeyGeometry() {
        let plane = KeyboardPlane()
        for language in KeyboardLanguage.allCases {
            for width in [234.0, 264.0, 390.0] {
                for numbers in [false, true] {
                    for page in [0, 1, 2] {
                        plane.language = language
                        plane.page = page
                        plane.numberRow = numbers
                        plane.compact = width < 300
                        let rows = numbers && page == 0 ? 5 : 4
                        plane.frame = CGRect(x: 0, y: 0, width: width, height: Double(rows) * (width < 300 ? 32 : 48))
                        plane.layoutIfNeeded()
                        let keys = plane.keys
                        plane.largerKeyLabels = false
                        plane.highContrast = false
                        let normal = keys.map { plane.labelFont(for: $0.0, frame: $0.1.insetBy(dx: 2, dy: 2)).pointSize }
                        plane.largerKeyLabels = true
                        plane.highContrast = true
                        plane.setNeedsLayout()
                        plane.layoutIfNeeded()
                        XCTAssertEqual(keys.map(\.0), plane.keys.map(\.0))
                        XCTAssertEqual(keys.map(\.1), plane.keys.map(\.1))
                        for (index, item) in keys.enumerated() {
                            let frame = item.1.insetBy(dx: 2, dy: 2)
                            let font = plane.labelFont(for: item.0, frame: frame)
                            XCTAssertGreaterThanOrEqual(font.pointSize + 0.01, normal[index], item.0)
                            XCTAssertLessThanOrEqual(font.lineHeight, frame.height + 0.1, item.0)
                            if item.0 == "space" {
                                let width = ("PrivateType" as NSString).size(withAttributes: [.font: font]).width
                                XCTAssertLessThanOrEqual(width, frame.width + 0.1)
                            }
                        }
                        let letter = plane.keys.first { $0.0 == "q" }
                        if let letter {
                            XCTAssertGreaterThan(plane.labelFont(for: "q", frame: letter.1).pointSize, normal[0])
                        }
                    }
                }
            }
        }
    }

    func testSystemAccessibilityTraitsApplyWithOptionsOffAndHighContrastStaysReadable() {
        let plane = controller.plane
        plane.largerKeyLabels = false
        plane.highContrast = false
        plane.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        plane.traitOverrides.accessibilityContrast = .high
        plane.updateTraitsIfNeeded()
        XCTAssertTrue(plane.usesLargerLabels)
        XCTAssertTrue(plane.usesHighContrast)
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            for key in ["q", "space", "shift", "delete", "return"] {
                func luminance(_ color: UIColor) -> CGFloat {
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    func linear(_ value: CGFloat) -> CGFloat {
                        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                    }
                    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
                }
                let text = luminance(plane.keyForeground(for: key))
                let fill = luminance(plane.keyFill(for: key))
                XCTAssertGreaterThanOrEqual((max(text, fill) + 0.05) / (min(text, fill) + 0.05), 4.5)
            }
        }
    }

    func testAppearanceChangesPreserveTouchProfilePrivateModeAndGeometry() throws {
        let before = controller.plane.keys.map(\.1)
        let profile = try XCTUnwrap(controller.activeTouchProfile)
        controller.setPrivateTyping(true)
        controller.settingsPanel.largerLabelsSwitch.isOn = true
        controller.settingsPanel.highContrastSwitch.isOn = true
        controller.settingsPanel.highContrastSwitch.sendActions(for: .valueChanged)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.storage.largerKeyLabels)
        XCTAssertTrue(controller.storage.highContrast)
        XCTAssertTrue(controller.isPrivateTyping)
        XCTAssertEqual(controller.activeTouchProfile, profile)
        XCTAssertEqual(controller.plane.keys.map(\.1), before)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testAccessibleKeysStayStableAndRejectHiddenStaleAndDismissedActions() throws {
        let plane = controller.plane
        controller.demoText = "word "
        controller.textDidChange(nil)
        func letter(_ name: String) throws -> UIAccessibilityElement {
            try XCTUnwrap(plane.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }
                .first { $0.accessibilityLabel == name })
        }
        let first = try letter("a")
        plane.setNeedsLayout()
        plane.layoutIfNeeded()
        XCTAssertTrue(first === (try letter("a")))
        let accent = try XCTUnwrap(first.accessibilityCustomActions?.first { $0.name == "Insert \u{00e4}" })
        controller.showSettings()
        XCTAssertFalse(first.accessibilityActivate())
        XCTAssertEqual(accent.actionHandler?(accent), false)
        controller.hideSettings()
        controller.showWordOptions("word")
        XCTAssertFalse(first.accessibilityActivate())
        controller.hideWordOptions()
        controller.showEmoji()
        controller.showEmojiBrowse()
        XCTAssertFalse(first.accessibilityActivate())
        controller.hideEmoji()
        plane.shifted = true
        XCTAssertFalse(first.accessibilityActivate())
        XCTAssertEqual(accent.actionHandler?(accent), false)
        let upper = try letter("A")
        let upperAccent = try XCTUnwrap(upper.accessibilityCustomActions?.first { $0.name == "Insert \u{00c4}" })
        XCTAssertEqual(upperAccent.actionHandler?(upperAccent), true)
        XCTAssertEqual(controller.context, "word \u{00c4}")
        controller.viewWillDisappear(false)
        XCTAssertFalse((try letter("a")).accessibilityActivate())
    }

    func testVoiceOverFeedbackUsesGenericQueuedStatusAndRestoresFocus() throws {
        controller.voiceOverActive = { true }
        var events: [(UIAccessibility.Notification, Any?)] = []
        controller.postAccessibility = { events.append(($0, $1)) }
        controller.setPrivateTyping(true)
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        key("space")
        controller.textDidChange(nil)
        controller.textDidChange(nil)
        var messages = events.filter { $0.0 == .announcement }.compactMap { $0.1 as? NSAttributedString }
        XCTAssertEqual(messages.map(\.string), ["Correction available. Undo restores the original word."])
        XCTAssertEqual(messages.first?.attribute(.accessibilitySpeechAnnouncementPriority, at: 0, effectiveRange: nil) as? String,
                       UIAccessibilityPriority.low.rawValue)
        controller.undoButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "send teh")
        XCTAssertNotNil(events.last?.1 as? UIButton)
        key("space")
        let delete = try XCTUnwrap(controller.plane.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }
            .first { $0.accessibilityLabel == "Delete" })
        let action = try XCTUnwrap(delete.accessibilityCustomActions?.first { $0.name == "Delete word" })
        XCTAssertEqual(action.actionHandler?(action), true)
        controller.textDidChange(nil)
        messages = events.filter { $0.0 == .announcement }.compactMap { $0.1 as? NSAttributedString }
        XCTAssertEqual(messages.map(\.string), ["Correction available. Undo restores the original word.",
                                             "Text deleted. Restore is available."])
        controller.restoreButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "send teh ")
        XCTAssertEqual(events.last?.0, .layoutChanged)
        XCTAssertTrue(controller.isPrivateTyping)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testWordOptionsRestoreTheOriginAndVoiceOverOffDoesNotAnnounce() throws {
        controller.demoText = "he"
        controller.textDidChange(nil)
        controller.voiceOverActive = { true }
        var focus: Any?
        controller.postAccessibility = { if $0 == .layoutChanged { focus = $1 } }
        let origin = try XCTUnwrap(controller.suggestionButtons.last(where: { $0.isEnabled }))
        let action = try XCTUnwrap(origin.accessibilityCustomActions?.first)
        XCTAssertEqual(action.actionHandler?(action), true)
        controller.hideWordOptions()
        XCTAssertTrue(focus as? UIButton === origin)
        controller.voiceOverActive = { false }
        var eventCount = 0
        controller.postAccessibility = { _, _ in eventCount += 1 }
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        key("space")
        controller.undoCorrection()
        XCTAssertEqual(eventCount, 0)
    }

    func testLargestSettingsTextFitsNarrowAndLandscapeWidths() throws {
        let panel = KeyboardSettingsView(frame: .zero)
        panel.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        func updateTraits(_ view: UIView) {
            view.updateTraitsIfNeeded()
            view.subviews.forEach(updateTraits)
        }
        updateTraits(panel)
        func labels(_ view: UIView) -> [UILabel] {
            (view as? UILabel).map { [$0] } ?? view.subviews.flatMap(labels)
        }
        for size in [CGSize(width: 320, height: 192), CGSize(width: 700, height: 144)] {
            panel.frame = CGRect(origin: .zero, size: size)
            panel.setNeedsLayout()
            panel.layoutIfNeeded()
            let title = try XCTUnwrap(labels(panel).first { $0.text == "Neural predictions" })
            XCTAssertGreaterThan(title.font.pointSize, 30)
            XCTAssertLessThanOrEqual(panel.contentSize.width, size.width + 1)
            XCTAssertGreaterThan(panel.contentSize.height, size.height)
            for label in labels(panel) where !label.isHidden && label.bounds.width > 0 {
                let required = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(required.height, label.bounds.height + 1, label.text ?? "")
            }
        }
    }

    func testWordOptionsActionRejectsUnavailablePanelsAndURLSuggestions() throws {
        controller.demoText = "he"
        controller.textDidChange(nil)
        let button = try XCTUnwrap(controller.suggestionButtons.first { $0.isEnabled })
        let action = try XCTUnwrap(button.accessibilityCustomActions?.first)
        controller.showSettings()
        XCTAssertEqual(action.actionHandler?(action), false)
        controller.hideSettings()
        controller.showEmoji()
        XCTAssertEqual(action.actionHandler?(action), false)
        controller.hideEmoji()
        button.isHidden = true
        XCTAssertEqual(action.actionHandler?(action), false)
        button.isHidden = false
        controller.viewWillDisappear(false)
        XCTAssertEqual(action.actionHandler?(action), false)
        controller.viewWillAppear(false)
        let proxy = TestDocumentProxy()
        proxy.keyboardType = .URL
        proxy.text = "example.d"
        controller.demoMode = false
        controller.documentProxy = proxy
        controller.textDidChange(nil)
        let address = try XCTUnwrap(controller.suggestionButtons.first { $0.currentTitle == "example.de" })
        let addressAction = try XCTUnwrap(address.accessibilityCustomActions?.first)
        XCTAssertEqual(addressAction.actionHandler?(addressAction), false)
        XCTAssertFalse(controller.isShowingWordOptions)
        XCTAssertEqual(proxy.text, "example.d")
    }

    func testWideUppercaseGermanLettersAndLongReturnFitNarrowKeys() throws {
        let plane = KeyboardPlane()
        plane.language = .german
        plane.shifted = true
        plane.compact = true
        plane.returnTitle = "Continue"
        plane.frame = CGRect(x: 0, y: 0, width: 264, height: 128)
        plane.layoutIfNeeded()
        for key in ["w", "\u{00fc}", "\u{00f6}", "\u{00e4}", "\u{00df}", "return"] {
            let frame = try XCTUnwrap(plane.keys.first { $0.0 == key }?.1).insetBy(dx: 2, dy: 2)
            plane.largerKeyLabels = false
            plane.highContrast = false
            let normal = plane.labelFont(for: key, frame: frame).pointSize
            plane.largerKeyLabels = true
            plane.highContrast = true
            let font = plane.labelFont(for: key, frame: frame)
            let text = key == "return" ? "Continue" : AlternateCharacters.cased(key, uppercase: true)
            XCTAssertLessThanOrEqual((text as NSString).size(withAttributes: [.font: font]).width, frame.width + 0.1, key)
            XCTAssertGreaterThanOrEqual(font.pointSize + 0.01, normal, key)
        }
    }

    func testRetainedSuggestionActionsRejectCorrectionAndRestoreRows() throws {
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        let button = try XCTUnwrap(controller.suggestionButtons.first { $0.isEnabled })
        let options = try XCTUnwrap(button.accessibilityCustomActions?.first)
        key("space")
        XCTAssertFalse(controller.undoButton.isHidden)
        XCTAssertEqual(options.actionHandler?(options), false)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "send the ")
        XCTAssertFalse(controller.isShowingWordOptions)
        XCTAssertFalse(controller.undoButton.isHidden)
        controller.undoCorrection()
        key("space")
        XCTAssertTrue(controller.beginWordDeletion())
        controller.previewWordDeletion(1)
        controller.commitWordDeletion()
        XCTAssertFalse(controller.restoreButton.isHidden)
        XCTAssertEqual(options.actionHandler?(options), false)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "send ")
        XCTAssertFalse(controller.isShowingWordOptions)
        XCTAssertFalse(controller.restoreButton.isHidden)
    }

    func testHighContrastSwitchThumbsUpdateForBothStatesAndReset() {
        controller.showSettings()
        let panel = controller.settingsPanel
        panel.applyContrast(true)
        let toggle = panel.numberRowSwitch
        toggle.isOn = false
        toggle.sendActions(for: .valueChanged)
        XCTAssertNil(toggle.thumbTintColor)
        toggle.isOn = true
        toggle.sendActions(for: .valueChanged)
        XCTAssertEqual(toggle.thumbTintColor, .systemBackground)
        panel.applyContrast(false)
        XCTAssertNil(toggle.thumbTintColor)
        XCTAssertNil(toggle.onTintColor)
    }

    func testNavigationHeadersKeepControlsAndPrivateStatusSeparate() throws {
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        func visible(_ view: UIView) -> Bool {
            var ancestor: UIView? = view
            while let current = ancestor {
                if current.isHidden { return false }
                ancestor = current.superview
            }
            return true
        }
        func check(back name: String, title: String) throws {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let back = try XCTUnwrap(views(controller.view).compactMap { $0 as? UIButton }
                .first { $0.accessibilityLabel == name && visible($0) })
            let label = try XCTUnwrap(views(controller.view).compactMap { $0 as? UILabel }
                .first { $0.text == title && visible($0) })
            let backFrame = back.convert(back.bounds, to: controller.view)
            let titleFrame = label.convert(label.bounds, to: controller.view)
            let safe = controller.view.safeAreaLayoutGuide.layoutFrame
            XCTAssertGreaterThanOrEqual(backFrame.height, 44)
            XCTAssertTrue(safe.contains(backFrame))
            XCTAssertTrue(safe.contains(titleFrame))
            let header = try XCTUnwrap(controller.privateIndicator.superview)
            let ordered = try XCTUnwrap(header.accessibilityElements?.compactMap { $0 as? UIView })
            if title == "sample" {
                XCTAssertEqual(backFrame.minX, safe.minX + 8, accuracy: 1)
                XCTAssertEqual(titleFrame.midX, safe.midX, accuracy: 1)
                XCTAssertTrue(ordered.first === back)
                if controller.isPrivateTyping { XCTAssertTrue(ordered.last === controller.privateIndicator) }
            } else {
                let inset = controller.isPrivateTyping ? 112.0 : 56.0
                if name == "Back to settings" {
                    XCTAssertEqual(backFrame.minX, safe.minX + inset, accuracy: 1)
                } else {
                    XCTAssertEqual(backFrame.minX, safe.minX + 8, accuracy: 1)
                }
                XCTAssertLessThanOrEqual(titleFrame.maxX, safe.maxX - 52)
                if controller.isPrivateTyping {
                    let status = controller.privateIndicator.convert(controller.privateIndicator.bounds, to: controller.view)
                    XCTAssertLessThanOrEqual(status.maxX, titleFrame.minX)
                    XCTAssertTrue(ordered.dropFirst().first === controller.privateIndicator)
                }
            }
            if !controller.isPrivateTyping { XCTAssertFalse(ordered.contains { $0 === controller.privateIndicator }) }

        }
        for enabled in [false, true] {
            controller.setPrivateTyping(enabled)
            for width in [264.0, 390.0, 844.0] {
                controller.traitOverrides.verticalSizeClass = width > 700 ? .compact : .regular
                controller.view.updateTraitsIfNeeded()
                controller.view.frame = CGRect(x: 0, y: 0, width: width, height: width > 700 ? 196 : 244)
                controller.showSettings()
                try check(back: "Back to keyboard", title: "Preview settings")
                controller.showTouchDiagnostics()
                try check(back: "Back to settings", title: "Touch zones")
                controller.hideSettings()
                try check(back: "Back to keyboard", title: "Preview settings")
                controller.hideSettings()
                XCTAssertTrue(controller.showWordOptions("sample"))
                try check(back: "Close word options", title: "sample")
                controller.hideWordOptions()
            }
        }
    }

    func testPrivateEmojiNavigationAndTypingFeedbackDoNotOverlap() throws {
        controller.setPrivateTyping(true)
        for hand in KeyboardHand.allCases {
            controller.storage.keyboardHand = hand
            controller.view.frame.size.width = 264
            controller.showEmoji()
            controller.showEmojiBrowse()
            controller.startEmojiSearch()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let header = try XCTUnwrap(controller.privateIndicator.superview)
            let order = try XCTUnwrap(header.accessibilityElements?.compactMap { $0 as? UIView })
            let back = try XCTUnwrap(order.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "searchEmoji" })
            XCTAssertEqual(back.accessibilityLabel, "Back to typing")
            let search = controller.emojiSearch.convert(controller.emojiSearch.bounds, to: controller.view)
            let status = controller.privateIndicator.convert(controller.privateIndicator.bounds, to: controller.view)
            XCTAssertGreaterThanOrEqual(search.width, 120)
            XCTAssertLessThanOrEqual(search.maxY, status.minY)
            XCTAssertTrue(order.dropFirst().first === controller.privateIndicator)
            controller.setPrivateTyping(false)
            controller.view.layoutIfNeeded()
            XCTAssertFalse(header.accessibilityElements?.contains { ($0 as? UIView) === controller.privateIndicator } ?? true)
            controller.setPrivateTyping(true)
            controller.showEmojiBrowse()
            controller.view.layoutIfNeeded()
            let browseBack = back.convert(back.bounds, to: controller.view)
            let delete = controller.emojiDelete.convert(controller.emojiDelete.bounds, to: controller.view)
            XCTAssertEqual(browseBack.minX - delete.maxX, 4, accuracy: 0.5)
            controller.hideEmoji()
        }
        controller.storage.keyboardHand = .full
        func checkFeedbackOrder(_ active: [UIView], absent: [UIView]) throws {
            let order = try XCTUnwrap(controller.privateIndicator.superview?.accessibilityElements?.compactMap { $0 as? UIView })
            XCTAssertTrue(order.dropFirst().first === controller.privateIndicator)
            for view in active { XCTAssertTrue(order.contains { $0 === view }) }
            for view in absent { XCTAssertFalse(order.contains { $0 === view }) }
        }
        controller.demoText = "send teh"
        controller.textDidChange(nil)
        try checkFeedbackOrder(controller.suggestionButtons.filter { $0.isEnabled },
            absent: [controller.undoButton, controller.restoreButton])
        key("space")
        try checkFeedbackOrder([controller.correctionLabel, controller.undoButton],
            absent: controller.suggestionButtons + [controller.restoreButton])
        controller.view.layoutIfNeeded()
        let status = controller.privateIndicator.convert(controller.privateIndicator.bounds, to: controller.view)
        let correction = controller.correctionLabel.convert(controller.correctionLabel.bounds, to: controller.view)
        XCTAssertGreaterThanOrEqual(correction.minX, status.maxX + 4)
        controller.undoCorrection()
        try checkFeedbackOrder(controller.suggestionButtons.filter { $0.isEnabled },
            absent: [controller.undoButton, controller.restoreButton])
        key("space")
        XCTAssertTrue(controller.beginWordDeletion())
        controller.previewWordDeletion(1)
        controller.commitWordDeletion()
        controller.view.layoutIfNeeded()
        let deletion = controller.deletionLabel.convert(controller.deletionLabel.bounds, to: controller.view)
        XCTAssertGreaterThanOrEqual(deletion.minX, status.maxX + 4)
        XCTAssertFalse(controller.restoreButton.isHidden)
        try checkFeedbackOrder([controller.deletionLabel, controller.restoreButton],
            absent: controller.suggestionButtons + [controller.undoButton])
        controller.restoreDeletedText()
        try checkFeedbackOrder(controller.suggestionButtons.filter { $0.isEnabled },
            absent: [controller.undoButton, controller.restoreButton])
        XCTAssertTrue(controller.beginWordDeletion())
        controller.previewWordDeletion(1)
        controller.commitWordDeletion()
        try checkFeedbackOrder([controller.restoreButton], absent: controller.suggestionButtons)
        key("shift")
        try checkFeedbackOrder(controller.suggestionButtons.filter { $0.isEnabled },
            absent: [controller.undoButton, controller.restoreButton])
        XCTAssertTrue(controller.isPrivateTyping)
    }

    func testLayoutSelectionInSettingsPersistsWithoutChangingTextOrLanguagePreference() {
        controller.demoText = "Please keep it"
        controller.storage.preferredLanguage = .afrikaans
        for (index, layout) in KeyboardLanguage.allCases.enumerated().reversed() {
            controller.showSettings()
            let control = controller.settingsPanel.layoutControl
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
            XCTAssertEqual(controller.storage.language, layout)
            XCTAssertEqual(KeyboardStorage(defaults: UserDefaults(suiteName: suite)!).language, layout)
            XCTAssertEqual(controller.storage.preferredLanguage, .afrikaans)
            XCTAssertEqual(controller.plane.language, layout)
            XCTAssertEqual(controller.context, "Please keep it")
            controller.hideSettings()
            controller.showSettings()
            XCTAssertEqual(control.selectedSegmentIndex, index)
            controller.hideSettings()
        }
    }

    func testSpacePreservesOrdinaryWordsDespiteUppercaseLexiconEntries() {
        for layout in KeyboardLanguage.allCases {
            controller.storage.language = layout
            controller.viewWillAppear(false)
            for word in ["it", "It", "IT", "us", "Us", "US"] {
                controller.registerLexiconEntry(input: word.lowercased(), replacement: word.uppercased())
                controller.demoText = "Please send " + word
                controller.textDidChange(nil)
                key("space")
                XCTAssertEqual(controller.context, "Please send " + word + " ")
                key("delete")
                XCTAssertEqual(controller.context, "Please send " + word)
            }
        }
    }

    func testSpaceKeepsTypedCaseForSupplementaryLexiconWords() {
        for word in ["the", "tap", "work", "hello"] {
            controller.registerLexiconEntry(input: word, replacement: word.capitalized)
            controller.demoText = "Please send " + word
            controller.textDidChange(nil)
            key("space")
            XCTAssertEqual(controller.context, "Please send " + word + " ")
        }
        for word in ["The", "Avery", "Berlin", "API", "THE"] {
            controller.registerLexiconEntry(input: word, replacement: word.lowercased())
            controller.demoText = "Ask " + word
            controller.textDidChange(nil)
            key("space")
            XCTAssertEqual(controller.context, "Ask " + word + " ")
        }
        for (shortcut, expansion) in [("brb", "Be right back"), ("sig", "Avery"), ("api", "API"), ("i", "I")] {
            controller.registerLexiconEntry(input: shortcut, replacement: expansion)
            controller.demoText = "Say " + shortcut
            controller.textDidChange(nil)
            key("space")
            XCTAssertEqual(controller.context, "Say " + expansion + " ")
        }
        controller.demoText = "Vielen Dank i"
        controller.textDidChange(nil)
        key("space")
        XCTAssertEqual(controller.context, "Vielen Dank i ")
    }

    func testSpaceDoesNotStealBottomLetterContactsAndFunctionCellsStayExact() throws {
        let plane = controller.plane
        for width: CGFloat in [264, 390] {
            for language in KeyboardLanguage.allCases {
                plane.language = language
                plane.frame = CGRect(x: 0, y: 0, width: width, height: 192)
                plane.layoutIfNeeded()
                let letterRow = try XCTUnwrap(plane.keys.first { $0.0 == "b" }?.1)
                let letters = plane.keys.filter { $0.0.count == 1 && $0.0.first?.isLetter == true && $0.1.minY == letterRow.minY }
                for (key, cell) in letters {
                    for fraction: CGFloat in [0.05, 0.5, 0.95] {
                        let point = CGPoint(x: cell.minX + cell.width * fraction, y: cell.maxY - 1)
                        let hit = try XCTUnwrap(plane.hit(at: point))
                        XCTAssertTrue(letters.contains { $0.0 == hit.key }, key + " selected " + hit.key)
                    }
                }
                for (key, cell) in plane.keys where key.count > 1 || key.first?.isLetter != true {
                    if key == "globe" { continue }
                    for fraction: CGFloat in [0.05, 0.95] {
                        XCTAssertEqual(plane.hit(at: CGPoint(x: cell.minX + cell.width * fraction, y: cell.minY + 1))?.key, key)
                    }
                }
            }
        }
    }

    func testBothModeButtonsCancelDragsAndRejectOverlappingKeyContacts() throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        for id in ["searchEmoji", "keyboardSettingsToggle"] {
            let button = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? DeliberateTapButton }
                .first { $0.accessibilityIdentifier == id })
            let center = CGPoint(x: 22, y: 22)
            XCTAssertTrue(button.beginTap(at: center))
            button.moveTap(to: CGPoint(x: 22, y: 48))
            button.moveTap(to: center)
            XCTAssertFalse(button.validTap)
            XCTAssertTrue(button.beginTap(at: center))
            button.moveTap(to: CGPoint(x: 32, y: 22))
            XCTAssertFalse(button.validTap)
            XCTAssertTrue(button.beginTap(at: center))
            let contact = NSObject()
            controller.plane.beginContact(ObjectIdentifier(contact))
            controller.plane.beginPress(try physicalHit("a"))
            XCTAssertFalse(button.validTap)
            button.sendActions(for: .touchUpInside)
            XCTAssertFalse(controller.isShowingEmoji)
            XCTAssertFalse(controller.isShowingSettings)
            controller.plane.cancelPress()
            controller.plane.endContact(ObjectIdentifier(contact))
            let first = NSObject(), second = NSObject()
            controller.plane.beginContact(ObjectIdentifier(first))
            controller.plane.beginContact(ObjectIdentifier(second))
            controller.plane.endContact(ObjectIdentifier(first))
            button.sendActions(for: .touchUpInside)
            XCTAssertFalse(controller.isShowingEmoji)
            XCTAssertFalse(controller.isShowingSettings)
            controller.plane.endContact(ObjectIdentifier(second))
            XCTAssertTrue(button.beginTap(at: center))
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.isShowingEmoji, id == "searchEmoji")
            XCTAssertEqual(controller.isShowingSettings, id == "keyboardSettingsToggle")
            controller.hideEmoji()
            controller.hideSettings()
        }
    }

    func testEmojiRejectsConcurrentKeyContactAndAcceptsImmediateIntentionalTap() throws {
        func findButton(_ view: UIView) -> UIButton? {
            if let button = view as? UIButton, button.accessibilityIdentifier == "searchEmoji" { return button }
            return view.subviews.compactMap(findButton).first
        }
        let button = try XCTUnwrap(findButton(controller.view))
        let frame = try XCTUnwrap(controller.plane.keys.first { $0.0 == "a" }?.1)
        controller.plane.beginPress(KeyHit(key: "a", point: CGPoint(x: frame.midX, y: frame.midY), frame: frame))
        button.sendActions(for: .touchUpInside)
        XCTAssertFalse(controller.isShowingEmoji)
        controller.plane.cancelPress()
        let first = NSObject(), second = NSObject()
        controller.plane.beginContact(ObjectIdentifier(first))
        controller.plane.beginContact(ObjectIdentifier(second))
        controller.plane.endContact(ObjectIdentifier(first))
        button.sendActions(for: .touchUpInside)
        XCTAssertFalse(controller.isShowingEmoji)
        XCTAssertTrue(controller.plane.hasActiveContact)
        controller.plane.endContact(ObjectIdentifier(second))
        key("a")
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.isShowingEmoji)
        XCTAssertFalse(controller.emojiResults.results.isEmpty)
    }

    func testFirstAppearanceAndReopeningRefreshLayoutWithoutLoadingEmoji() {
        controller.viewWillDisappear(false)
        controller.storage.language = .german
        controller.storage.numberRow = true
        controller.storage.keyboardHand = .right
        controller.viewWillAppear(false)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.plane.language, .german)
        XCTAssertTrue(controller.plane.numberRow)
        XCTAssertTrue(controller.emojiResults.results.isEmpty)
        controller.demoText = "Please send teh"
        controller.textDidChange(nil)
        key("space")
        XCTAssertEqual(controller.context, "Please send the ")
        controller.showEmoji()
        XCTAssertFalse(controller.emojiResults.results.isEmpty)
    }

    func testTouchMapUsesTypingResolutionAndPreservesFunctionBoundaries() throws {
        let plane = controller.plane
        let canvas = TouchZoneCanvas()
        var model = TouchModel()
        for _ in 0..<20 { model.learn(key: "f", x: 0.4, y: 0) }
        for _ in 0..<120 where !model.hasApprovedModel {
            if model.shouldValidateNext { model.validate(baselineCorrect: false, activeCorrect: false, candidateCorrect: true) }
            else { model.learn(key: "f", x: 0.4, y: 0) }
        }
        XCTAssertTrue(model.hasApprovedModel)
        plane.touchModel = model
        for page in [0, 1, 2] {
            plane.page = page
            plane.layoutIfNeeded()
            canvas.model = plane.touchModel
            canvas.keys = plane.keys
            canvas.sourceBounds = plane.bounds
            canvas.page = plane.page
            for (key, frame) in plane.keys {
                if key.count > 1 || key.first?.isLetter != true {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    XCTAssertEqual(try XCTUnwrap(canvas.resolvedKey(at: center)).0, key)
                }
                for point in [CGPoint(x: frame.midX, y: frame.midY), CGPoint(x: frame.minX + 1, y: frame.maxY - 1)] {
                    let typed = try XCTUnwrap(plane.resolvedKey(at: point))
                    let mapped = try XCTUnwrap(canvas.resolvedKey(at: point))
                    XCTAssertEqual(mapped.0, typed.0)
                    XCTAssertEqual(mapped.1, typed.1)
                }
            }
            if page == 0 {
                let b = try XCTUnwrap(plane.keys.first { $0.0 == "b" }?.1)
                let point = CGPoint(x: b.minX + 1, y: b.maxY - 1)
                XCTAssertEqual(try XCTUnwrap(canvas.resolvedKey(at: point)).0, "b")
            }
        }
    }

    func testHiddenTouchMapRefreshesKeyFramesAfterRotationAndOneHandResize() throws {
        controller.showSettings()
        controller.showTouchDiagnostics()
        func findCanvas(_ view: UIView) -> TouchZoneCanvas? {
            if let canvas = view as? TouchZoneCanvas { return canvas }
            return view.subviews.compactMap(findCanvas).first
        }
        let canvas = try XCTUnwrap(findCanvas(controller.touchDiagnostics))
        for (width, compact, hand) in [(CGFloat(844), true, KeyboardHand.full), (CGFloat(390), false, .right)] {
            controller.traitOverrides.verticalSizeClass = compact ? .compact : .regular
            controller.view.updateTraitsIfNeeded()
            controller.storage.keyboardHand = hand
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: compact ? 196 : 244)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            XCTAssertTrue(controller.plane.isHidden)
            XCTAssertEqual(canvas.sourceBounds, controller.plane.bounds)
            XCTAssertEqual(try XCTUnwrap(canvas.keys.map { $0.1.maxX }.max()), canvas.sourceBounds.maxX, accuracy: 0.01)
            XCTAssertEqual(try XCTUnwrap(canvas.keys.map { $0.1.maxY }.max()), canvas.sourceBounds.maxY, accuracy: 0.01)
            let corner = CGPoint(x: canvas.sourceBounds.maxX - 1, y: canvas.sourceBounds.maxY - 1)
            XCTAssertEqual(try XCTUnwrap(canvas.resolvedKey(at: corner)).0, "return")
        }
    }

    func testSuggestionPunctuationSupportsMissingAfterContextAndOwnSelectionCallbacks() {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for after: String? in [nil, "", " next"] {
            for notification in ["none", "willDid", "didOnly", "textThenDid"] {
                for punctuation in [".", ",", "?", "!", ":", ";"] {
                    proxy.after = after
                    proxy.text = "send det"
                    controller.textDidChange(nil)
                    controller.plane.page = 0
                    controller.selectSuggestion("details")
                    switch notification {
                    case "willDid": controller.selectionWillChange(nil); controller.selectionDidChange(nil)
                    case "didOnly": controller.selectionDidChange(nil)
                    case "textThenDid": controller.textDidChange(nil); controller.selectionDidChange(nil)
                    default: break
                    }
                    if punctuation != "." && punctuation != "," { key("page") }
                    key(punctuation)
                    XCTAssertEqual(proxy.text, "send details" + punctuation, notification + " / " + punctuation)
                    XCTAssertEqual(proxy.after, after)
                }
            }
        }
    }

    func testManualSpaceAfterSuggestionSurvivesCallbacksAndPunctuation() {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for after: String? in [nil, ""] {
            for punctuation in [".", "?"] {
                proxy.after = after
                proxy.text = "send "
                controller.textDidChange(nil)
                controller.selectSuggestion("details")
                key("space")
                XCTAssertEqual(proxy.text, "send details  ")
                controller.selectionWillChange(nil)
                controller.textDidChange(nil)
                controller.selectionDidChange(nil)
                key(punctuation)
                XCTAssertEqual(proxy.text, "send details  " + punctuation)
            }
        }
    }

    func testSuggestionSpaceClosesBeforePunctuationAcrossSymbolPages() {
        for punctuation in [".", ",", "?", "!", ":", ";"] {
            controller.demoText = "send "
            controller.textDidChange(nil)
            controller.selectSuggestion("details")
            key("page")
            key(punctuation)
            XCTAssertEqual(controller.context, "send details" + punctuation)
            key("space")
            XCTAssertEqual(controller.context, "send details" + punctuation + " ")
        }
    }

    func testSuggestionSpaceOwnershipRejectsManualSpacesAndHostChanges() {
        for text in ["word ", "word  ", "word\n", " "] {
            controller.demoText = text
            controller.textDidChange(nil)
            key("?")
            XCTAssertEqual(controller.context, text + "?")
        }
        controller.demoText = "word"
        controller.textDidChange(nil)
        key("space")
        key(".")
        XCTAssertEqual(controller.context, "word .")
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        for change in ["document", "selection", "after", "missing", "delete", "cursor"] {
            proxy.contextAvailable = true
            proxy.selection = nil
            proxy.after = ""
            proxy.text = ""
            controller.textDidChange(nil)
            controller.selectSuggestion("details")
            switch change {
            case "document": proxy.documentIdentifier = UUID()
            case "selection": proxy.selection = "selected"
            case "after": proxy.after = "new text"
            case "missing": proxy.contextAvailable = false
            case "cursor":
                controller.selectionWillChange(nil)
                proxy.text.removeLast()
                proxy.after = " "
                controller.selectionDidChange(nil)
                controller.selectionWillChange(nil)
                proxy.text += " "
                proxy.after = ""
                controller.selectionDidChange(nil)
            default: key("delete"); key("space")
            }
            let before = proxy.text
            key("?")
            XCTAssertEqual(proxy.text, before + "?", change)
        }
    }

    func testModeControlsKeepScreenPositionsAndRepeatedTapsPreserveData() throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func control(_ id: String) throws -> UIButton {
            try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == id })
        }
        func frame(_ button: UIButton) -> CGRect {
            let local = button.convert(button.bounds, to: controller.view)
            return local.offsetBy(dx: 0, dy: -controller.view.bounds.height)
        }
        func layout() {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let height = KeyboardLayout.height(compact: controller.plane.compact,
                emoji: controller.isSearchingEmoji, size: controller.storage.keyboardSize,
                numberRow: controller.storage.numberRow)
            controller.view.frame.size.height = height
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
        for (width, compact) in [(264.0, false), (390.0, false), (844.0, true)] {
            controller.traitOverrides.verticalSizeClass = compact ? .compact : .regular
            controller.view.updateTraitsIfNeeded()
            controller.view.frame.size.width = width
            for hand in KeyboardHand.allCases {
                controller.storage.keyboardHand = hand
                for privateMode in [false, true] {
                    controller.setPrivateTyping(privateMode)
                    controller.demoText = "Keep this text"
                    layout()
                    let gear = try control("keyboardSettingsToggle")
                    let emoji = try control("searchEmoji")
                    let gearFrame = frame(gear)
                    let emojiFrame = frame(emoji)
                    let planeFrame = controller.plane.convert(controller.plane.bounds, to: controller.view)
                    let emojiLocal = emoji.convert(emoji.bounds, to: controller.view)
                    let gearLocal = gear.convert(gear.bounds, to: controller.view)
                    XCTAssertEqual(gearLocal.minX, planeFrame.minX + 6, accuracy: 0.5)
                    XCTAssertEqual(emojiLocal.maxX, planeFrame.maxX - 6, accuracy: 0.5)
                    for button in [emoji, gear] {
                        let local = button.convert(button.bounds, to: controller.view)
                        XCTAssertEqual(local.size, CGSize(width: 44, height: 44))
                        XCTAssertEqual(planeFrame.minY - local.maxY, 8, accuracy: 0.5)
                        let gap = CGPoint(x: local.midX, y: local.maxY + 4)
                        XCTAssertFalse(controller.view.hitTest(gap, with: nil) === button)
                        let letter = CGPoint(x: local.midX, y: planeFrame.minY + 1)
                        XCTAssertTrue(controller.view.hitTest(letter, with: nil) === controller.plane)
                        XCTAssertTrue(controller.view.hitTest(CGPoint(x: local.midX, y: local.midY), with: nil) === button)
                    }
                    let order = controller.privateIndicator.superview?.accessibilityElements as? [UIView]
                    XCTAssertTrue(order?.first === gear)
                    XCTAssertTrue(order?.last === emoji)
                    let learning = controller.storage.learning
                    let correction = controller.storage.autocorrection
                    let history = controller.storage.emojiUsage
                    gear.sendActions(for: .touchUpInside)
                    layout()
                    XCTAssertTrue(controller.isShowingSettings)
                    XCTAssertEqual(frame(gear), gearFrame)
                    XCTAssertEqual(frame(emoji), emojiFrame)
                    controller.showTouchDiagnostics()
                    layout()
                    gear.sendActions(for: .touchUpInside)
                    layout()
                    XCTAssertFalse(controller.isShowingSettings)
                    XCTAssertFalse(controller.isShowingTouchDiagnostics)
                    emoji.sendActions(for: .touchUpInside)
                    layout()
                    XCTAssertTrue(controller.isShowingEmoji)
                    XCTAssertEqual(frame(emoji), emojiFrame)
                    controller.startEmojiSearch()
                    layout()
                    XCTAssertEqual(frame(emoji), emojiFrame)
                    XCTAssertEqual(frame(gear), gearFrame)
                    emoji.sendActions(for: .touchUpInside)
                    layout()
                    XCTAssertFalse(controller.isShowingEmoji)
                    XCTAssertEqual(controller.context, "Keep this text")
                    XCTAssertEqual(controller.storage.learning, learning)
                    XCTAssertEqual(controller.storage.autocorrection, correction)
                    XCTAssertEqual(controller.storage.emojiUsage.ranked, history.ranked)
                }
            }
        }
    }

    func testEmojiHistoryConfirmationResetsOnSearchSettingsAndDismissal() throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func button(_ label: String) throws -> UIButton {
            try XCTUnwrap(descendants(controller.emojiResults).compactMap { $0 as? UIButton }
                .first { $0.accessibilityLabel == label })
        }
        controller.storage.recordEmoji("\u{1F600}")
        for path in ["search", "settings", "dismiss"] {
            controller.showEmoji()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let clear = try button("Clear frequently used emojis")
            clear.sendActions(for: .touchUpInside)
            let confirm = try button("Confirm clear emoji history")
            var ancestor: UIView? = confirm
            while let view = ancestor {
                XCTAssertFalse(view.isHidden)
                ancestor = view.superview
            }
            switch path {
            case "search": controller.startEmojiSearch(); controller.showEmojiBrowse()
            case "settings": controller.showSettings(); controller.hideSettings(); controller.showEmoji()
            default: controller.viewWillDisappear(false); controller.viewWillAppear(false); controller.showEmoji()
            }
            confirm.sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.storage.emojiUsage.ranked.first?.text, "\u{1F600}", path)
            controller.hideEmoji()
        }
    }

    func testWesternCorrectionsCommitAndUndoOnEitherLayout() {
        let samples: [(PreferredLanguage, String, String, String)] = [
            (.spanish, "muchas gracias ", "gracais", "gracias"),
            (.french, "merci beaucoup ", "bonjor", "bonjour"),
            (.italian, "grazie per ", "buongirono", "buongiorno"),
            (.portuguese, "muito obrigado ", "obrigdao", "obrigado"),
            (.dutch, "bedankt voor ", "bednakt", "bedankt"),
            (.swedish, "vi ses ", "tcak", "tack"),
            (.danish, "tak for ", "mrogen", "morgen"),
            (.norwegian, "takk for ", "hjelpne", "hjelpen"),
            (.finnish, "olen matkalla ", "kiitso", "kiitos")
        ]
        for layout in KeyboardLanguage.allCases {
            controller.storage.language = layout
            controller.viewWillAppear(false)
            for (preference, context, typo, word) in samples {
                controller.storage.preferredLanguage = preference
                controller.demoText = context + typo
                controller.textDidChange(nil)
                key("space")
                XCTAssertEqual(controller.context, context + word + " ", preference.rawValue)
                key("delete")
                XCTAssertEqual(controller.context, context + typo, preference.rawValue)
                key("space")
                XCTAssertEqual(controller.context, context + typo + " ", preference.rawValue)
            }
        }
    }

    func testDictionaryLanguagesDoNotLoadANeuralModelAndEnglishStillLoadsAfterward() async {
        controller.storage.neuralPrediction = true
        let contexts: [TypingLanguage: String] = [
            .german: "ich sehe eine Katz", .afrikaans: "baie dankie ", .spanish: "muchas gracias ", .french: "merci beaucoup ",
            .italian: "grazie per ", .portuguese: "muito obrigado ", .dutch: "bedankt voor ",
            .swedish: "vi ses i morgon ", .danish: "tak for din ",
            .norwegian: "takk for hjelpen ", .finnish: "olen matkalla kotiin "
        ]
        for language in TypingLanguage.allCases where language != .english {
            let unexpected = expectation(description: language.rawValue + " does not load a neural model")
            unexpected.isInverted = true
            controller.neuralService = NeuralPredictionService { _, _ in
                unexpected.fulfill()
                throw NeuralPredictionError.invalidModel
            }
            controller.storage.preferredLanguage = PreferredLanguage(rawValue: language.rawValue)!
            controller.demoText = contexts[language]!
            controller.textDidChange(nil)
            await fulfillment(of: [unexpected], timeout: 0.2)
            XCTAssertEqual(controller.neuralEngine, "Multilingual dictionary", language.rawValue)
            if language == .german {
                let visibleWords = controller.suggestionButtons.filter { !$0.isHidden }.compactMap(\.currentTitle)
                XCTAssertTrue(visibleWords.contains("Katze"), "Visible suggestions: \(visibleWords)")
            }
        }
        let english = expectation(description: "English model loads after a language change")
        controller.neuralService = NeuralPredictionService { language, _ in
            XCTAssertEqual(language, .english)
            english.fulfill()
            throw NeuralPredictionError.invalidModel
        }
        controller.storage.preferredLanguage = .automatic
        controller.demoText = "we should review "
        controller.textDidChange(nil)
        await fulfillment(of: [english], timeout: 2)
    }

    func testItalianAndSwedishCaseOnlyLexiconEntriesPreserveTypedCase() {
        controller.registerLexiconEntry(input: "i", replacement: "I")
        for (preference, context) in [(PreferredLanguage.italian, "vediamo "), (.swedish, "vi ses ")] {
            controller.storage.preferredLanguage = preference
            for word in ["i", "I"] {
                controller.demoText = context + word
                controller.textDidChange(nil)
                key("space")
                XCTAssertEqual(controller.context, context + word + " ")
            }
        }
    }


    func testAlternatePopupUsesHeaderAndStationaryReleaseCommitsHighlightedOption() throws {
        controller.demoText = "word "
        controller.textDidChange(nil)
        let plane = controller.plane
        for value in ["e", "s", "."] {
            let hit = try physicalHit(value)
            plane.beginPress(hit)
            plane.showAlternates()
            XCTAssertFalse(controller.alternatePopup.isHidden)
            let popup = controller.alternatePopup
            let keyFrame = plane.convert(hit.frame, to: controller.view)
            XCTAssertGreaterThanOrEqual(popup.frame.minY, 0)
            XCTAssertLessThanOrEqual(popup.frame.maxY, keyFrame.minY)
            XCTAssertFalse(popup.isUserInteractionEnabled)
            let selected = plane.alternateOptions[try XCTUnwrap(plane.alternateIndex)]
            let original = controller.context
            plane.endPress(at: hit.point)
            XCTAssertEqual(controller.context, original + selected)
            XCTAssertTrue(popup.isHidden)
        }
    }

    func testAlternateSelectionReturnsToNearestOptionOverTheSourceKeyAndCancelsOutside() throws {
        let plane = controller.plane
        controller.demoText = "word "
        controller.textDidChange(nil)
        let hit = try physicalHit("u")
        plane.beginPress(hit)
        plane.showAlternates()
        let menu = plane.alternateFrame
        let target = CGPoint(x: menu.minX + 18, y: menu.midY)
        plane.movePress(to: target)
        XCTAssertEqual(plane.alternateIndex, 0)
        plane.movePress(to: hit.point)
        XCTAssertEqual(plane.alternateIndex, 2)
        plane.endPress(at: hit.point)
        XCTAssertEqual(controller.context, "word \u{00fb}")
        plane.beginPress(hit)
        plane.showAlternates()
        plane.movePress(to: CGPoint(x: -100, y: -100))
        plane.endPress(at: target)
        XCTAssertEqual(controller.context, "word \u{00fb}")
        XCTAssertTrue(controller.alternatePopup.isHidden)
        plane.beginPress(hit)
        plane.showAlternates()
        controller.showSettings()
        plane.endPress(at: target)
        XCTAssertEqual(controller.context, "word \u{00fb}")
        XCTAssertTrue(controller.alternatePopup.isHidden)
    }

    func testAlternateOverlayFitsLongMenusAcrossSizesAndRotationCancelsSelection() throws {
        let plane = controller.plane
        for width in [280.0, 390, 844] {
            controller.view.frame.size = CGSize(width: width, height: 244)
            controller.view.layoutIfNeeded()
            for value in ["a", "e", "s", ",", "."] {
                let hit = try physicalHit(value)
                plane.beginPress(hit)
                plane.showAlternates()
                XCTAssertTrue(controller.view.bounds.contains(controller.alternatePopup.frame))
                XCTAssertGreaterThanOrEqual(plane.alternateFrame.width / CGFloat(plane.alternateOptions.count), 28)
                plane.cancelPress()
            }
        }
        let hit = try physicalHit("a")
        plane.beginPress(hit)
        plane.showAlternates()
        controller.view.frame.size.width = 390
        controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.alternatePopup.isHidden)
    }

    func testCursorFeedbackRequiresSupportedMovementAndResetsOnInterruption() throws {
        let plane = controller.plane
        let space = try physicalHit("space")
        plane.beginKey(space)
        plane.moveSpace(to: CGPoint(x: space.point.x + 36, y: space.point.y))
        XCTAssertFalse(plane.movingCursor)
        plane.endSpace(at: space.point)
        XCTAssertEqual(controller.context, " ")
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        plane.beginKey(space)
        plane.moveSpace(to: CGPoint(x: space.point.x + 3, y: space.point.y))
        XCTAssertFalse(plane.movingCursor)
        plane.endSpace(at: space.point)
        XCTAssertEqual(proxy.text, " ")
        plane.beginKey(space)
        plane.moveSpace(to: CGPoint(x: space.point.x + 36, y: space.point.y))
        XCTAssertTrue(plane.movingCursor)
        XCTAssertEqual(proxy.cursorOffsets, [3])
        XCTAssertEqual(plane.keyFill(for: "space"), UIColor.label)
        controller.showSettings()
        XCTAssertFalse(plane.movingCursor)
        plane.endSpace(at: space.point)
        XCTAssertEqual(proxy.text, " ")
    }

    func testHostFieldKeysKeepGeometryAndCancelOldPresses() throws {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        let original = try physicalHit(",").frame
        for (type, value) in [(UIKeyboardType.emailAddress, "@"), (.URL, "/"), (.default, ",")] {
            let pending = try physicalHit("e")
            controller.plane.beginPress(pending)
            controller.plane.showAlternates()
            proxy.keyboardType = type
            controller.textDidChange(nil)
            XCTAssertTrue(controller.alternatePopup.isHidden)
            controller.plane.endPress(at: pending.point)
            let punctuation = try physicalHit(value)
            XCTAssertEqual(punctuation.frame, original)
            let before = proxy.text
            controller.plane.beginKey(punctuation)
            XCTAssertEqual(proxy.text, before + value)
            key("page")
            XCTAssertEqual(controller.plane.keys.last { $0.0 == "," }?.1, original)
            key("page")
        }
        proxy.keyboardType = .emailAddress
        controller.textDidChange(nil)
        controller.showEmoji()
        controller.startEmojiSearch()
        XCTAssertEqual(try physicalHit(",").frame, original)
        XCTAssertFalse(controller.plane.cursorMovementEnabled)
        controller.hideEmoji()
        XCTAssertEqual(try physicalHit("@").frame, original)
        XCTAssertTrue(controller.storage.multilingualMemory.words.isEmpty)
    }

    func testGroupedEmojiTonePanelUsesExactVariantAndRejectsStaleActions() throws {
        let base = "\u{1F44D}", tone = "\u{1F44D}\u{1F3FF}"
        controller.showEmoji()
        controller.startEmojiSearch()
        for value in ["t", "h", "u", "m", "b", "s"] { key(value) }
        XCTAssertTrue(controller.emojiResults.results.contains { $0.text == base })
        XCTAssertFalse(controller.emojiResults.results.contains { $0.text == tone })
        controller.showEmojiTones(for: base)
        XCTAssertFalse(controller.emojiTonePanel.isHidden)
        XCTAssertEqual(controller.context, "")
        controller.selectEmojiTone("\u{1F431}")
        XCTAssertEqual(controller.context, "")
        controller.selectEmojiTone(tone)
        XCTAssertEqual(controller.context, tone)
        XCTAssertFalse(controller.isShowingEmoji)
        XCTAssertEqual(controller.storage.emojiUsage.ranked.first?.text, tone)
        controller.selectEmojiTone(base)
        XCTAssertEqual(controller.context, tone)
        let historyBeforePrivate = controller.storage.emojiUsage
        controller.showEmoji()
        controller.showEmojiTones(for: base)
        controller.setPrivateTyping(true)
        XCTAssertTrue(controller.emojiTonePanel.isHidden)
        controller.selectEmojiTone(tone)
        XCTAssertEqual(controller.context, tone)
        controller.showEmojiTones(for: base)
        controller.selectEmojiTone(tone)
        XCTAssertEqual(controller.context, tone + tone)
        controller.setPrivateTyping(false)
        XCTAssertEqual(controller.storage.emojiUsage, historyBeforePrivate)
    }

    func testTonePanelCancelAndModeChangesRejectRetainedButtons() throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let base = "\u{1F44D}"
        controller.showEmoji()
        controller.showEmojiTones(for: base)
        let panel = controller.emojiTonePanel
        let button = try XCTUnwrap(descendants(panel).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel?.hasPrefix("Insert ") == true
        })
        let cancel = try XCTUnwrap(descendants(panel).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == "Cancel skin tone selection"
        })
        cancel.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.context, "")
        controller.showEmojiTones(for: base)
        controller.startEmojiSearch()
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(panel.isHidden)
        XCTAssertEqual(controller.context, "")
    }

    func testEmojiCategoryJumpAndSearchBackPreserveBrowsePositionWithoutReordering() throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        controller.showEmoji()
        controller.view.layoutIfNeeded()
        let browse = controller.emojiResults
        let collection = try XCTUnwrap(descendants(browse).compactMap { $0 as? UICollectionView }.first)
        let category = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == "Food emoji"
        })
        category.sendActions(for: .touchUpInside)
        collection.layoutIfNeeded()
        let before = collection.contentOffset
        XCTAssertGreaterThan(before.y, 0)
        XCTAssertEqual(collection.indexPathsForVisibleItems.sorted().first?.section, 4)
        let entries = browse.results
        let selected = try XCTUnwrap(collection.indexPathsForVisibleItems.sorted().first)
        let text = (collection.cellForItem(at: selected)?.contentConfiguration as? UIListContentConfiguration)?.text
        let emoji = try XCTUnwrap(text)
        let anchorY = try XCTUnwrap(collection.layoutAttributesForItem(at: selected)).frame.minY - collection.contentOffset.y
        controller.storage.recordEmoji(emoji)
        controller.selectEmoji(emoji)
        controller.selectEmoji(emoji)
        XCTAssertEqual(controller.context, emoji + emoji)
        XCTAssertEqual(browse.results, entries)
        XCTAssertEqual(collection.contentOffset, before)
        controller.startEmojiSearch()
        key("c")
        controller.showEmojiBrowse()
        collection.layoutIfNeeded()
        let visible = collection.indexPathsForVisibleItems.compactMap { path in
            (collection.cellForItem(at: path)?.contentConfiguration as? UIListContentConfiguration)?.text
        }
        XCTAssertTrue(visible.contains(emoji))
        XCTAssertEqual(collection.indexPathsForVisibleItems.sorted().first?.section, 4)
        XCTAssertEqual(try XCTUnwrap(collection.layoutAttributesForItem(at: selected)).frame.minY - collection.contentOffset.y,
                       anchorY, accuracy: 0.5)
        controller.clearEmojiHistory()
        XCTAssertEqual(collection.contentOffset, .zero)
    }

    func testCurrencyMenusInsertExactCharactersOnBothSymbolPages() throws {
        controller.demoText = "word "
        controller.textDidChange(nil)
        for (page, source, selected) in [(1, "\u{20ac}", "$"), (2, "$", "\u{20ac}"),
                                         (2, "\u{00a3}", "\u{00a5}"), (2, "\u{00a5}", "\u{00a2}")] {
            controller.plane.page = page
            let hit = try physicalHit(source)
            controller.plane.beginPress(hit)
            controller.plane.showAlternates()
            let index = try XCTUnwrap(controller.plane.alternateOptions.firstIndex(of: selected))
            let menu = controller.plane.alternateFrame
            let before = controller.context
            controller.plane.endPress(at: CGPoint(x: menu.minX + (CGFloat(index) + 0.5) * menu.width / 4, y: menu.midY))
            XCTAssertEqual(controller.context, before + selected)
        }
    }

    func testPopupVisualStatesKeepArtworkInsideRootBounds() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 244))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for (name, style, contrast) in [("Light", UIUserInterfaceStyle.light, false), ("Dark", .dark, false),
                                         ("High contrast", .light, true)] {
            window.overrideUserInterfaceStyle = style
            controller.overrideUserInterfaceStyle = style
            controller.view.overrideUserInterfaceStyle = style
            controller.plane.highContrast = contrast
            controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 244)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            XCTAssertEqual(controller.view.bounds.size, CGSize(width: 390, height: 244))
            controller.plane.beginPress(try physicalHit("e"))
            controller.plane.showAlternates()
            let menu = controller.plane.alternateFrame
            controller.plane.movePress(to: CGPoint(x: menu.minX + menu.width * 0.5, y: menu.midY))
            controller.view.layoutIfNeeded()
            XCTAssertEqual(controller.plane.traitCollection.userInterfaceStyle, style)
            var image: UIImage!
            UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                controller.plane.layer.setNeedsDisplay()
                controller.alternatePopup.layer.setNeedsDisplay()
                controller.plane.layer.displayIfNeeded()
                controller.alternatePopup.layer.displayIfNeeded()
                image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { context in
                    controller.view.layer.render(in: context.cgContext)
                }
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Raised alternate menu " + name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(controller.view.bounds.contains(controller.alternatePopup.frame))
            controller.plane.cancelInteractions()
        }
    }

    func testSameTypeHostDocumentChangeCancelsPopupAndCursor() throws {
        let proxy = TestDocumentProxy()
        controller.documentProxy = proxy
        controller.demoMode = false
        controller.textDidChange(nil)
        let hit = try physicalHit("e")
        controller.plane.beginPress(hit)
        controller.plane.showAlternates()
        proxy.documentIdentifier = UUID()
        controller.textDidChange(nil)
        controller.plane.endPress(at: hit.point)
        XCTAssertEqual(proxy.text, "")
        XCTAssertTrue(controller.alternatePopup.isHidden)
        let space = try physicalHit("space")
        controller.plane.beginKey(space)
        controller.plane.moveSpace(to: CGPoint(x: space.point.x + 24, y: space.point.y))
        XCTAssertTrue(controller.plane.movingCursor)
        proxy.documentIdentifier = UUID()
        controller.textDidChange(nil)
        XCTAssertFalse(controller.plane.movingCursor)
        controller.plane.endSpace(at: space.point)
        XCTAssertEqual(proxy.text, "")
    }

    func testExplicitToneSearchKeepsExactVariantSelectable() {
        controller.showEmoji()
        controller.startEmojiSearch()
        for character in "thumbs up dark" { key(character == " " ? "space" : String(character)) }
        let tone = "\u{1F44D}\u{1F3FF}"
        XCTAssertTrue(controller.emojiResults.results.contains { $0.text == tone })
        controller.selectEmoji(tone)
        XCTAssertEqual(controller.context, tone)
        XCTAssertFalse(controller.isShowingEmoji)
    }

    func testTonePanelRotationAndDismissalInvalidateOldButtons() throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        for dismiss in [false, true] {
            controller.showEmoji()
            controller.showEmojiTones(for: "\u{1F44D}")
            let button = try XCTUnwrap(descendants(controller.emojiTonePanel).compactMap { $0 as? UIButton }.first {
                $0.accessibilityLabel?.hasPrefix("Insert ") == true
            })
            if dismiss { controller.viewWillDisappear(false) }
            else {
                controller.view.frame.size.width = 280
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
            }
            XCTAssertTrue(controller.emojiTonePanel.isHidden)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.context, "")
            controller.hideEmoji()
        }
    }

    func testCompactEmojiBrowseKeepsFullRowsAndCategoryFooterWithAndWithoutGlobe() async throws {
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        controller.demoMode = false
        controller.documentProxy = TestDocumentProxy()
        controller.traitOverrides.verticalSizeClass = .compact
        for width in [280.0, 844] {
          for globe in [false, true] {
            controller.clearEmojiHistory()
            controller.storage.keyboardSize = .compact
            controller.plane.showsGlobe = globe
            controller.storage.recordEmoji("\u{1F44D}")
            controller.showEmoji()
            controller.view.frame.size = CGSize(width: width, height: KeyboardLayout.height(compact: true, size: .compact))
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            await Task.yield()
            let collection = try XCTUnwrap(descendants(controller.emojiResults).compactMap { $0 as? UICollectionView }.first)
            collection.layoutIfNeeded()
            XCTAssertGreaterThanOrEqual(collection.bounds.height, 44)
            let first = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            XCTAssertGreaterThanOrEqual(first.frame.minY, collection.bounds.minY)
            XCTAssertLessThanOrEqual(first.frame.maxY, collection.bounds.maxY,
                                    "Grid: \(collection.bounds), results: \(controller.emojiResults.bounds)")
            let categories = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "emojiCategories" && !$0.isHidden })
            XCTAssertFalse(categories.isHidden)
            XCTAssertEqual(categories.frame.height, 44, accuracy: 0.5)
            let clear = try XCTUnwrap(descendants(categories).compactMap { $0 as? UIButton }.first {
                $0.accessibilityLabel == "Clear emoji history"
            })
            XCTAssertFalse(clear.isHidden)
            clear.sendActions(for: .touchUpInside)
            clear.sendActions(for: .touchUpInside)
            XCTAssertFalse(controller.storage.emojiUsage.ranked.isEmpty)
            let cancel = try XCTUnwrap(descendants(controller.emojiResults).compactMap { $0 as? UIButton }.first {
                $0.accessibilityLabel == "Cancel clear emoji history"
            })
            cancel.sendActions(for: .touchUpInside)
            XCTAssertFalse(collection.isHidden)
            for (label, section) in [("Food emoji", 4), ("Flags emoji", 9)] {
                let button = try XCTUnwrap(descendants(categories).compactMap { $0 as? UIButton }.first {
                    $0.accessibilityLabel == label
                })
                button.sendActions(for: .touchUpInside)
                collection.layoutIfNeeded()
                XCTAssertTrue(button.isSelected)
                XCTAssertTrue(collection.indexPathsForVisibleItems.contains { $0.section == section })
            }
            controller.hideEmoji()
          }
        }
    }

    func testHostFieldKeysRestoreAfterOwnedEmojiSearchResignsFocus() throws {
        final class FocusAwareProxy: TestDocumentProxy {
            var searchFocus: () -> Bool = { false }
            var hostType = UIKeyboardType.emailAddress
            override var keyboardType: UIKeyboardType {
                get { searchFocus() ? .default : hostType }
                set { hostType = newValue }
            }
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let proxy = FocusAwareProxy()
        proxy.searchFocus = { [weak controller] in controller?.emojiSearch.hasFocus == true }
        controller.demoMode = false
        controller.documentProxy = proxy
        for (type, fieldKey) in [(UIKeyboardType.emailAddress, "@"), (.URL, "/")] {
            proxy.hostType = type
            controller.textDidChange(nil)
            XCTAssertEqual(controller.plane.fieldKey, fieldKey)
            controller.showEmoji()
            controller.startEmojiSearch()
            XCTAssertTrue(controller.emojiSearch.hasFocus)
            controller.textDidChange(nil)
            XCTAssertEqual(controller.plane.fieldKey, ",")
            controller.showEmojiBrowse()
            XCTAssertFalse(controller.emojiSearch.hasFocus)
            XCTAssertEqual(controller.plane.fieldKey, fieldKey)
            controller.startEmojiSearch()
            XCTAssertTrue(controller.emojiSearch.hasFocus)
            for value in ["t", "h", "u", "m", "b", "s"] { key(value) }
            controller.showEmojiTones(for: "\u{1F44D}")
            controller.selectEmojiTone("\u{1F44D}\u{1F3FF}")
            XCTAssertFalse(controller.isShowingEmoji)
            XCTAssertFalse(controller.emojiSearch.hasFocus)
            XCTAssertEqual(controller.plane.fieldKey, fieldKey)
            XCTAssertTrue(controller.plane.cursorMovementEnabled)
        }
        XCTAssertEqual(proxy.text, "\u{1F44D}\u{1F3FF}\u{1F44D}\u{1F3FF}")
    }

    func testStaleOwnedSearchTraitsPreserveHostPolicyAndAllowDistinctNormalField() throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.demoMode = false
        controller.storage.learning = true
        controller.storage.autocorrection = true
        controller.registerLexiconEntry(input: "teh", replacement: "the")
        for (type, correction, fieldKey) in [(UIKeyboardType.emailAddress, UITextAutocorrectionType.yes, "@"),
                                              (.URL, .yes, "/"), (.default, .no, ",")] {
            let proxy = TestDocumentProxy()
            proxy.keyboardType = type
            proxy.autocorrectionType = correction
            controller.documentProxy = proxy
            controller.textDidChange(nil)
            controller.showEmoji()
            controller.startEmojiSearch()
            XCTAssertTrue(controller.emojiSearch.hasFocus)
            proxy.documentIdentifier = UUID()
            proxy.keyboardType = .default
            proxy.autocorrectionType = .yes
            controller.textDidChange(nil)
            XCTAssertTrue(controller.isSearchingEmoji)
            for value in ["t", "h", "u", "m", "b", "s"] { key(value) }
            controller.showEmojiTones(for: "\u{1F44D}")
            controller.selectEmojiTone("\u{1F44D}\u{1F3FF}")
            XCTAssertFalse(controller.emojiSearch.hasFocus)
            XCTAssertEqual(controller.plane.fieldKey, fieldKey)
            controller.textDidChange(nil)
            controller.selectionDidChange(nil)
            XCTAssertEqual(controller.plane.fieldKey, fieldKey)
            proxy.text = "teh"
            key("space")
            XCTAssertEqual(proxy.text, "teh ")
            proxy.documentIdentifier = UUID()
            proxy.keyboardType = .default
            proxy.autocorrectionType = .yes
            proxy.text = ""
            controller.textDidChange(nil)
            XCTAssertEqual(controller.plane.fieldKey, ",")
            for value in ["t", "e", "h", "space"] { key(value) }
            XCTAssertEqual(proxy.text, "the ")
        }
        controller.viewWillDisappear(false)
        XCTAssertNil(controller.storage.multilingualMemory.words["teh"])
    }

    func testStaleSearchCapitalizationDoesNotReplaceTheHostPreference() throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let proxy = TestDocumentProxy()
        proxy.autocapitalizationType = .allCharacters
        controller.demoMode = false
        controller.documentProxy = proxy
        controller.textDidChange(nil)
        controller.showEmoji()
        controller.startEmojiSearch()
        XCTAssertTrue(controller.emojiSearch.hasFocus)
        proxy.documentIdentifier = UUID()
        proxy.autocapitalizationType = .none
        controller.textDidChange(nil)
        controller.hideEmoji()
        key("a")
        XCTAssertEqual(proxy.text, "A")
    }

    func testSearchExitBeforeAnyDocumentCallbackPreservesTheHostSurface() throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.demoMode = false
        for browse in [false, true] {
            let proxy = TestDocumentProxy()
            proxy.keyboardType = .emailAddress
            controller.documentProxy = proxy
            controller.textDidChange(nil)
            controller.showEmoji()
            controller.startEmojiSearch()
            XCTAssertTrue(controller.emojiSearch.hasFocus)
            proxy.documentIdentifier = UUID()
            proxy.keyboardType = .default
            if browse { controller.showEmojiBrowse() }
            else { controller.hideEmoji() }
            XCTAssertFalse(controller.emojiSearch.hasFocus)
            XCTAssertEqual(controller.plane.fieldKey, "@")
            controller.textDidChange(nil)
            XCTAssertEqual(controller.plane.fieldKey, "@")
            proxy.documentIdentifier = UUID()
            controller.textDidChange(nil)
            XCTAssertEqual(controller.plane.fieldKey, ",")
            controller.hideEmoji()
        }
    }

    func testAlternatePopupBlocksCoveredHeaderAndKeepsOwnedSearchFocus() throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(controller.view)
        let hostedHeight = controller.view.heightAnchor.constraint(equalToConstant: 244)
        controller.onEmojiSearchVisibilityChange = { visible in
            hostedHeight.constant = visible ? 288 : 244
        }
        NSLayoutConstraint.activate([
            hostedHeight,
            controller.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        controller.didMove(toParent: host)
        host.view.layoutIfNeeded()
        defer {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.demoText = "word "
        controller.textDidChange(nil)
        controller.setPrivateTyping(true)
        controller.view.layoutIfNeeded()
        let plane = controller.plane
        plane.beginPress(try physicalHit("e"))
        plane.showAlternates()
        let header = try XCTUnwrap(controller.privateIndicator.superview)
        XCTAssertFalse(header.isUserInteractionEnabled)
        let point = controller.privateIndicator.convert(CGPoint(x: 26, y: 22), to: controller.view)
        XCTAssertFalse(controller.view.hitTest(point, with: nil) === controller.privateIndicator)
        plane.cancelPress()
        XCTAssertTrue(header.isUserInteractionEnabled)
        XCTAssertTrue(controller.view.hitTest(point, with: nil) === controller.privateIndicator)
        controller.showEmoji()
        controller.startEmojiSearch()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        XCTAssertTrue(controller.emojiSearch.hasFocus)
        plane.beginPress(try physicalHit("e"))
        plane.showAlternates()
        let queryRow = try XCTUnwrap(controller.emojiSearch.superview)
        XCTAssertTrue((queryRow as? TouchBlockingStackView)?.blocksTouches == true)
        XCTAssertTrue(controller.emojiSearch.hasFocus)
        let queryPoint = controller.emojiSearch.convert(CGPoint(x: 20, y: 20), to: controller.view)
        let blockedHit = controller.view.hitTest(queryPoint, with: nil)
        XCTAssertFalse(blockedHit?.isDescendant(of: queryRow) ?? false)
        let localQueryPoint = controller.view.convert(queryPoint, to: queryRow)
        XCTAssertTrue(queryRow.bounds.contains(localQueryPoint), "Row: \(queryRow.bounds), search: \(controller.emojiSearch.frame), root: \(controller.view.bounds)")
        XCTAssertNil(queryRow.hitTest(localQueryPoint, with: nil))
        let menu = plane.alternateFrame
        let selected = try XCTUnwrap(plane.alternateOptions.first)
        plane.endPress(at: CGPoint(x: menu.minX + menu.width / CGFloat(plane.alternateOptions.count) / 2, y: menu.midY))
        XCTAssertEqual(controller.emojiQuery, selected)
        XCTAssertTrue(controller.emojiSearch.hasFocus)
        XCTAssertFalse((queryRow as? TouchBlockingStackView)?.blocksTouches == true)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let restoredQueryPoint = controller.emojiSearch.convert(CGPoint(x: 20, y: 20), to: queryRow)
        XCTAssertTrue(queryRow.bounds.contains(restoredQueryPoint), "Row: \(queryRow.bounds), search: \(controller.emojiSearch.frame), root: \(controller.view.bounds)")
        XCTAssertNotNil(queryRow.hitTest(restoredQueryPoint, with: nil))
        XCTAssertTrue(header.isUserInteractionEnabled)
        XCTAssertTrue(controller.isPrivateTyping)
        XCTAssertEqual(controller.context, "word ")
    }

    func testAlternateSelectionHasNoDeadZoneBetweenKeyAndPopup() throws {
        controller.demoText = "word "
        controller.textDidChange(nil)
        let plane = controller.plane
        for width in [264.0, 390, 844] {
            plane.frame = CGRect(x: 0, y: 0, width: width, height: 192)
            plane.layoutIfNeeded()
            for value in ["u", "a", ",", "\u{20ac}"] {
                plane.page = value == "\u{20ac}" ? 1 : 0
                let hit = try physicalHit(value)
                plane.beginPress(hit)
                plane.showAlternates()
                XCTAssertNotNil(plane.alternateIndex)
                let menu = plane.alternateFrame
                let cellWidth = menu.width / CGFloat(plane.alternateOptions.count)
                for y in [hit.point.y, hit.frame.minY - 5, (hit.frame.minY + menu.maxY) / 2, menu.midY] {
                    for index in plane.alternateOptions.indices {
                        let x = menu.minX + (CGFloat(index) + 0.5) * cellWidth
                        plane.movePress(to: CGPoint(x: x, y: y))
                        XCTAssertEqual(plane.alternateIndex, index, "key=\(value), width=\(width), y=\(y)")
                        XCTAssertEqual(controller.alternatePopup.selected, index)
                    }
                    for index in 1..<plane.alternateOptions.count {
                        let boundary = menu.minX + CGFloat(index) * cellWidth
                        plane.movePress(to: CGPoint(x: boundary - 0.01, y: y))
                        XCTAssertEqual(plane.alternateIndex, index - 1)
                        plane.movePress(to: CGPoint(x: boundary + 0.01, y: y))
                        XCTAssertEqual(plane.alternateIndex, index)
                    }
                }
                plane.movePress(to: CGPoint(x: menu.minX - 8, y: menu.midY))
                XCTAssertEqual(plane.alternateIndex, 0)
                plane.movePress(to: CGPoint(x: menu.maxX + 8, y: menu.midY))
                XCTAssertEqual(plane.alternateIndex, plane.alternateOptions.count - 1)
                plane.cancelPress()
            }
        }
    }

    func testAlternateOpeningAndPendingCompletionUseTheLatestTouch() throws {
        controller.demoText = "word "
        controller.textDidChange(nil)
        let plane = controller.plane
        let hit = try physicalHit("u")
        let start = CGPoint(x: hit.frame.minX + 0.1, y: hit.point.y)
        let moved = CGPoint(x: hit.frame.maxX - 0.1, y: hit.point.y)
        plane.beginPress(KeyHit(key: "u", point: start, frame: hit.frame))
        plane.movePress(to: moved)
        plane.showAlternates()
        XCTAssertEqual(plane.alternateIndex, 3)
        let menu = plane.alternateFrame
        let last = CGPoint(x: menu.maxX - 18, y: menu.midY)
        plane.movePress(to: last)
        XCTAssertEqual(plane.alternateOptions[try XCTUnwrap(plane.alternateIndex)], "\u{016b}")
        let second = try physicalHit("e")
        plane.beginPress(second)
        plane.endPress(at: second.point)
        XCTAssertEqual(controller.context, "word \u{016b}e")
        plane.beginPress(hit)
        plane.showAlternates()
        plane.movePress(to: last)
        XCTAssertTrue(plane.beginSymbolDrag(try physicalHit("page")))
        XCTAssertEqual(controller.context, "word \u{016b}e\u{016b}")
        plane.cancelSymbolDrag()
    }

}
