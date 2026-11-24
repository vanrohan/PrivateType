import XCTest
#if SWIFT_PACKAGE
@testable import KeyboardCore
#else
@testable import SimpleKeyboard
#endif

final class EmojiUsageTests: XCTestCase {
    func testToneGroupingPreservesBaseVariantsAndCompoundEmoji() throws {
        for base in ["\u{1F44D}", "\u{1F469}\u{200D}\u{1F4BB}"] {
            let variants = EmojiCatalog.toneVariants(for: base)
            XCTAssertEqual(variants.count, 6)
            XCTAssertEqual(variants.first?.text, base)
            XCTAssertEqual(EmojiCatalog.grouped(variants).map(\.text), [base])
            for variant in variants { XCTAssertEqual(EmojiCatalog.toneVariants(for: variant.text), variants) }
        }
        XCTAssertTrue(EmojiCatalog.toneVariants(for: "invalid").isEmpty)
        let rainbow = "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let entries = try [rainbow, family].map { try XCTUnwrap(EmojiCatalog.entry(for: $0)) }
        XCTAssertEqual(EmojiCatalog.grouped(entries), entries)
        XCTAssertEqual(EmojiCatalog.grouped(EmojiCatalog.entries).flatMap { EmojiCatalog.toneVariants(for: $0.text) }.count,
                       EmojiCatalog.entries.count)
    }

    func testEmojiCategoriesCoverCommonBrowseTargets() throws {
        for (text, category) in [("\u{1F600}", EmojiCategory.faces), ("\u{263a}\u{FE0F}", .faces),
                                  ("\u{270c}\u{FE0F}", .people), ("\u{1F3CB}\u{FE0F}", .people), ("\u{1F44D}", .people),
                                  ("\u{1F431}", .nature), ("\u{1F355}", .food), ("\u{1F680}", .travel),
                                  ("\u{1F3BE}", .activities), ("\u{26F3}", .activities), ("\u{1F4BB}", .objects), ("\u{1F4EC}", .objects),
                                  ("\u{2764}\u{FE0F}", .faces), ("\u{1F1E9}\u{1F1EA}", .flags)] {
            XCTAssertEqual(EmojiCatalog.category(for: try XCTUnwrap(EmojiCatalog.entry(for: text))), category)
        }
    }

    func testFrequencySortsBeforeRecencyAndVariantsStayDistinct() throws {
        let first = "\u{1F600}", second = "\u{1F44D}", variant = "\u{1F44D}\u{1F3FF}"
        var usage = EmojiUsage()
        let start = Date(timeIntervalSince1970: 100)
        usage.record(first, at: start)
        usage.record(first, at: start.addingTimeInterval(1))
        usage.record(second, at: start.addingTimeInterval(2))
        usage.record(variant, at: start.addingTimeInterval(3))
        XCTAssertEqual(usage.ranked.map(\.text), [first, variant, second])
        usage.record("not an emoji")
        XCTAssertEqual(usage.ranked.count, 3)
        let decoded = try JSONDecoder().decode(EmojiUsage.self, from: JSONEncoder().encode(usage))
        XCTAssertEqual(decoded.ranked, usage.ranked)
    }

    func testUsageIsBoundedAndRepeatedInsertionKeepsTheMostUsedEmoji() {
        var usage = EmojiUsage()
        let favorite = EmojiCatalog.entries[0].text
        for _ in 0..<5 { usage.record(favorite) }
        for entry in EmojiCatalog.entries.prefix(100) { usage.record(entry.text) }
        XCTAssertEqual(usage.ranked.count, 64)
        XCTAssertEqual(usage.ranked.first?.text, favorite)
    }

    func testStoragePersistsAcrossLanguageChangesAndClearsOnlyEmojiUsage() throws {
        let suite = "EmojiUsageTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = KeyboardStorage(defaults: defaults)
        storage.recordEmoji("\u{1F600}")
        storage.language = .german
        storage.learning = true
        var memory = LearningMemory()
        memory.learn(word: "hello", previous: nil)
        storage.save(memory: memory, touches: .init(), language: .english)
        let reloaded = KeyboardStorage(defaults: defaults)
        XCTAssertEqual(reloaded.emojiUsage.ranked.first?.text, "\u{1F600}")
        reloaded.clearEmojiUsage()
        XCTAssertTrue(KeyboardStorage(defaults: defaults).emojiUsage.ranked.isEmpty)
        XCTAssertEqual(reloaded.memory(for: .english).words["hello"], 1)
        defaults.set(Data("broken".utf8), forKey: "emoji.usage")
        XCTAssertTrue(reloaded.emojiUsage.ranked.isEmpty)
    }

    func testDecodedExtremeCountsCannotOverflowOnInsertion() throws {
        let text = "{\"uses\":{\"\u{1F600}\":{\"count\":" + String(Int.max) + ",\"lastUsed\":100}}}"
        var usage = try JSONDecoder().decode(EmojiUsage.self, from: Data(text.utf8))
        usage.record("\u{1F600}")
        XCTAssertEqual(usage.ranked.map(\.text), ["\u{1F600}"])
    }

