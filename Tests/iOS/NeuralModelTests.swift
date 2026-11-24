import XCTest
import Darwin
@testable import SimpleKeyboard

final class NeuralModelTests: XCTestCase {
    func testModelsAreBundledInTheAppAndKeyboard() throws {
        let app = Bundle.main
        let plugins = try XCTUnwrap(app.builtInPlugInsURL)
        let keyboard = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("SimpleKeyboardExtension.appex")))
        let expectsEnglishModel = app.url(forResource: "English", withExtension: "pte") != nil
        for bundle in [app, keyboard, Bundle(for: Self.self)] {
            XCTAssertEqual(bundle.url(forResource: "English", withExtension: "pte") != nil, expectsEnglishModel)
            XCTAssertEqual(bundle.url(forResource: "EnglishVocabulary", withExtension: "txt") != nil, expectsEnglishModel)
        }
        for bundle in [app, keyboard] {
            XCTAssertNil(bundle.url(forResource: "German", withExtension: "mlmodelc"))
            XCTAssertNil(bundle.url(forResource: "GermanTokenizer", withExtension: "json"))
            XCTAssertNil(bundle.url(forResource: "GermanModelCard", withExtension: "md"))
            XCTAssertNil(bundle.url(forResource: "GermanConversionChecks", withExtension: "json"))
            XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "PrivateType")
            XCTAssertNotNil(bundle.url(forResource: "Settings", withExtension: "bundle"))
        }
        let settings = try XCTUnwrap(keyboard.url(forResource: "Settings", withExtension: "bundle"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: settings.appendingPathComponent("Root.plist")), format: nil) as? [String: Any])
        let specifiers = try XCTUnwrap(plist["PreferenceSpecifiers"] as? [[String: Any]])
        XCTAssertEqual(specifiers.first { $0["Key"] as? String == "neuralPrediction" }?["DefaultValue"] as? Bool, true)
        XCTAssertEqual(specifiers.first { $0["Key"] as? String == "autocorrection" }?["DefaultValue"] as? Bool, true)
        XCTAssertEqual(specifiers.first { $0["Key"] as? String == "learning" }?["DefaultValue"] as? Bool, true)
    }

    func testEnglishModelLoadsAndUsesSentenceContextAndPrefix() throws {
        try XCTSkipUnless(Bundle(for: Self.self).url(forResource: "English", withExtension: "pte") != nil,
                          "Optional English model is absent.")
        let model = try EnglishNeuralModel(bundle: Bundle(for: Self.self))
        XCTAssertEqual(try model.words(context: "Can you please", prefix: "").first, "provide")
        XCTAssertTrue(try model.words(context: "I am on my", prefix: "").prefix(3).contains("way"))
        XCTAssertTrue(try model.words(context: "Can you please", prefix: "giv").contains("give"))
        XCTAssertFalse(try model.words(context: "flurblezorp", prefix: "").isEmpty)
        XCTAssertTrue(try model.words(context: "Can you please", prefix: "zzzzzzzz").isEmpty)
    }

    func testGermanModelLoadsAndKeepsNounCase() throws {
        try XCTSkipUnless(Bundle(for: Self.self).url(forResource: "German", withExtension: "mlmodelc") != nil,
                          "Optional German model is absent.")
        let model = try GermanNeuralModel(bundle: Bundle(for: Self.self))
        XCTAssertEqual(try model.words(context: "Vielen Dank für deine", prefix: "").first, "Hilfe")
        XCTAssertTrue(try model.words(context: "Ich bin auf dem Weg nach", prefix: "Hau").contains("Hause"))
        XCTAssertFalse(try model.words(context: String(repeating: "Ich bin hier. ", count: 30), prefix: "").isEmpty)
        let compounds = try model.words(context: "Ich suche einen", prefix: "Arbeits", candidates: ["Arbeitsplatz", "Arbeitsvertrag", "Arbeitszeit"])
        XCTAssertTrue(compounds.contains("Arbeitsplatz"))
        XCTAssertEqual(compounds.filter { ["Arbeitsplatz", "Arbeitsvertrag", "Arbeitszeit"].contains($0) },
                       ["Arbeitsplatz", "Arbeitsvertrag", "Arbeitszeit"])
        XCTAssertTrue(compounds.allSatisfy { $0.lowercased().hasPrefix("arbeits") })
        XCTAssertTrue(try model.words(context: "Vielen Dank f\u{00fc}r deine", prefix: "Hilfr", candidates: ["Hilfe"]).contains("Hilfe"))
    }

    func testEnglishModelRanksCorrectionsWithSentenceContext() throws {
        try XCTSkipUnless(Bundle(for: Self.self).url(forResource: "English", withExtension: "pte") != nil,
                          "Optional English model is absent.")
        let model = try EnglishNeuralModel(bundle: Bundle(for: Self.self))
        let candidates = ["cat", "eat", "hat"]
        let food = try model.words(context: "what would you like to", prefix: "qat", candidates: candidates)
        let pet = try model.words(context: "the mouse ran away from the", prefix: "qat", candidates: candidates)
        XCTAssertTrue(Set(candidates).isSubset(of: Set(food)))
        XCTAssertTrue(Set(candidates).isSubset(of: Set(pet)))
        XCTAssertTrue((food + pet).allSatisfy { $0.lowercased().hasPrefix("qat") || candidates.contains($0) })
        XCTAssertLessThan(try XCTUnwrap(food.firstIndex(of: "eat")), try XCTUnwrap(food.firstIndex(of: "cat")))
        XCTAssertLessThan(try XCTUnwrap(pet.firstIndex(of: "cat")), try XCTUnwrap(pet.firstIndex(of: "eat")))
        XCTAssertTrue(try model.words(context: "only seeing AI generated", prefix: "atuff", candidates: ["stuff"]).contains("stuff"))
        let contractions = try model.words(context: "", prefix: "Its", candidates: ["it's", "itself", "itse"])
        let visible = PredictionEngine(multilingual: true).suggestions(context: "Its", completions: ["itself", "itse"],
            corrections: ["it's"], neural: contractions, writingLanguage: .english,
            languageScores: ["it's": 500, "itself": 500, "itse": 0])
        XCTAssertEqual(visible[1], "It's")
    }

    func testAModelLatencyAndMemoryWithFixedPublicPrompts() throws {
        func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info.phys_footprint : 0
        }
        let bundle = Bundle(for: Self.self)
        let languages = KeyboardLanguage.allCases.filter { language in
            language == .english ? bundle.url(forResource: "English", withExtension: "pte") != nil :
                bundle.url(forResource: "German", withExtension: "mlmodelc") != nil
        }
        try XCTSkipUnless(!languages.isEmpty, "Optional models are absent.")
        for language in languages {
            try autoreleasepool {
                let before = footprint()
                let model: NeuralWordModel = language == .english ? try EnglishNeuralModel(bundle: bundle) : try GermanNeuralModel(bundle: bundle)
                let prompts = language == .english ? ["Can you please", "I am on my", "Thank you for your", "I look forward to"] :
                    ["Vielen Dank für deine", "Ich freue mich auf", "Kannst du mir bitte", "Ich bin auf dem Weg nach"]
                var times: [Double] = []
                for prompt in prompts {
                    let start = CFAbsoluteTimeGetCurrent()
                    XCTAssertFalse(try model.words(context: prompt, prefix: "").isEmpty)
                    times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                }
                print("MODEL_METRICS \(language.rawValue) resident_before=\(before) resident_after=\(footprint()) latency_ms=\(times)")
            }
        }
    }
}

