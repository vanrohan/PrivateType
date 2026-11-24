import XCTest
#if SWIFT_PACKAGE
@testable import KeyboardCore
#else
@testable import SimpleKeyboard
#endif

final class TypingBenchmarkTests: XCTestCase {
    private var conditions: [String: String] {
        Dictionary(uniqueKeysWithValues: BenchmarkCondition.allCases.map { ($0.rawValue, "Not recorded") })
    }
    private var environment: BenchmarkEnvironment {
        BenchmarkEnvironment(device: "iPhone", os: "26.2", version: "1.0", build: "7", orientation: "portrait", automated: true)
    }
    private func session(_ task: BenchmarkTask = .english) -> BenchmarkSession {
        BenchmarkSession(task: task, conditions: conditions, environment: environment, now: 100)
    }
    private func result(_ text: String = "sample") throws -> BenchmarkResult {
        var trial = session()
        trial.change("s", now: 101)
        trial.change(text, now: 106)
        return try trial.finish()
    }
    private func store() -> (BenchmarkStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "benchmark-tests-" + UUID().uuidString)!
        return (BenchmarkStore(defaults: defaults), defaults)
    }

    func testCopyUsesFirstAndLastChangesAndClearsText() throws {
        var trial = session()
        trial.change("P", now: 110)
        trial.change("Please sen", now: 113)
        trial.change("Please send", now: 115)
        trial.change("Please send", now: 180)
        let result = try trial.finish()
        XCTAssertEqual(result.seconds, 5)
        XCTAssertEqual(result.wordsPerMinute, 26.4)
        XCTAssertEqual(trial.text, "")
        XCTAssertThrowsError(try trial.finish())
    }

    func testRepairIncludesOpeningAndFinalCommitCounts() throws {
        var trial = session(.repair)
        XCTAssertEqual(trial.text, "Please send teh details.")
        trial.change("Please send th details.", now: 110)
        trial.change(BenchmarkTask.repair.prompt, now: 112)
        let result = try trial.finish()
        XCTAssertEqual(result.seconds, 12)
        XCTAssertEqual(result.errors, 0)
        XCTAssertNil(result.wordsPerMinute)
        XCTAssertEqual(result.timingMethod, "start_to_last_change")
    }

    func testSingleChangeUntimedAndEmptyOrUnchangedRepairRejected() throws {
        var trial = session()
        XCTAssertThrowsError(try trial.finish())
        trial = session()
        trial.change("Paste", now: 101)
        XCTAssertNil(try trial.finish().seconds)
        trial = session(.repair)
        XCTAssertThrowsError(try trial.finish())
    }

    func testDeleteAndReplaceUseFinalTextForErrors() throws {
        var trial = session()
        trial.change("wrong", now: 101)
        trial.change("", now: 102)
        trial.change(BenchmarkTask.english.prompt, now: 105)
        let result = try trial.finish()
        XCTAssertEqual(result.seconds, 4)
        XCTAssertEqual(result.errors, 0)
    }

    func testDistancePreservesAccentsCaseSpaceAndUsesOrdinaryEdits() {
        for (a, b, expected) in [("abc", "abc", 0), ("abc", "axc", 1), ("abc", "ab", 1),
            ("ab", "abc", 1), ("teh", "the", 2), ("e\u{301}", "\u{e9}", 0),
            ("e", "\u{e9}", 1), ("A ", "a", 2), ("", "abc", 3)] {
            XCTAssertEqual(BenchmarkSession.distance(a, b), expected)
        }
    }

    func testInvalidClockLongInputInterruptionAndRestart() throws {
        for instant in [Double.nan, .infinity, 99] {
            var trial = session()
            trial.change("secret", now: instant)
            XCTAssertThrowsError(try trial.finish())
            XCTAssertEqual(trial.text, "")
        }
        var trial = session()
        trial.change("s", now: 105)
        trial.change("secret", now: 104)
        XCTAssertThrowsError(try trial.finish())
        trial = session()
        trial.change(String(repeating: "x", count: 513), now: 101)
        XCTAssertThrowsError(try trial.finish())
        trial = session()
        trial.change("secret", now: 101)
        trial.invalidate()
        XCTAssertEqual(trial.text, "")
        XCTAssertThrowsError(try trial.finish())
        trial = session(.german)
        trial.change(BenchmarkTask.german.prompt, now: 101)
        XCTAssertEqual(try trial.finish().task, .german)
        var badStart = BenchmarkSession(task: .english, conditions: conditions, environment: environment, now: -.infinity)
        XCTAssertThrowsError(try badStart.finish())
    }

    func testFrozenConditionsAndAllTaskMetrics() throws {
        var chosen = conditions
        chosen["keyboard"] = "PrivateType"
        var trial = BenchmarkSession(task: .mixed, conditions: chosen, environment: environment, now: 100)
        chosen["keyboard"] = "Apple"
        trial.change(BenchmarkTask.mixed.prompt, now: 101)
        XCTAssertEqual(try trial.finish().conditions["keyboard"], "PrivateType")
        for task in BenchmarkTask.allCases {
            trial = session(task)
            trial.change("x", now: 101)
            trial.change(task.prompt, now: 102)
            XCTAssertEqual(try trial.finish().errors, 0)
        }
    }

    func testSaveReloadDuplicateDeleteAndNoTypedText() throws {
        let (store, defaults) = store()
        let item = try result("PRIVATE_SECRET_MARKER")
        try store.save(item)
        XCTAssertThrowsError(try store.save(item))
        XCTAssertEqual(BenchmarkStore(defaults: defaults).results, [item])
        XCTAssertFalse(String(data: defaults.data(forKey: BenchmarkStore.key)!, encoding: .utf8)!.contains("PRIVATE_SECRET_MARKER"))
        XCTAssertFalse(store.csv.contains("PRIVATE_SECRET_MARKER"))
        try store.delete([item.id])
        XCTAssertTrue(BenchmarkStore(defaults: defaults).results.isEmpty)
    }

    func testRebrandLoadsOldAndNewKeyboardResultsWithoutChangingLabels() throws {
        let (_, defaults) = store()
        var selected = conditions
        selected["keyboard"] = "PrivateType"
        var trial = BenchmarkSession(task: .english, conditions: selected, environment: environment, now: 100)
        trial.change("sample", now: 101)
        let current = try trial.finish()
        let currentJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        var records = [currentJSON]
        for version in [1, 2] {
            var legacy = currentJSON
            legacy["id"] = UUID().uuidString
            legacy["protocolVersion"] = version
            if version == 1 { legacy.removeValue(forKey: "sampleID") }
            var legacyConditions = selected
            legacyConditions["keyboard"] = "SimpleKeys"
            legacy["conditions"] = legacyConditions
            records.append(legacy)
        }
        defaults.set(try JSONSerialization.data(withJSONObject: records), forKey: BenchmarkStore.key)
        let loaded = BenchmarkStore(defaults: defaults)
        XCTAssertFalse(loaded.loadFailed)
        XCTAssertEqual(loaded.results.map { $0.conditions["keyboard"] }, ["PrivateType", "SimpleKeys", "SimpleKeys"])
        XCTAssertTrue(loaded.csv.contains("\"PrivateType\""))
        XCTAssertTrue(loaded.csv.contains("\"SimpleKeys\""))
        XCTAssertTrue(BenchmarkCondition.keyboard.options.contains("PrivateType"))
        XCTAssertFalse(BenchmarkCondition.keyboard.options.contains("SimpleKeys"))
        try loaded.save(result())
        XCTAssertEqual(BenchmarkStore(defaults: defaults).results.count, 4)
    }

    func testCapacityDoesNotEvictAndDeleteAllowsSave() throws {
        let (store, _) = store()
        for _ in 0..<50 { try store.save(result()) }
        let first = store.results[0]
        XCTAssertThrowsError(try store.save(result()))
        XCTAssertEqual(store.results.count, 50)
        XCTAssertEqual(store.results[0], first)
        try store.delete([first.id])
        try store.save(result())
        try store.deleteAll()
    }

    func testCorruptInvalidAndDuplicateDataAreRejected() throws {
        let (_, defaults) = store()
        for data in [Data("bad".utf8), Data(repeating: 0, count: 131_073)] {
            defaults.set(data, forKey: BenchmarkStore.key)
            XCTAssertTrue(BenchmarkStore(defaults: defaults).loadFailed)
        }
        let item = try result()
        defaults.set(try JSONEncoder().encode([item, item]), forKey: BenchmarkStore.key)
        XCTAssertTrue(BenchmarkStore(defaults: defaults).loadFailed)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        for (key, value) in [("characters", -1 as Any), ("seconds", -2 as Any), ("protocolVersion", 99 as Any)] {
            var invalid = json
            invalid[key] = value
            defaults.set(try JSONSerialization.data(withJSONObject: [invalid]), forKey: BenchmarkStore.key)
            XCTAssertTrue(BenchmarkStore(defaults: defaults).loadFailed)
        }
        var tiny = json
        tiny["seconds"] = Double.leastNonzeroMagnitude
        defaults.set(try JSONSerialization.data(withJSONObject: [tiny]), forKey: BenchmarkStore.key)
        XCTAssertTrue(BenchmarkStore(defaults: defaults).loadFailed)
        json["conditions"] = ["keyboard": "Untrusted value"]
        defaults.set(try JSONSerialization.data(withJSONObject: [json]), forKey: BenchmarkStore.key)
        XCTAssertTrue(BenchmarkStore(defaults: defaults).loadFailed)
    }

    func testCSVIncludesProtocolConditionsAndEscapesMetadata() throws {
        let (store, _) = store()
        var env = environment
        env.build = "=1,\"2\""
        var trial = BenchmarkSession(task: .english, conditions: conditions, environment: env, now: 100)
        trial.change("x", now: 101)
        try store.save(trial.finish())
        XCTAssertTrue(store.csv.contains("\"'=1,\"\"2\"\"\""))
        XCTAssertTrue(store.csv.contains("\"first_to_last_change\""))
        XCTAssertTrue(store.csv.contains("\"automated\""))
        XCTAssertTrue(store.csv.contains("\"Not recorded\""))
    }
    func testEverySampleHasAStableIDAndScoresItsOwnText() throws {
        var identifiers = Set<String>()
        for task in BenchmarkTask.allCases {
            XCTAssertGreaterThanOrEqual(task.samples.count, 2)
            XCTAssertEqual(task.samples[0].id, task.rawValue)
            for sample in task.samples {
                XCTAssertTrue(identifiers.insert(sample.id).inserted)
                XCTAssertLessThanOrEqual(sample.text.count, 512)
                if task == .emoji {
                    for character in sample.text where character.unicodeScalars.contains(where: { !$0.isASCII }) {
                        XCTAssertNotNil(EmojiCatalog.entry(for: String(character)))
                    }
                }
                var trial = BenchmarkSession(task: task, sampleID: sample.id, conditions: conditions,
                    environment: environment, now: 100)
                XCTAssertEqual(trial.text, sample.initialText)
                trial.change("x", now: 101)
                trial.change(sample.text, now: 105)
                let result = try trial.finish()
                XCTAssertEqual(result.errors, 0)
                XCTAssertEqual(result.sampleID, sample.id)
                XCTAssertEqual(result.sample, sample)
                XCTAssertEqual(result.protocolVersion, 2)
                XCTAssertEqual(result.seconds, task == .repair ? 5 : 4)
                XCTAssertEqual(result.wordsPerMinute == nil, task == .repair)
            }
        }
        var trial = BenchmarkSession(task: .english, sampleID: "unknown", conditions: conditions,
            environment: environment, now: 100)
        trial.change("x", now: 101)
        XCTAssertThrowsError(try trial.finish())
    }

    func testLegacyResultsLoadBesideVariantsAndExportSampleIDs() throws {
        let (_, defaults) = store()
        let original = try result()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "sampleID")
        legacy["protocolVersion"] = 1
        defaults.set(try JSONSerialization.data(withJSONObject: [legacy]), forKey: BenchmarkStore.key)
        let loaded = BenchmarkStore(defaults: defaults)
        XCTAssertFalse(loaded.loadFailed)
        XCTAssertEqual(loaded.results.first?.sample?.id, BenchmarkTask.english.rawValue)
        let sample = BenchmarkTask.emoji.samples[1]
        var trial = BenchmarkSession(task: .emoji, sampleID: sample.id, conditions: conditions,
            environment: environment, now: 100)
        trial.change("x", now: 101)
        trial.change(sample.text, now: 103)
        let item = try trial.finish()
        try loaded.save(item)
        XCTAssertEqual(BenchmarkStore(defaults: defaults).results.count, 2)
        XCTAssertTrue(loaded.csv.contains("\"sample\""))
        XCTAssertTrue(loaded.csv.contains("\"" + sample.id + "\""))
        XCTAssertFalse(loaded.csv.contains(sample.text))
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        invalid["sampleID"] = BenchmarkTask.symbols.samples[0].id
        defaults.set(try JSONSerialization.data(withJSONObject: [invalid]), forKey: BenchmarkStore.key)
        XCTAssertTrue(BenchmarkStore(defaults: defaults).loadFailed)
    }

    func testOriginalSamplesStayImmutableForStoredResults() {
        let originals: [(BenchmarkTask, String, String)] = [
            (.english, "copy.en.v1", "Please send the meeting details tomorrow morning."),
            (.afrikaans, "copy.af.v1", "Baie dankie vir jou hulp. Ek sien jou by die huis."),
            (.german, "copy.de.v1", "Vielen Dank. Wir treffen uns morgen am Bahnhof."),
            (.mixed, "copy.mixed.v1", "Hello, baie dankie. Vielen Dank for your help."),
            (.repair, "repair.v1", "Please send the details.")]
        for (task, id, text) in originals {
            XCTAssertEqual(task.samples[0].id, id)
            XCTAssertEqual(task.samples[0].text, text)
        }
        XCTAssertEqual(BenchmarkTask.repair.samples[0].initialText, "Please send teh details.")
    }

}
