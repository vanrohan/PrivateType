import XCTest
import CryptoKit
@testable import SimpleKeyboard

@MainActor
final class MultilingualSpellingTests: XCTestCase {
    func testManualRepairsCoverMixedLanguagesAndMultipleEdits() {
        let spelling = MultilingualSpelling()
        let predictor = PredictionEngine(multilingual: true)
        let samples: [(String, String, TypingLanguage)] = [
            ("Ek ken die chuck vleis. Dis cheaoer", "cheaper", .afrikaans),
            ("Klnk", "Klink", .english), ("Blckchan", "Blockchain", .english),
            ("send the messge", "message", .english),
            ("we discuss cryptocurrncy", "cryptocurrency", .english),
            ("please check the documntaton", "documentation", .english),
            ("baie dankei", "dankie", .afrikaans)
        ]
        for (context, expected, language) in samples {
            let token = TextRules.token(before: context)
            let corrections = spelling.manualCorrections(token, language: language)
            let completions = spelling.completions(token, language: language)
            for neural in [[], [expected], token == "Klnk" ? ["kink"] : []] {
                let words = predictor.suggestions(context: context, completions: completions,
                    corrections: corrections, neural: neural, writingLanguage: language,
                    languageScores: spelling.rankingScores(completions + corrections, language: language))
                XCTAssertEqual(words.first, token)
                XCTAssertTrue(words.prefix(2).contains(expected), "\(context): \(words); candidates: \(corrections)")
            }
        }
        XCTAssertFalse(TextRules.safeCorrection(word: "Blckchan", candidate: "Blockchain"))
        for word in ["hello", "API", "blockchain", "qzxqzxqz", String(repeating: "a", count: 1000)] {
            XCTAssertTrue(spelling.manualCorrections(word, language: .english).isEmpty, word)
        }
    }

    func testJoinedWordRepairsReachTheNarrowRow() {
        let spelling = MultilingualSpelling()
        let predictor = PredictionEngine(multilingual: true)
        let samples: [(String, String, TypingLanguage)] = [
            ("Birtgcertificate", "Birth certificate", .english),
            ("birthcertificate", "birth certificate", .english),
            ("birthcertifcate", "birth certificate", .english),
            ("birtthcertificate", "birth certificate", .english),
            ("brithcertificate", "birth certificate", .english),
            ("BIRTHCERTIFICATE", "BIRTH CERTIFICATE", .english),
            ("please send Birtgcertificate", "Birth certificate", .german),
            ("meetingroom", "meeting room", .english),
            ("Useiphone", "Use iPhone", .english),
            ("alot", "a lot", .english),
            ("Ineed", "I need", .english),
            ("nextmonday", "next Monday", .english),
            ("thankyou", "thank you", .english),
            ("mercibeaucoup", "merci beaucoup", .french)
        ]
        for (context, expected, language) in samples {
            let token = TextRules.prefix(before: context)
            let repairs = Array(spelling.manualCorrections(token, language: language).prefix(24))
            let completions = Array(spelling.completions(token, language: language).prefix(24))
            XCTAssertTrue(repairs.contains { $0.lowercased() == expected.lowercased() }, "\(token): \(repairs)")
            for neural in [[], ["unrelated"] + completions] {
                let words = predictor.suggestions(context: context, completions: completions, corrections: repairs,
                    neural: neural, writingLanguage: language,
                    languageScores: spelling.rankingScores(completions + repairs, language: language), limit: 2)
                XCTAssertEqual(words.first, token)
                XCTAssertEqual(words.dropFirst().first, expected, "\(context): \(words); repairs: \(repairs)")
            }
            XCTAssertNil(spelling.automaticCorrection(token, candidates: repairs.filter { $0.contains(" ") }))
            XCTAssertEqual(Array(spelling.manualCorrections(token, language: language).prefix(24)), repairs)
        }
        XCTAssertTrue(spelling.manualCorrections("formhome", language: .english).contains("from home"))
        for (word, language) in [("keyboard", TypingLanguage.english), ("birthday", .english),
                                  ("Geburtsurkunde", .german), ("qzxqzxqz", .english),
                                  (String(repeating: "q", count: 1000), .english)] {
            XCTAssertFalse(spelling.manualCorrections(word, language: language).contains { $0.contains(" ") }, word)
        }
    }

