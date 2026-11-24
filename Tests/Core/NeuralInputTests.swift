import XCTest
#if SWIFT_PACKAGE
@testable import KeyboardCore
#else
@testable import SimpleKeyboard
#endif

final class NeuralInputTests: XCTestCase {
    func testHashMatchesThePublishedFutoReference() {
        XCTAssertEqual(FutoHash.hash([]), 1471106076447886454)
        XCTAssertEqual(FutoHash.hash(Array("hello".utf8)), 66478811968527032)
        XCTAssertEqual(FutoHash.hash(Array("abcdefghijklmnopq".utf8)), 11444799058722442184)
        XCTAssertEqual(FutoHash.hash(Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWX".utf8)), 1187001438105522303)
        XCTAssertEqual(FutoHash.buckets("hello"), [22259, 20925])
        XCTAssertEqual(FutoHash.buckets("don't"), [31366, 22265])
        XCTAssertEqual(FutoHash.buckets("xylophone"), [1546, 30130])
    }

    func testGermanTokenizerMatchesTheOriginalPythonTokenizer() throws {
        #if SWIFT_PACKAGE
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Models/GermanTokenizer.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Optional German tokenizer is absent.")
        #else
        guard let url = Bundle(for: Self.self).url(forResource: "GermanTokenizer", withExtension: "json") else {
            throw XCTSkip("Optional German tokenizer is absent.")
        }
        #endif
        let tokenizer = try BytePairTokenizer(data: Data(contentsOf: url))
        let cases: [(String, [Int])] = [
            ("Hallo Welt", [1007, 978]),
            ("Ich bin auf dem Weg nach Hause.", [308, 512, 392, 486, 1364, 557, 1205, 18]),
            ("Vielen Dank für deine Hilfe!", [2539, 1710, 442, 826, 2135, 5]),
            ("Grüße, Straße, Öl und Äpfel", [5957, 1207, 16, 2588, 16, 6164, 328, 1502, 3395]),
            ("don't we're", [72, 300, 11, 88, 3816, 11, 370]),
            ("  Hallo\nWelt ", [225, 5179, 203, 59, 672, 225]),
            ("\u{1f44b}\u{1f3fd}", [177, 258, 244, 238, 177, 258, 242, 126]),
            ("cafe\u{0301}", [4448, 796, 141, 228])
        ]
        for (text, expected) in cases { XCTAssertEqual(tokenizer.encode(text), expected, text) }
        XCTAssertEqual(tokenizer.encode(""), [])
    }

    func testInvalidTokenizerFailsInsteadOfUsingTheWrongVocabulary() {
        XCTAssertThrowsError(try BytePairTokenizer(data: Data("{}".utf8)))
    }

    func testNeuralCandidatesKeepTypedWordsAndGermanCase() {
        let english = PredictionEngine()
        XCTAssertEqual(english.suggestions(context: "Can you please ", neural: ["provide", "add", "create"]).first, "provide")
        let partial = english.suggestions(context: "Can you please pro", neural: ["provide", "process", "apple", "123"])
        XCTAssertEqual(partial.first, "pro")
        XCTAssertTrue(partial.contains("provide"))
        XCTAssertFalse(partial.contains("apple"))
        XCTAssertTrue(PredictionEngine(language: .german).suggestions(context: "Vielen Dank für deine ", neural: ["Hilfe"]).contains("Hilfe"))
        XCTAssertEqual(english.suggestions(context: "user@example.com", neural: ["hello"]), [])
    }
}
