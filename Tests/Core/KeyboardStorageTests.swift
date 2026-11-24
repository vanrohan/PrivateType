import XCTest
#if SWIFT_PACKAGE
@testable import KeyboardCore
#else
@testable import SimpleKeyboard
#endif

final class KeyboardStorageTests: XCTestCase {
    func testPrivateTypingBlocksPersonalDataUseAndWritesWithoutDeletingData() throws {
        let suite = "PrivateTyping." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        var memory = LearningMemory()
        memory.learn(word: "hedging", previous: "portfolio")
        var touches = TouchModel()
        touches.learn(key: "a", x: 0.1, y: 0)
        let profile = TouchProfile(layout: .english, landscape: false, width: 390)
        storage.save(memory: memory, touches: touches, language: .english)
        storage.saveWords(memory)
        storage.saveTouches(touches, profile: profile)
        storage.recordEmoji("\u{1F600}")
        storage.setProtected("teh", enabled: true)
        let original = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        storage.privateTyping = true
        XCTAssertTrue(storage.multilingualMemory.words.isEmpty)
        XCTAssertTrue(storage.memory(for: .english).words.isEmpty)
        XCTAssertTrue(storage.touches(profile: profile).offsets.isEmpty)
        XCTAssertTrue(storage.touches(for: .english).offsets.isEmpty)
        XCTAssertTrue(storage.emojiUsage.ranked.isEmpty)
        XCTAssertTrue(storage.protectedWords.contains("teh"))
        storage.saveWords(.init())
        storage.save(memory: .init(), touches: .init(), language: .english)
        storage.saveMultilingual(memory: .init(), touches: .init(), layout: .english)
        storage.saveTouches(.init(), profile: profile)
        storage.recordEmoji("\u{1F431}")
        XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(defaults.persistentDomain(forName: suite))).isEqual(to: original))
        XCTAssertFalse(KeyboardStorage(defaults: defaults).privateTyping)
        storage.privateTyping = false
        XCTAssertEqual(storage.multilingualMemory.words["hedging"], 1)
        XCTAssertEqual(storage.touches(profile: profile).offsets["a"]?.count, 1)
        XCTAssertEqual(storage.emojiUsage.ranked.first?.text, "\u{1F600}")
        XCTAssertTrue(storage.learning)
    }

    func testCursorSpeedPersistsAndDefaultsRemainSafe() throws {
        let suite = "CursorSpeed." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(storage.cursorSpeed, .standard)
        storage.cursorSpeed = .slow
        XCTAssertEqual(KeyboardStorage(defaults: defaults).cursorSpeed, .slow)
        storage.clear()
        XCTAssertEqual(storage.cursorSpeed, .slow)
        defaults.set("invalid", forKey: "cursorSpeed")
        XCTAssertEqual(storage.cursorSpeed, .standard)
    }

    func testWordControlsForgetAllPairPositionsWithLearningOff() throws {
        let suite = "WordControls." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        var memory = LearningMemory()
        memory.learn(word: "blorf", previous: "hello")
        memory.learn(word: "again", previous: "blorf")
        memory.learn(word: "blorfs", previous: "keep")
        for language in KeyboardLanguage.allCases { storage.save(memory: memory, touches: .init(), language: language) }
        storage.saveWords(memory)
        storage.learning = false
        storage.setProtected("Blorf", enabled: true)
        storage.setProtected("user@example.com", enabled: true)
        storage.forgetWord("BLORF")
        let reloaded = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(reloaded.protectedWords, ["blorf"])
        reloaded.learning = true
        for memory in [reloaded.multilingualMemory] + KeyboardLanguage.allCases.map({ reloaded.memory(for: $0) }) {
            XCTAssertNil(memory.words["blorf"])
            XCTAssertNil(memory.pairs["hello blorf"])
            XCTAssertNil(memory.pairs["blorf again"])
            XCTAssertEqual(memory.words["blorfs"], 1)
            XCTAssertEqual(memory.pairs["keep blorfs"], 1)
        }
        reloaded.setProtected("BLORF", enabled: false)
        XCTAssertTrue(storage.protectedWords.isEmpty)
    }

    func testLayoutOptionsPersistAndClearKeepsLayoutButRemovesWordChoices() throws {
        let suite = "LayoutOptions." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(storage.keyboardSize, .standard)
        XCTAssertEqual(storage.keyboardHand, .full)
        XCTAssertFalse(storage.numberRow)
        storage.keyboardSize = .tall
        storage.keyboardHand = .right
        storage.numberRow = true
        storage.setProtected("teh", enabled: true)
        let reloaded = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(reloaded.keyboardSize, .tall)
        XCTAssertEqual(reloaded.keyboardHand, .right)
        XCTAssertTrue(reloaded.numberRow)
        reloaded.clear()
        XCTAssertTrue(storage.protectedWords.isEmpty)
        XCTAssertEqual(storage.keyboardSize, .tall)
        XCTAssertTrue(storage.numberRow)
        defaults.set("invalid", forKey: "keyboardSize")
        defaults.set("invalid", forKey: "keyboardHand")
        XCTAssertEqual(storage.keyboardSize, .standard)
        XCTAssertEqual(storage.keyboardHand, .full)
    }

    func testNewGeometryDoesNotInheritLegacyTouchZones() throws {
        let suite = "GeometryProfiles." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        var model = TouchModel()
        model.learn(key: "a", x: 0.1, y: 0)
        storage.save(memory: .init(), touches: model, language: .english)
        let standard = TouchProfile(layout: .english, landscape: false, width: 390)
        let tall = TouchProfile(layout: .english, landscape: false, width: 390, geometry: ".tall.full")
        XCTAssertTrue(storage.touches(profile: tall).offsets.isEmpty)
        XCTAssertEqual(storage.touches(profile: standard).offsets["a"]?.count, 1)
        storage.saveTouches(model, profile: tall)
        XCTAssertEqual(storage.touches(profile: tall).offsets["a"]?.count, 1)
    }

    func testLearningLifecycleAndLanguageIsolation() throws {
        let suite = "SimpleKeyboardTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        XCTAssertTrue(storage.learning)
        storage.learning = false
        XCTAssertFalse(KeyboardStorage(defaults: defaults).learning)
        var english = LearningMemory(), german = LearningMemory()
        english.learn(word: "hedging", previous: "portfolio")
        german.learn(word: "absicherung", previous: "portfolio")
        var touches = TouchModel()
        for _ in 0..<3 { touches.learn(key: "a", x: 0.1, y: 0) }
        storage.save(memory: english, touches: touches, language: .english)
        XCTAssertNil(defaults.data(forKey: "words.en_US"))
        storage.learning = true
        storage.save(memory: english, touches: touches, language: .english)
        var germanTouches = TouchModel()
        for _ in 0..<3 { germanTouches.learn(key: "ü", x: -0.1, y: 0) }
        storage.save(memory: german, touches: germanTouches, language: .german)
        storage.language = .german
        let reloaded = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(reloaded.language, .german)
        XCTAssertEqual(reloaded.memory(for: .english).words["hedging"], 1)
        XCTAssertNil(reloaded.memory(for: .german).words["hedging"])
        XCTAssertEqual(reloaded.memory(for: .german).words["absicherung"], 1)
        XCTAssertEqual(reloaded.touches(for: .english).offsets["a"]?.count, 3)
        XCTAssertEqual(reloaded.touches(for: .english).offset(for: "a"), TouchOffset())
        XCTAssertEqual(reloaded.touches(for: .german).offset(for: "a").count, 0)
        XCTAssertEqual(reloaded.touches(for: .german).offsets["ü"]?.count, 3)
        XCTAssertEqual(reloaded.touches(for: .german).offset(for: "ü"), TouchOffset())
        reloaded.learning = false
        XCTAssertTrue(reloaded.memory(for: .english).words.isEmpty)
        XCTAssertTrue(reloaded.touches(for: .english).offsets.isEmpty)
        reloaded.learning = true
        XCTAssertEqual(reloaded.memory(for: .english).words["hedging"], 1)
        reloaded.clear()
        let cleared = KeyboardStorage(defaults: defaults)
        XCTAssertTrue(cleared.memory(for: .english).words.isEmpty)
        XCTAssertTrue(cleared.memory(for: .german).words.isEmpty)
        XCTAssertTrue(cleared.touches(for: .english).offsets.isEmpty)
        XCTAssertTrue(cleared.touches(for: .german).offsets.isEmpty)
        XCTAssertNil(defaults.data(forKey: "words.en_US"))
        XCTAssertNil(defaults.data(forKey: "words.de_DE"))
    }

    func testSharedLearningLoadsBothLegacyLanguagesAndKeepsTouchLayoutsSeparate() throws {
        let suite = "SimpleKeyboardSharedTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        var english = LearningMemory(), german = LearningMemory()
        english.learn(word: "hedging", previous: "portfolio")
        german.learn(word: "absicherung", previous: "portfolio")
        storage.save(memory: english, touches: .init(), language: .english)
        storage.save(memory: german, touches: .init(), language: .german)
        var shared = storage.multilingualMemory
        XCTAssertEqual(shared.words["hedging"], 1)
        XCTAssertEqual(shared.words["absicherung"], 1)
        shared.learn(word: "dankie", previous: "baie")
        var touches = TouchModel()
        for _ in 0..<3 { touches.learn(key: "u", x: 0.1, y: 0) }
        storage.saveMultilingual(memory: shared, touches: touches, layout: .english)
        storage.language = .german
        let reloaded = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(reloaded.multilingualMemory.words["dankie"], 1)
        XCTAssertEqual(reloaded.multilingualMemory.words["hedging"], 1)
        XCTAssertEqual(reloaded.touches(for: .english).offsets["u"]?.count, 3)
        XCTAssertEqual(reloaded.touches(for: .english).offset(for: "u"), TouchOffset())
        XCTAssertEqual(reloaded.touches(for: .german).offset(for: "u").count, 0)
        reloaded.learning = false
        XCTAssertTrue(reloaded.multilingualMemory.words.isEmpty)
        reloaded.learning = true
        XCTAssertEqual(reloaded.multilingualMemory.words["dankie"], 1)
        reloaded.clear()
        XCTAssertTrue(reloaded.multilingualMemory.words.isEmpty)
        XCTAssertNil(defaults.data(forKey: "words.multilingual"))
    }

    func testTouchProfilesSeparateOrientationWidthAndLayoutAndMigrateLegacyOnce() throws {
        let suite = "TouchProfileTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        var legacy = TouchModel()
        for _ in 0..<3 { legacy.learn(key: "a", x: 0.1, y: 0) }
        storage.save(memory: .init(), touches: legacy, language: .english)
        let portrait = TouchProfile(layout: .english, landscape: false, width: 390)
        let landscape = TouchProfile(layout: .english, landscape: true, width: 844)
        let narrow = TouchProfile(layout: .english, landscape: false, width: 320)
        let german = TouchProfile(layout: .german, landscape: false, width: 390)
        XCTAssertEqual(storage.touches(profile: portrait).offsets["a"]?.count, 3)
        for profile in [landscape, narrow, german] { XCTAssertTrue(storage.touches(profile: profile).offsets.isEmpty) }
        storage.saveTouches(legacy, profile: landscape)
        XCTAssertEqual(storage.touches(profile: landscape).offsets["a"]?.count, 3)
        storage.learning = false
        XCTAssertTrue(storage.touches(profile: portrait).offsets.isEmpty)
        storage.saveTouches(.init(), profile: portrait)
        storage.learning = true
        XCTAssertEqual(storage.touches(profile: portrait).offsets["a"]?.count, 3)
        storage.clear()
        for profile in [portrait, landscape, narrow, german] { XCTAssertTrue(storage.touches(profile: profile).offsets.isEmpty) }
    }

    func testTouchProfileRetentionIsBounded() throws {
        let suite = "TouchRetentionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        for index in 1...40 {
            storage.saveTouches(.init(), profile: TouchProfile(layout: .english, landscape: false, width: Double(index * 20)))
        }
        XCTAssertEqual(defaults.stringArray(forKey: "touches.profile.order")?.count, 32)
        XCTAssertNil(defaults.data(forKey: "touches.profile.en_US.portrait.20"))
        XCTAssertNotNil(defaults.data(forKey: "touches.profile.en_US.portrait.800"))
    }

    func testCorruptStoredDataFallsBackToEmptyMemory() throws {
        let suite = "SimpleKeyboardTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        storage.learning = true
        defaults.set(Data("invalid".utf8), forKey: "words.en_US")
        defaults.set(Data("invalid".utf8), forKey: "touches.en_US")
        defaults.set("unknown", forKey: "language")
        XCTAssertTrue(storage.memory(for: .english).words.isEmpty)
        XCTAssertTrue(storage.touches(for: .english).offsets.isEmpty)
        XCTAssertEqual(storage.language, .english)
    }
    func testPreferredLanguagePersistsWithoutChangingLayoutOrPrivateMode() throws {
        let suite = "LanguagePreference." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(storage.preferredLanguage, .automatic)
        storage.language = .german
        storage.privateTyping = true
        for preference in PreferredLanguage.allCases {
            storage.preferredLanguage = preference
            XCTAssertEqual(KeyboardStorage(defaults: defaults).preferredLanguage, preference)
            XCTAssertEqual(storage.language, .german)
            XCTAssertTrue(storage.privateTyping)
        }
        storage.preferredLanguage = .afrikaans
        storage.clear()
        XCTAssertEqual(storage.preferredLanguage, .afrikaans)
        defaults.set("invalid", forKey: "preferredLanguage")
        XCTAssertEqual(storage.preferredLanguage, .automatic)
    }

    func testAccessibilityPreferencesPersistAndHistoryClearKeepsThem() throws {
        let suite = "AccessibilityPreferences." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        XCTAssertFalse(storage.largerKeyLabels)
        XCTAssertFalse(storage.highContrast)
        storage.largerKeyLabels = true
        storage.highContrast = true
        storage.privateTyping = true
        storage.clear()
        let reloaded = KeyboardStorage(defaults: defaults)
        XCTAssertTrue(reloaded.largerKeyLabels)
        XCTAssertTrue(reloaded.highContrast)
        XCTAssertFalse(reloaded.privateTyping)
        XCTAssertEqual(reloaded.language, .english)
        for key in ["largerKeyLabels", "highContrast"] { defaults.set("invalid", forKey: key) }
        XCTAssertFalse(reloaded.largerKeyLabels)
        XCTAssertFalse(reloaded.highContrast)
    }

}