    func testCommonEnglishAndGermanSearchWordsFindExpectedEmoji() {
        for query in ["birthday", "GEBURTSTAG", "torte"] {
            XCTAssertTrue(EmojiCatalog.search(query).contains { $0.text == "\u{1F382}" }, query)
        }
        XCTAssertTrue(EmojiCatalog.search("Deutschland").contains { $0.text == "\u{1F1E9}\u{1F1EA}" })
        XCTAssertTrue(EmojiCatalog.search("daumen-hoch").contains { $0.text == "\u{1F44D}" })
        XCTAssertTrue(EmojiCatalog.search("thumbs_up").contains { $0.text == "\u{1F44D}" })
        XCTAssertTrue(EmojiCatalog.search("kaffee").contains { $0.text == "\u{2615}" })
        let cats = EmojiCatalog.search("cat")
        XCTAssertTrue(cats.contains { $0.text == "\u{1F431}" })
        XCTAssertFalse(cats.contains { $0.name.contains("multiplication") })
        XCTAssertTrue(EmojiCatalog.search("birth").contains { $0.text == "\u{1F382}" })
    }
    func testAfrikaansAliasesCountriesAndAccents() {
        for (query, text) in [("hond", "\u{1F436}"), ("kat", "\u{1F431}"), ("dankie", "\u{1F64F}"),
                              ("hart", "\u{2764}\u{FE0F}"), ("koffie", "\u{2615}"),
                              ("Duitsland", "\u{1F1E9}\u{1F1EA}"), ("Suid Afrika", "\u{1F1FF}\u{1F1E6}")] {
            XCTAssertTrue(EmojiCatalog.search(query).contains { $0.text == text }, query)
        }
        XCTAssertEqual(EmojiCatalog.search("re\u{00eb}n"), EmojiCatalog.search("reen"))
    }

    func testEmojiSearchTyposKeepEveryTermAndDoNotExpandShortTerms() {
        XCTAssertTrue(EmojiCatalog.search("koffei").contains { $0.text == "\u{2615}" })
        let doctors = EmojiCatalog.search("woman doctro")
        XCTAssertFalse(doctors.isEmpty)
        XCTAssertTrue(doctors.allSatisfy { $0.name.hasPrefix("woman health worker") })
        XCTAssertTrue(EmojiCatalog.search("woman qzxqzx").isEmpty)
        XCTAssertTrue(EmojiCatalog.search("kta").isEmpty)
        XCTAssertTrue(EmojiCatalog.search("qqqqqqqq").isEmpty)
        XCTAssertEqual(EmojiCatalog.search("cat"), EmojiCatalog.search("cat"))
        XCTAssertTrue(EmojiCatalog.search(String(repeating: "a", count: 65)).isEmpty)
        XCTAssertTrue(EmojiCatalog.search(Array(repeating: "a", count: 9).joined(separator: " ")).isEmpty)
        XCTAssertTrue(EmojiCatalog.search(String(repeating: "a", count: 33)).isEmpty)
    }

    func testCompoundEmojiAreUniqueAndUsageKeepsVariantsSeparate() throws {
        let base = "\u{1F469}\u{200D}\u{2695}\u{FE0F}"
        let toned = "\u{1F469}\u{1F3FF}\u{200D}\u{2695}\u{FE0F}"
        XCTAssertNotNil(EmojiCatalog.entry(for: base))
        XCTAssertNotNil(EmojiCatalog.entry(for: toned))
        XCTAssertEqual(EmojiCatalog.search(toned).map(\.text), [toned])
        XCTAssertEqual(Set(EmojiCatalog.entries.map(\.text)).count, EmojiCatalog.entries.count)
        XCTAssertEqual(EmojiCatalog.search("woman doctor").count, 6)
        XCTAssertNotNil(EmojiCatalog.entry(for: "\u{1F468}\u{200D}\u{1F468}\u{200D}\u{1F467}"))
        var usage = EmojiUsage()
        usage.record(base)
        usage.record(toned)
        XCTAssertEqual(Set(usage.ranked.map(\.text)), [base, toned])
        XCTAssertEqual(try JSONDecoder().decode(EmojiUsage.self, from: JSONEncoder().encode(usage)).ranked, usage.ranked)
    }

    func testExactEmojiTokensPrecedePrefixesAndSuppressFuzzyResults() throws {
        let bears = EmojiCatalog.search("bear")
        let teddy = try XCTUnwrap(bears.firstIndex { $0.name == "teddy bear" })
        let beard = try XCTUnwrap(bears.firstIndex { $0.name == "bearded person" })
        XCTAssertLessThan(teddy, beard)
        XCTAssertTrue(EmojiCatalog.search("deer").contains { $0.text == "\u{1F98C}" })
        XCTAssertFalse(EmojiCatalog.search("deer").contains { $0.name.contains("beer") })
        XCTAssertTrue(EmojiCatalog.search("family man woman girl boy").contains {
            $0.text == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        })
    }

}