    func testVocabularyRepairsReachTheVisibleRow() {
        let spelling = MultilingualSpelling()
        let predictor = PredictionEngine(multilingual: true)
        let samples: [(String, String, TypingLanguage)] = [
            ("Does the moms", "mom's", .english),
            ("Moms", "Mom's", .english),
            ("my dads", "dad's", .english),
            ("the parents", "parent's", .english),
            ("Ipgone", "iPhone", .english),
            ("ipgone", "iPhone", .german),
            ("IPGONE", "IPHONE", .english),
            ("use iphne", "iPhone", .english),
            ("use iphoen", "iPhone", .english),
            ("open eBsy", "eBay", .english),
            ("Ebsy", "eBay", .english),
            ("open iTunea", "iTunes", .english)
        ]
        for (context, expected, language) in samples {
            let token = TextRules.token(before: context)
            let corrections = Array(spelling.manualCorrections(token, language: language).prefix(24))
            let completions = Array(spelling.completions(token, language: language).prefix(24))
            XCTAssertTrue(corrections.contains { $0.lowercased() == expected.lowercased() }, "\(token): \(corrections)")
            for neural in [[], [expected] + completions, completions, ["momsen"]] {
                let words = predictor.suggestions(context: context, completions: completions,
                    corrections: corrections, neural: neural, writingLanguage: language,
                    languageScores: spelling.rankingScores(completions + corrections, language: language)
                        .merging(["momsen": 500], uniquingKeysWith: max), limit: 4)
                XCTAssertEqual(words.first, token)
                XCTAssertTrue(words.prefix(3).contains(expected), "\(context): \(words); candidates: \(corrections)")
                if expected.contains("'") {
                    XCTAssertEqual(words.dropFirst().first, expected, "Narrow row: \(context): \(words)")
                }
            }
        }
        for token in ["moms", "dads", "parents"] {
            XCTAssertNil(spelling.automaticCorrection(token, candidates: spelling.manualCorrections(token, language: .english)))
        }
        XCTAssertTrue(spelling.contractions("moms", language: .german).isEmpty)
        let language = spelling.writingLanguage(in: "Ipgone", preference: .german)
        XCTAssertEqual(language, .german)
        let corrections = spelling.manualCorrections("Ipgone", language: language)
        let words = predictor.suggestions(context: "Ipgone", corrections: corrections, writingLanguage: language)
        XCTAssertTrue(words.contains("iPhone"), words.description)
        XCTAssertTrue(spelling.manualCorrections("mom's", language: .english).isEmpty)
        XCTAssertEqual(predictor.suggestions(context: "mom's").first, "mom's")
    }