private final class TestWordModel: NeuralWordModel {
    let name: String
    let action: () throws -> [String]
    init(name: String, action: @escaping () throws -> [String]) { self.name = name; self.action = action }
    func words(context: String, prefix: String, candidates: [String]) throws -> [String] { try action() }
}

@MainActor
final class NeuralServiceTests: XCTestCase {
    func testInFlightOldLanguageCannotReplaceNewLanguageSuggestions() async {
        let started = expectation(description: "English request starts")
        let latest = expectation(description: "German request returns")
        let stale = expectation(description: "Old request stays hidden")
        stale.isInverted = true
        let gate = DispatchSemaphore(value: 0)
        let service = NeuralPredictionService { language, _ in
            TestWordModel(name: language.badge) {
                if language == .english {
                    started.fulfill()
                    _ = gate.wait(timeout: .now() + 2)
                }
                return language == .english ? ["provide"] : ["Hilfe"]
            }
        }
        service.request(context: "Can you please ", language: .english) { _ in stale.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        service.request(context: "Vielen Dank für deine ", language: .german) { result in
            XCTAssertEqual(result.words, ["Hilfe"])
            XCTAssertEqual(result.engine, "DE")
            latest.fulfill()
        }
        gate.signal()
        await fulfillment(of: [latest, stale], timeout: 0.4)
        service.clear()
    }

    func testMissingModelReturnsAnExplicitFallback() async {
        let result = expectation(description: "Fallback returns")
        let service = NeuralPredictionService { _, _ in throw NeuralPredictionError.missingResource }
        service.request(context: "hello ", language: .english) { value in
            XCTAssertTrue(value.words.isEmpty)
            XCTAssertEqual(value.engine, "Basic predictions")
            result.fulfill()
        }
        await fulfillment(of: [result], timeout: 1)
        service.clear()
    }

    func testClearDiscardsAnActiveRequest() async {
        let started = expectation(description: "Request starts")
        let stale = expectation(description: "Cleared request stays hidden")
        stale.isInverted = true
        let gate = DispatchSemaphore(value: 0)
        let service = NeuralPredictionService { _, _ in
            TestWordModel(name: "test") {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 2)
                return ["hello"]
            }
        }
        service.request(context: "a ", language: .english) { _ in stale.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        service.clear()
        gate.signal()
        await fulfillment(of: [stale], timeout: 0.2)
    }
}