    func testSupplementalVocabularyResourcesAndCompletionReachBothBundles() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let keyboard = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("SimpleKeyboardExtension.appex")))
        for bundle in [Bundle.main, keyboard] {
            let manifestURL = try XCTUnwrap(bundle.url(forResource: "EnglishProvenance", withExtension: "json", subdirectory: "Dictionaries/Western"))
            let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
            let entries = try XCTUnwrap(manifest["generated"] as? [String: [String: Any]])
            for (name, record) in entries {
                let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil, subdirectory: "Dictionaries/Western"))
                let data = try Data(contentsOf: url)
                XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), record["sha256"] as? String)
            }
        }
        let spelling = MultilingualSpelling()
        XCTAssertTrue(spelling.completions("blockch", language: .english).contains("blockchain"))
        // Usage tables can include typos. They must not establish spelling validity.
        XCTAssertFalse(spelling.memberships("teh").contains(.english))
        XCTAssertFalse(spelling.memberships("recieve").contains(.english))
        XCTAssertFalse(spelling.completions("reciev", language: .english).contains("recieve"))
        XCTAssertFalse(spelling.completions("reciev", language: .english).contains("recieved"))
    }

    func testManualSearchReportsColdAndCachedLatencyWithFullDictionaries() {
        let spelling = MultilingualSpelling()
        for (word, language) in [("Birtgcertificate", TypingLanguage.english), ("cheaoer", TypingLanguage.afrikaans), ("blckchan", .english),
                                 ("besprechugn", .german), (String(repeating: "q", count: 32), .german)] {
            let start = CFAbsoluteTimeGetCurrent()
            let first = spelling.manualCorrections(word, language: language)
            let cold = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let cachedStart = CFAbsoluteTimeGetCurrent()
            XCTAssertEqual(spelling.manualCorrections(word, language: language), first)
            let cached = (CFAbsoluteTimeGetCurrent() - cachedStart) * 1000
            print("SPELLING_METRICS length=\(word.count) language=\(language.rawValue) cold_ms=\(cold) cached_ms=\(cached)")
        }
    }

    func testEnglishTypoCandidatesReachTheVisibleSuggestions() {
        let spelling = MultilingualSpelling()
        let predictor = PredictionEngine(multilingual: true)
        let samples = [("atuff", "stuff"), ("stiffq", "stiff"), ("tomorow", "tomorrow"),
                       ("messsage", "message"), ("recieve", "receive"), ("adn", "and"),
                       ("teh", "the"), ("wgat", "what"), ("thibk", "think"),
                       ("thsnks", "thanks"), ("becsuse", "because"), ("pleaae", "please")]
        for (token, expected) in samples {
            let context = "we are only seeing " + token
            let corrections = Array(spelling.corrections(token, language: .english).prefix(9))
            XCTAssertTrue(corrections.contains(expected), "Candidates: \(token): \(corrections)")
            let completions = Array(spelling.completions(token, language: .english).prefix(24))
            if Bundle.main.url(forResource: "EnglishVocabulary", withExtension: "txt") != nil {
                XCTAssertTrue(MultilingualSpelling.englishCorrections(token).contains(expected), "Bundled: \(token)")
            }
            for neural in [[], [expected, "unrelated"]] {
                let suggestions = predictor.suggestions(context: context, completions: completions,
                    corrections: corrections, neural: neural, writingLanguage: .english,
                    languageScores: spelling.rankingScores(completions + corrections, language: .english))
                XCTAssertEqual(suggestions.first, token)
                XCTAssertTrue(suggestions.contains(expected), "Visible: \(token): \(suggestions); corrections: \(corrections); neural: \(neural)")
            }
        }
        XCTAssertNil(spelling.automaticCorrection("adn", candidates: ["and"]))
        XCTAssertTrue(spelling.corrections("house", language: .english).isEmpty)
        XCTAssertTrue(spelling.corrections("API", language: .english).isEmpty)
    }

    func testEnglishContractionsCompeteWithCompletionsWithoutAutomaticReplacement() {
        let spelling = MultilingualSpelling()
        let predictor = PredictionEngine(multilingual: true)
        for (token, expected) in [("its", "it's"), ("Its", "It's"), ("dont", "don't"), ("ill", "I'll"), ("im", "I'm"), ("id", "I'd"),
                                  ("Atuff", "Stuff"), ("ATUFF", "STUFF"), ("tomorr", "tomorrow")] {
            let corrections = spelling.corrections(token, language: .english)
            let completions = spelling.completions(token, language: .english)
            for neural in [[], [expected] + completions] {
                let words = predictor.suggestions(context: token, completions: completions, corrections: corrections,
                    neural: neural, writingLanguage: .english,
                    languageScores: spelling.rankingScores(completions + corrections, language: .english))
                XCTAssertEqual(words.first, token)
                XCTAssertTrue(words.contains(expected), "\(token): \(words)")
                if token.lowercased() == "its" { XCTAssertEqual(words[1], expected) }
            }
        }
        XCTAssertNil(spelling.automaticCorrection("its", candidates: ["it's"]))
        XCTAssertNil(spelling.automaticCorrection("ill", candidates: ["I'll"]))
    }

    func testOfflineAfrikaansDictionaryProtectsCommonWordsAndAccents() {
        let spelling = MultilingualSpelling()
        XCTAssertGreaterThan(MultilingualSpelling.afrikaans.count, 100_000)
        for word in ["dag", "Dag", "DAG", "dankie", "vandag", "baie", "lekker", "huis", "m\u{00f4}re", "goeiem\u{00f4}re"] {
            XCTAssertTrue(spelling.isKnown(word), word)
            XCTAssertEqual(spelling.corrections(word), [], word)
            XCTAssertNil(spelling.automaticCorrection(word, candidates: ["dad"]), word)
        }
        XCTAssertTrue(spelling.completions("danki").contains("dankie"))
        XCTAssertTrue(MultilingualSpelling.afrikaans.corrections("dankei").contains("dankie"))
        XCTAssertTrue(spelling.corrections("dankiq").contains("dankie"), String(describing: spelling.corrections("dankiq")))
    }
    func testEnglishAndGermanWordsShareTheSpellingCheck() {
        XCTAssertGreaterThan(MultilingualSpelling.german.count, 100_000)
        XCTAssertTrue(MultilingualSpelling.german.completions("Besprech").contains("Besprechung"))
        let spelling = MultilingualSpelling()
        for word in ["hello", "tomorrow", "Gr\u{00fc}\u{00df}e", "Stra\u{00df}e", "Besprechung", "morgen"] {
            XCTAssertTrue(spelling.isKnown(word), word)
            XCTAssertTrue(spelling.corrections(word).isEmpty, word)
        }
        XCTAssertTrue(spelling.completions("Besprech").contains { $0.lowercased() == "besprechung" }, String(describing: spelling.completions("Besprech")))
        XCTAssertFalse(spelling.isKnown("qzxqzxqz"))
    }
    func testAutomaticCorrectionLeavesAmbiguousAndShortWordsAlone() {
        let spelling = MultilingualSpelling()
        XCTAssertNil(spelling.automaticCorrection("dag", candidates: ["dad"]))
        XCTAssertNil(spelling.automaticCorrection("zax", candidates: ["tax"]))
        XCTAssertNil(spelling.automaticCorrection("qell", candidates: ["well", "tell"]))
        XCTAssertEqual(spelling.automaticCorrection("teh", candidates: ["ten", "the"]), "the")
        XCTAssertEqual(spelling.automaticCorrection("teh", candidates: ["Eth", "the"]), "the")
        XCTAssertNil(spelling.automaticCorrection("API", candidates: ["app"]))
    }
    func testCompactDictionaryFindsBoundsAndCanonicalAccents() {
        let dictionary = WordLexicon(words: ["zulu", "m\u{00f4}re", "apple", "apple"])
        XCTAssertEqual(dictionary.count, 3)
        XCTAssertTrue(dictionary.contains("apple"))
        XCTAssertTrue(dictionary.contains("zulu"))
        XCTAssertFalse(dictionary.contains("a"))
        XCTAssertFalse(dictionary.contains("zzzz"))
        XCTAssertTrue(dictionary.contains("mo\u{0302}re"))
        XCTAssertEqual(dictionary.completions("M"), ["m\u{00f4}re"])
        XCTAssertTrue(dictionary.corrections("more").contains("m\u{00f4}re"))
    }

    func testLongTokensAreBoundedAndEmptyDictionariesStayEmpty() {
        let dictionary = WordLexicon(words: [])
        XCTAssertEqual(dictionary.count, 0)
        XCTAssertFalse(dictionary.contains("hello"))
        XCTAssertTrue(dictionary.completions("h").isEmpty)
        let long = String(repeating: "q", count: 10_000)
        XCTAssertTrue(MultilingualSpelling.afrikaans.corrections(long).isEmpty)
        XCTAssertTrue(MultilingualSpelling.german.corrections(long).isEmpty)
    }

    func testWritingContextSelectsTheModelWithoutKeyboardLayout() {
        let spelling = MultilingualSpelling()
        XCTAssertEqual(spelling.writingLanguage(in: "we should review "), .english)
        XCTAssertEqual(spelling.writingLanguage(in: "ich brauche "), .german)
        XCTAssertEqual(spelling.writingLanguage(in: "baie dankie "), .afrikaans)
        XCTAssertEqual(spelling.writingLanguage(in: ""), .english)
    }
    func testPreferenceKeepsMixedWordsRecognizedAndClearContextWins() {
        let spelling = MultilingualSpelling()
        for preference in PreferredLanguage.allCases {
            XCTAssertEqual(spelling.writingLanguage(in: "", preference: preference), preference.language ?? .english)
            XCTAssertEqual(spelling.writingLanguage(in: "we should review ", preference: preference), .english)
            XCTAssertEqual(spelling.writingLanguage(in: "we should review baie dankie ", preference: preference), .afrikaans)
            XCTAssertEqual(spelling.writingLanguage(in: "baie dankie ich brauche ", preference: preference), .german)
            for word in ["hello", "dankie", "Besprechung"] {
                XCTAssertTrue(spelling.isKnown(word))
                XCTAssertNil(spelling.automaticCorrection(word, candidates: ["the"]))
            }
        }
        let scores = spelling.rankingScores(["dankie", "Besprechung", "hello"], language: .afrikaans)
        XCTAssertGreaterThan(scores["dankie", default: 0], scores["hello", default: 0])
        XCTAssertGreaterThan(scores["dankie", default: 0], scores["besprechung", default: 0])
    }

    func testBundledEnglishCompletionsKeepFrequencyCaseAndShortPrefixes() throws {
        try XCTSkipUnless(Bundle.main.url(forResource: "EnglishCompletions", withExtension: "txt",
                                         subdirectory: "Dictionaries") != nil, "Optional English table is absent.")
        let prefixes = MultilingualSpelling.englishPrefixes
        XCTAssertGreaterThan(prefixes.count, 50_000)
        XCTAssertEqual(prefixes.values(for: "t"), ["the", "to", "this", "that", "their", "two", "they", "time"])
        XCTAssertEqual(prefixes.values(for: "th").first, "the")
        XCTAssertEqual(prefixes.values(for: "ple").first, "please")
        XCTAssertTrue(prefixes.values(for: "mee").contains("meeting"))
        XCTAssertEqual(prefixes.values(for: "iph"), ["iPhone"])
        XCTAssertEqual(prefixes.values(for: "IPH"), ["iPhone"])
        XCTAssertTrue(prefixes.values(for: "don").contains("don't"))
        XCTAssertTrue(prefixes.values(for: "").isEmpty)
        XCTAssertTrue(prefixes.values(for: "qzxqzxqz").isEmpty)
        let spelling = MultilingualSpelling()
        let predictor = PredictionEngine(multilingual: true)
        for token in ["t", "th"] {
            let suggestions = predictor.suggestions(context: "Please send " + token,
                completions: spelling.completions(token), lowercaseEnglishWords: ["the", "to", "this", "that"])
            XCTAssertEqual(suggestions.first, token)
            XCTAssertTrue(suggestions.contains("the"), suggestions.description)
        }
        let phoneCompletions = spelling.completions("iph")
        let phoneSuggestions = predictor.suggestions(context: "use iph", completions: phoneCompletions)
        XCTAssertTrue(phoneSuggestions.contains("iPhone"), "Completions: \(phoneCompletions); suggestions: \(phoneSuggestions)")
        XCTAssertTrue(spelling.completions("").isEmpty)
    }

    func testGeneratedPrefixTableHasBoundedDistinctProperCompletions() throws {
        guard let url = Bundle.main.url(forResource: "EnglishCompletions", withExtension: "txt", subdirectory: "Dictionaries") else {
            throw XCTSkip("Optional English table is absent.")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("\n"))
        var previous: [UInt8] = []
        for row in text.split(separator: "\n") {
            let columns = row.split(separator: "\t").map(String.init)
            let prefix = try XCTUnwrap(columns.first)
            let candidates = Array(columns.dropFirst())
            let bytes = Array(prefix.utf8)
            XCTAssertTrue(previous.isEmpty || previous.lexicographicallyPrecedes(bytes))
            previous = bytes
            XCTAssertTrue((1...8).contains(candidates.count))
            XCTAssertEqual(Set(candidates.map { $0.precomposedStringWithCanonicalMapping.lowercased() }).count, candidates.count)
            for word in candidates {
                XCTAssertTrue(TextRules.isWord(word), word)
                let key = word.precomposedStringWithCanonicalMapping.lowercased()
                XCTAssertTrue(key.hasPrefix(prefix))
                XCTAssertNotEqual(key, prefix)
            }
        }
    }

    private var westernSamples: [(TypingLanguage, String, String, String, String, String, String)] {
        [
            (.spanish, "gracias", "grac", "gracais", "muchas gracias ", "por", "necesito comprar comida para esta noche"),
            (.french, "bonjour", "bonj", "bonjor", "merci beaucoup ", "pour", "nous allons acheter du pain ce soir"),
            (.italian, "buongiorno", "buong", "buongirono", "grazie per ", "il", "domani voglio comprare qualcosa da mangiare"),
            (.portuguese, "obrigado", "obrig", "obrigdao", "muito obrigado ", "pela", "preciso comprar comida para esta noite"),
            (.dutch, "bedankt", "bedan", "bednakt", "bedankt voor ", "je", "we willen vanavond samen lekker eten"),
            (.swedish, "tack", "tac", "tcak", "vi ses ", "i", "vi beh\u{00f6}ver k\u{00f6}pa mat till kv\u{00e4}llen"),
            (.danish, "morgen", "morg", "mrogen", "tak for ", "din", "vi skal k\u{00f8}be mad til aftensmaden"),
            (.norwegian, "hjelpen", "hjel", "hjelpne", "takk for ", "hjelpen", "vi trenger mat til middag i kveld"),
            (.finnish, "kiitos", "kiit", "kiitso", "olen matkalla ", "kotiin", "haluan ostaa ruokaa t\u{00e4}n\u{00e4} iltana")
        ]
    }

    func testWesternLanguagesKeepWordsCompletePrefixesAndOfferTypoCorrectionsOffline() {
        let spelling = MultilingualSpelling()
        for (language, word, prefix, typo, _, _, _) in westernSamples {
            XCTAssertTrue(spelling.memberships(word).contains(language), language.rawValue)
            XCTAssertTrue(spelling.corrections(word, language: language).isEmpty, word)
            XCTAssertTrue(spelling.completions(prefix, language: language).prefix(8).contains(word), word)
            XCTAssertTrue(spelling.corrections(typo, language: language).contains(word), typo)
            XCTAssertNil(spelling.automaticCorrection(word, candidates: [typo]), word)
            XCTAssertFalse(spelling.isKnown("qzxqzxqz"))
            XCTAssertNil(language.neuralLanguage)
        }
    }

    func testWesternPhrasePredictionsAndHeldOutLanguageDetectionUseEitherLayout() {
        let spelling = MultilingualSpelling()
        for layout in KeyboardLanguage.allCases {
            let predictor = PredictionEngine(language: layout, multilingual: true)
            for (language, _, _, _, context, next, heldOut) in westernSamples {
                let suggestions = predictor.suggestions(context: context, sentenceStart: false, writingLanguage: language)
                XCTAssertTrue(suggestions.contains(next), language.rawValue + suggestions.description)
                XCTAssertEqual(spelling.writingLanguage(in: heldOut + " "), language, heldOut)
                let tokens = heldOut.split(separator: " ").map(String.init)
                let recognized = tokens.filter { spelling.memberships($0).contains(language) }.count
                XCTAssertGreaterThanOrEqual(Double(recognized) / Double(tokens.count), 0.8, heldOut)
                for token in tokens { XCTAssertNil(spelling.automaticCorrection(token, candidates: spelling.corrections(token, language: language)), token) }
            }
        }
    }

    func testSharedWordsAndCorrectionCollisionsRemainConservative() {
        let spelling = MultilingualSpelling()
        XCTAssertEqual(spelling.writingLanguage(in: "we should review your "), .english)
        XCTAssertTrue([TypingLanguage.swedish, .norwegian].contains(spelling.writingLanguage(in: "ha en bra dag ")))
        XCTAssertEqual(spelling.writingLanguage(in: "ha en bra dag ", preference: .swedish), .swedish)
        XCTAssertEqual(spelling.writingLanguage(in: "ik denk dat dit een goed idee is "), .dutch)
        XCTAssertEqual(spelling.writingLanguage(in: "muchas gracias your "), .spanish)
        XCTAssertEqual(spelling.writingLanguage(in: "hello merci beaucoup "), .french)
        XCTAssertEqual(spelling.writingLanguage(in: "bonjour we should review "), .english)
        XCTAssertTrue(spelling.isKnown("adn"))
        XCTAssertNil(spelling.automaticCorrection("adn", candidates: ["and"]))
        XCTAssertEqual(spelling.automaticCorrection("teh", candidates: spelling.corrections("teh", language: .english)), "the")
        for preference in PreferredLanguage.allCases {
            XCTAssertEqual(spelling.writingLanguage(in: "", preference: preference), preference.language ?? .english)
        }
    }

    func testWesternResourcesAndNoticesExistInAppAndKeyboardBundles() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let keyboard = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("SimpleKeyboardExtension.appex")))
        let attributes = (keyboard.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
        XCTAssertEqual(attributes?["RequestsOpenAccess"] as? Bool, false)
        for bundle in [Bundle.main, keyboard] {
            for (language, _, _, _, _, _, _) in westernSamples {
                let words = WordLexicon(bundle: bundle, resource: language.code + "Words", subdirectory: "Dictionaries/Western")
                XCTAssertGreaterThan(words.count, 10_000, language.rawValue)
            }
            for name in ["Wordfreq-credits", "Wordfreq-code-license", "CC-BY-SA-4.0"] {
                let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "txt", subdirectory: "Dictionaries/Western"))
                XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).isEmpty)
            }
            let privacy = try XCTUnwrap(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
            let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: privacy), format: nil) as? [String: Any])
            XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
            XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        }
    }

    func testGeneratedWesternTablesMatchTheirManifestAndPrefixBounds() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Provenance", withExtension: "json", subdirectory: "Dictionaries/Western"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(manifest["version"] as? String, "3.1.1")
        let files = try XCTUnwrap(manifest["generated"] as? [String: [String: Any]])
        XCTAssertEqual(files.count, 18)
        for (name, record) in files {
            let path = url.deletingLastPathComponent().appendingPathComponent(name)
            let data = try Data(contentsOf: path)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, record["sha256"] as? String, name)
            let rows = String(decoding: data, as: UTF8.self).split(separator: "\n")
            XCTAssertEqual(rows.count, record["entries"] as? Int, name)
            var previous: [UInt8] = []
            for row in rows {
                let fields = row.split(separator: "\t").map(String.init)
                let key = try XCTUnwrap(fields.first)
                let bytes = Array(key.utf8)
                XCTAssertTrue(previous.isEmpty || previous.lexicographicallyPrecedes(bytes), name)
                previous = bytes
                XCTAssertEqual(key, key.precomposedStringWithCanonicalMapping.lowercased())
                if name.contains("Completions") {
                    let candidates = Array(fields.dropFirst())
                    XCTAssertTrue((1...4).contains(key.count))
                    XCTAssertTrue((1...8).contains(candidates.count))
                    XCTAssertEqual(Set(candidates).count, candidates.count)
                    XCTAssertTrue(candidates.allSatisfy { $0.hasPrefix(key) && $0 != key && TextRules.isWord($0) })
                }
            }
        }
    }

}
