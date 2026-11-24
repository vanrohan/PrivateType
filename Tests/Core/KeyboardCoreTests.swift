import XCTest
#if SWIFT_PACKAGE
@testable import KeyboardCore
#else
@testable import SimpleKeyboard
#endif

final class KeyboardCoreTests: XCTestCase {
    func testTwoEditSearchUsesTheSameDistanceRuleAsRanking() {
        let words = ["blockchain", "documentation", "tomorrow", "receive", "dankie", "caf\u{00e9}"]
        let dictionary = WordLexicon(words: words)
        for input in ["blckchan", "documntaton", "tomorw", "recive", "dnkei", "cafe", "zzzzzzzz"] {
            let expected = Set(words.filter { TextRules.distance(input, $0) <= 2 })
            XCTAssertEqual(Set(dictionary.corrections(input, limit: 100, maximumDistance: 2)), expected, input)
        }
        XCTAssertTrue(TextRules.isSuggestionCorrection(word: "blckchan", candidate: "blockchain"))
        XCTAssertFalse(TextRules.isSuggestionCorrection(word: "cat", candidate: "coatx"))
        XCTAssertFalse(TextRules.safeCorrection(word: "blckchan", candidate: "blockchain"))
    }

    func testSplitRepairsUseSeparateManualValidation() {
        for (input, phrase) in [("birtgcertificate", "birth certificate"), ("birthcertificate", "birth certificate"),
                                 ("brithcertificate", "birth certificate"), ("alot", "a lot"),
                                 (String(repeating: "a", count: 32), String(repeating: "a", count: 16) + " " + String(repeating: "a", count: 16))] {
            XCTAssertTrue(TextRules.isSuggestionCorrection(word: input, candidate: phrase), input)
            XCTAssertFalse(TextRules.isWord(phrase))
            XCTAssertFalse(TextRules.safeCorrection(word: input, candidate: phrase))
        }
        for phrase in ["birth  certificate", " birth certificate", "birth certificate ",
                       "birth\ncertificate", "birth certificate extra", "birth cert1ficate", "earth certificate"] {
            XCTAssertFalse(TextRules.isSuggestionCorrection(word: "birthcertificate", candidate: phrase), phrase)
        }
        XCTAssertFalse(TextRules.isSuggestionCorrection(word: "birthcertficat", candidate: "birth certificate"))
        XCTAssertFalse(TextRules.isSuggestionCorrection(word: "birtgcertifcate", candidate: "birth certificate"))
        XCTAssertEqual(TextRules.suggestionDistance("thankyou", "thank you"), 1)
        XCTAssertEqual(TextRules.suggestionDistance("thankyou", "than you"), 2)
        let lexicon = WordLexicon(words: ["form", "from"])
        XCTAssertTrue(lexicon.corrections("form").isEmpty)
        XCTAssertTrue(lexicon.corrections("form", includingKnownWords: true).contains("from"))
        XCTAssertEqual(TextRules.matchCase("use iPhone", to: "Useiphone"), "Use iPhone")
    }

    func testNextWordKeepsModelOrderAndSentenceBoundaries() {
        let predictor = PredictionEngine(multilingual: true)
        XCTAssertEqual(predictor.suggestions(context: "I am on my ", neural: ["phone", "way"], writingLanguage: .english).first, "phone")
        for context in ["on my. ", "on my! ", "on my\n", "on my.\" "] {
            let words = predictor.suggestions(context: context, writingLanguage: .english)
            XCTAssertEqual(words, predictor.suggestions(context: "", writingLanguage: .english), context)
        }
        XCTAssertEqual(predictor.suggestions(context: "thank you, ", writingLanguage: .english),
                       predictor.suggestions(context: "thank you ", writingLanguage: .english))
        var memory = LearningMemory()
        for _ in 0..<8 { memory.learn(word: "deployment", previous: "the") }
        XCTAssertEqual(PredictionEngine(memory: memory).suggestions(context: "the ").first, "deployment")
        XCTAssertEqual(PredictionEngine(memory: memory).suggestions(context: "the ", neural: ["report", "market"]).first, "deployment")
    }

    func testPrunedSearchMatchesExhaustiveDistanceAcrossSharedPrefixesAndAccents() {
        let words = ["block", "blockchain", "blocking", "blockchains", "documentation", "document", "documents",
                     "receive", "received", "receiver", "caf\u{00e9}", "caf\u{00e9}ine", "ma\u{00f1}ana", "m\u{00f4}re"]
        let dictionary = WordLexicon(words: words)
        for word in words {
            let letters = Array(word)
            var mutations = [String(letters.dropFirst()), String(letters.dropLast(2)), "x" + word, word + "x"]
            for index in 0..<(letters.count - 1) {
                var swapped = letters
                swapped.swapAt(index, index + 1)
                mutations.append(String(swapped))
            }
            for input in mutations where input.count >= 3 && !words.contains(input) {
                let expected = Set(words.filter { TextRules.distance(input, $0) <= 2 })
                XCTAssertEqual(Set(dictionary.corrections(input, limit: 100, maximumDistance: 2)), expected, input)
            }
        }
    }

    func testWordDeletionKeepsTokensGraphemesAndLineBoundaries() {
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: "one two  ", allowLeadingToken: true), ["two  ", "one two  "])
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: "one two  ", allowLeadingToken: false), ["two  "])
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: "one can't, ", allowLeadingToken: true).first, "can't, ")
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: "one " + family, allowLeadingToken: true).first, family)
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: "one\ntwo ", allowLeadingToken: true), ["two "])
        XCTAssertTrue(TextRules.wordDeletionSuffixes(before: "one\n", allowLeadingToken: true).isEmpty)
        XCTAssertTrue(TextRules.wordDeletionSuffixes(before: "   ", allowLeadingToken: true).isEmpty)
        XCTAssertTrue(TextRules.wordDeletionSuffixes(before: "", allowLeadingToken: true).isEmpty)
    }

    func testWordDeletionLimitsDoNotCutTokens() {
        let long = String(repeating: "a", count: 256)
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: "prefix " + long, allowLeadingToken: true), [long])
        XCTAssertTrue(TextRules.wordDeletionSuffixes(before: long + "a", allowLeadingToken: true).isEmpty)
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: long + " short ", allowLeadingToken: true), ["short "])
        XCTAssertEqual(TextRules.wordDeletionSuffixes(before: String(repeating: "word ", count: 20), allowLeadingToken: true).count, 10)
    }

    func testAlternateCharactersIncludeAccentsCaseAndSymbols() {
        XCTAssertTrue(AlternateCharacters.options(for: "u").contains("\u{00fc}"))
        XCTAssertTrue(AlternateCharacters.options(for: "o").contains("\u{00f4}"))
        XCTAssertTrue(AlternateCharacters.options(for: "e", uppercase: true).contains("\u{00ca}"))
        XCTAssertTrue(AlternateCharacters.options(for: ",").contains(";"))
        XCTAssertTrue(AlternateCharacters.options(for: ".").contains("\u{2026}"))
        XCTAssertEqual(AlternateCharacters.options(for: "space"), [])
    }

    func testCommaAndPeriodOfferEachOtherFirstAndKeepExistingAlternates() {
        for shifted in [false, true] {
            XCTAssertEqual(AlternateCharacters.options(for: ",", uppercase: shifted),
                           [".", ";", ":", "!", "?", "\u{201a}", "\u{201e}"])
            XCTAssertEqual(AlternateCharacters.options(for: ".", uppercase: shifted),
                           [",", "\u{2026}", "\u{00b7}", "\u{2022}", "?", "!"])
        }
    }

    func testCurrencyHoldsOfferEveryOtherCurrencyOnce() {
        let currencies = ["\u{20ac}", "$", "\u{00a3}", "\u{00a5}", "\u{00a2}"]
        for key in currencies {
            for shifted in [false, true] {
                let options = AlternateCharacters.options(for: key, uppercase: shifted)
                XCTAssertEqual(Set(options), Set(currencies).subtracting([key]))
                XCTAssertEqual(options.count, 4)
            }
        }
    }

    func testSharpSAlternativesKeepBothUnicodeCharactersInEitherCase() {
        for shifted in [false, true] {
            let options = AlternateCharacters.options(for: "s", uppercase: shifted)
            XCTAssertTrue(options.contains("\u{00df}"))
            XCTAssertTrue(options.contains("\u{1e9e}"))
            XCTAssertFalse(options.contains("SS"))
        }
    }

    func testKeyboardCaseUsesProperSingleCharacterForms() {
        for (lower, upper) in [("\u{00df}", "\u{1e9e}"), ("\u{00e6}", "\u{00c6}"), ("\u{0153}", "\u{0152}"), ("\u{00ff}", "\u{0178}"), ("\u{0142}", "\u{0141}"), ("\u{00ea}", "\u{00ca}"), ("\u{00f4}", "\u{00d4}")] {
            XCTAssertEqual(AlternateCharacters.cased(lower, uppercase: true), upper)
            XCTAssertEqual(AlternateCharacters.cased(lower, uppercase: false), lower)
        }
    }

    func testAccentMenusKeepSingleCharactersAndCompleteUmlautAlternatives() {
        let keys = ["a", "e", "i", "o", "u", "c", "n", "s", "y", "z", "l", "\u{00fc}", "\u{00f6}", "\u{00e4}", "\u{00df}", ",", ".", "-", "'", "\"", "\u{20ac}"]
        for key in keys {
            for shifted in [false, true] {
                let options = AlternateCharacters.options(for: key, uppercase: shifted)
                XCTAssertFalse(options.isEmpty, key)
                XCTAssertEqual(Set(options).count, options.count, key)
                XCTAssertTrue(options.allSatisfy { $0.count == 1 && $0 == $0.precomposedStringWithCanonicalMapping }, key)
            }
        }
        XCTAssertTrue(AlternateCharacters.options(for: "\u{00e4}").contains("\u{0101}"))
        XCTAssertTrue(AlternateCharacters.options(for: "\u{00f6}").contains("\u{014d}"))
        XCTAssertTrue(AlternateCharacters.options(for: "i", uppercase: true).contains("\u{0130}"))
        XCTAssertTrue(AlternateCharacters.options(for: "i", uppercase: true).contains("\u{0131}"))
    }

    func testEmojiSearchSupportsWordsAliasesCaseAndEmptyResults() {
        XCTAssertGreaterThan(EmojiCatalog.entries.count, 1000)
        XCTAssertEqual(Set(EmojiCatalog.entries.map(\.text)).count, EmojiCatalog.entries.count)
        XCTAssertEqual(EmojiCatalog.search("   "), EmojiCatalog.entries)
        XCTAssertTrue(EmojiCatalog.search("  CAT  ").contains { $0.text == "\u{1F431}" })
        XCTAssertTrue(EmojiCatalog.search("herz").contains { $0.text == "\u{2764}\u{FE0F}" })
        XCTAssertTrue(EmojiCatalog.search("thumbs up dark").contains { $0.text == "\u{1F44D}\u{1F3FF}" })
        XCTAssertTrue(EmojiCatalog.search("flag germany").contains { $0.text == "\u{1F1E9}\u{1F1EA}" })
        XCTAssertTrue(EmojiCatalog.search("reunion").contains { $0.text == "\u{1F1F7}\u{1F1EA}" })
        XCTAssertTrue(EmojiCatalog.search("rainbow flag").contains { $0.text == "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}" })
        XCTAssertTrue(EmojiCatalog.search("unmatchedquery").isEmpty)
        XCTAssertTrue(EmojiCatalog.search("cat elephant").isEmpty)
    }

    func testURLCompletionsStaySeparateFromSearchWordsAndCompletedAddresses() {
        XCTAssertNil(TextRules.urlCompletions(before: "keyboard"))
        XCTAssertNil(TextRules.urlCompletions(before: "how to build a keyboard"))
        XCTAssertEqual(TextRules.urlCompletions(before: "https"), ["https://"])
        XCTAssertEqual(TextRules.urlCompletions(before: "https://example"),
                       ["https://example.com", "https://example.de", "https://example.org"])
        XCTAssertEqual(TextRules.urlCompletions(before: "www.example"),
                       ["www.example.com", "www.example.de", "www.example.org"])
        XCTAssertEqual(TextRules.urlCompletions(before: "example.c"), ["example.com"])
        XCTAssertEqual(TextRules.urlCompletions(before: "shop2.example."),
                       ["shop2.example.com", "shop2.example.de", "shop2.example.org"])
        XCTAssertEqual(TextRules.urlCompletions(before: "https://example.d"), ["https://example.de"])
        for address in ["https://example.com", "https://example.com/path2?q=3", "192.168.0.1", "user@example.c", "www.", ".", "example..d", "https://-example"] {
            XCTAssertEqual(TextRules.urlCompletions(before: address), [], address)
        }
    }

    func testSuggestionsUseTheWordAfterSymbols() {
        let engine = PredictionEngine(language: .german)
        for separator in ["-", "_", "/", "+", "&", ":", ",", "--", "\u{2013}", "\u{2014}", "\u{1F600}"] {
            for stem in ["International", "2026"] {
                let context = stem + separator + "Geb"
                XCTAssertEqual(TextRules.suggestionToken(before: context), "Geb", context)
                XCTAssertEqual(engine.suggestions(context: context, completions: ["Geburtsurkunde"]),
                               engine.suggestions(context: stem + " Geb", completions: ["Geburtsurkunde"]), context)
                XCTAssertEqual(TextRules.suggestionToken(before: stem + separator), "", context)
                if stem == "International" {
                    XCTAssertEqual(TextRules.previousWord(before: stem + separator), "international", context)
                }
                XCTAssertEqual(engine.suggestions(context: stem + separator),
                               engine.suggestions(context: stem + " "), context)
            }
        }
        for boundary in ["hello. ", "hello! ", "hello? ", "hello\n"] {
            XCTAssertNil(TextRules.previousWord(before: boundary), boundary)
        }
        for word in ["don't", "we\u{2019}re", "Gr\u{00fc}\u{00df}e", "cafe\u{301}"] {
            XCTAssertEqual(TextRules.suggestionToken(before: "name-" + word), word)
        }
        for context in ["hello@example.com", "https://example.com/path", "www.example.com", "example.com", "invoice123", "name-abc123"] {
            XCTAssertNil(TextRules.suggestionToken(before: context), context)
            XCTAssertTrue(engine.suggestions(context: context).isEmpty, context)
        }
    }

    func testWordRulesKeepAddressesAndNumbersOut() {
        for token in ["", "hello@example.com", "https://example.com", "abc123", "hello,", "_token", "'hello"] {
            XCTAssertFalse(TextRules.isWord(token), token)
        }
        for word in ["hello", "don't", "Grüße", "Straße", "über", "we\u{2019}re", "cafe\u{301}"] {
            XCTAssertTrue(TextRules.isWord(word), word)
        }
        XCTAssertEqual(TextRules.prefix(before: "a hello@example.com"), "")
        XCTAssertEqual(TextRules.prefix(before: "Hallo Grüße"), "Grüße")
        XCTAssertEqual(TextRules.prefix(before: "hello "), "")
    }

    func testSentenceAndCaseRules() {
        XCTAssertTrue(TextRules.beginsSentence(""))
        XCTAssertTrue(TextRules.beginsSentence("hello. "))
        XCTAssertTrue(TextRules.beginsSentence("hello\n"))
        XCTAssertFalse(TextRules.beginsSentence("hello "))
        XCTAssertEqual(TextRules.matchCase("hello", to: "Helo"), "Hello")
        XCTAssertEqual(TextRules.matchCase("hello", to: "HELO"), "HELLO")
        XCTAssertEqual(TextRules.matchCase("Grüße", to: "grüße"), "Grüße")
    }

    func testMixedCaseSuggestionsRetainTheirCanonicalForm() {
        for (candidate, typo) in [("iPhone", "Ipgone"), ("eBay", "Ebay"), ("iTunes", "Itunea")] {
            XCTAssertEqual(TextRules.matchCase(candidate, to: typo), candidate)
            XCTAssertEqual(TextRules.matchCase(candidate, to: typo.lowercased()), candidate)
            XCTAssertEqual(TextRules.matchCase(candidate, to: typo.uppercased()), candidate.uppercased())
        }
    }

    func testSentenceBoundariesRequireEvidenceAndHandleCommonAbbreviations() {
        for context in ["", "Done. ", "Really? ", "Yes! ", "Done.\" ", "hello\n  ", "hello\r\n  ", "hello\u{2028}  ", "\"", "(Done.) "] {
            XCTAssertTrue(TextRules.beginsSentence(context), context)
        }
        for context in ["we should ", "hello.", "typing.E.g.", "Dr. ", "e.g. ", "i.e. ", "z.B. ", "U.S. ", "3.14 ", "https://example.", "https://example. ", "www. ", "hello, "] {
            XCTAssertFalse(TextRules.beginsSentence(context), context)
        }
        XCTAssertFalse(TextRules.shouldCapitalizeSentence(before: nil, after: "remaining text", hasText: true))
        XCTAssertFalse(TextRules.shouldCapitalizeSentence(before: nil, after: nil, hasText: true))
        XCTAssertFalse(TextRules.shouldCapitalizeSentence(before: nil, after: "text", hasText: false))
        XCTAssertTrue(TextRules.shouldCapitalizeSentence(before: nil, after: nil, hasText: false))
        XCTAssertTrue(TextRules.shouldCapitalizeSentence(before: "", after: "existing text", hasText: true))
    }

    func testSuggestionCaseCanUseTheCursorBoundaryInsteadOfAnEmptyContextFallback() {
        let engine = PredictionEngine()
        let ordinary: Set<String> = ["hello", "tomorrow"]
        let words = engine.suggestions(context: "", neural: ["Hello", "Tomorrow"], lowercaseEnglishWords: ordinary, sentenceStart: false)
        XCTAssertEqual(Array(words.prefix(2)), ["hello", "tomorrow"])
        XCTAssertEqual(engine.suggestions(context: "", neural: ["Hello"], lowercaseEnglishWords: ordinary, sentenceStart: true).first, "Hello")
    }

    func testConservativeCorrectionIncludesTransposedKeys() {
        XCTAssertTrue(TextRules.safeCorrection(word: "teh", candidate: "the"))
        XCTAssertTrue(TextRules.safeCorrection(word: "helo", candidate: "hello"))
        XCTAssertTrue(TextRules.safeCorrection(word: "Grüse", candidate: "Grüße"))
        XCTAssertFalse(TextRules.safeCorrection(word: "id", candidate: "it"))
        XCTAssertFalse(TextRules.safeCorrection(word: "API", candidate: "app"))
        XCTAssertFalse(TextRules.safeCorrection(word: "helo", candidate: "world"))
        XCTAssertFalse(TextRules.safeCorrection(word: "me@example.com", candidate: "example"))
    }

    func testCorrectionUndoNeedsTheSameContext() {
        let undo = CorrectionUndo(original: "teh", replacement: "the", context: "send the ")
        XCTAssertTrue(undo.matches("send the "))
        XCTAssertFalse(undo.matches("change the "))
        XCTAssertFalse(undo.matches("send the a"))
        XCTAssertFalse(undo.matches("send the"))
    }

    func testNextWordUsesContextInBothLanguages() {
        let english = PredictionEngine()
        XCTAssertTrue(english.suggestions(context: "on my ").contains("way"))
        XCTAssertTrue(english.suggestions(context: "thank ").contains("you"))
        XCTAssertTrue(english.suggestions(context: "see you ").contains("tomorrow"))
        let german = PredictionEngine(language: .german)
        XCTAssertTrue(german.suggestions(context: "ich bin ").contains("auf"))
        XCTAssertTrue(german.suggestions(context: "vielen ").contains("Dank"))
        XCTAssertFalse(german.suggestions(context: "vielen ").contains("you"))
        XCTAssertEqual(english.suggestions(context: "hello@example.com"), [])
        XCTAssertEqual(english.suggestions(context: "https://exa"), [])
    }

    func testCompletionPreservesTypedWordCaseAndUniqueResults() {
        let engine = PredictionEngine()
        let words = engine.suggestions(context: "Hel", completions: ["hello", "help", "hello"], corrections: ["hello", "hello"])
        XCTAssertEqual(words.first, "Hel")
        XCTAssertTrue(words.contains("Hello"))
        XCTAssertEqual(Set(words).count, words.count)
        XCTAssertTrue(engine.suggestions(context: "HEL", completions: ["hello"]).contains("HELLO"))
        XCTAssertTrue(engine.suggestions(context: "").allSatisfy { $0.first?.isUppercase == true })
    }

    func testDictionaryCaseAndPersonalWordDoNotRemoveTypedToken() {
        let german = PredictionEngine(language: .german)
        XCTAssertTrue(german.suggestions(context: "liebe gr", completions: ["Grüße"]).contains("Grüße"))
        XCTAssertTrue(german.suggestions(context: "ich habe eine ").contains("Frage"))
        XCTAssertTrue(PredictionEngine().suggestions(context: "but ").contains("I"))
        var memory = LearningMemory()
        for _ in 0..<40 { memory.learn(word: "deploy", previous: "please") }
        XCTAssertEqual(PredictionEngine(memory: memory).suggestions(context: "please de").first, "de")
    }

    func testEnglishSuggestionsUseSentenceContextInsteadOfModelTitleCase() {
        let engine = PredictionEngine()
        let ordinary: Set<String> = ["review", "work", "hello", "mark"]
        let words = engine.suggestions(context: "we should ", neural: ["Review", "Work", "The"], lowercaseEnglishWords: ordinary)
        XCTAssertEqual(Set(words), Set(["review", "work", "the"]))
        XCTAssertEqual(engine.suggestions(context: "Finished. ", neural: ["review"], lowercaseEnglishWords: ordinary).first, "Review")
        XCTAssertEqual(engine.suggestions(context: "we should Re", neural: ["Review"], lowercaseEnglishWords: ordinary).dropFirst().first, "Review")
        XCTAssertEqual(engine.suggestions(context: "we should RE", neural: ["Review"], lowercaseEnglishWords: ordinary).dropFirst().first, "REVIEW")
        XCTAssertEqual(engine.suggestions(context: "we should re", neural: ["Review"], lowercaseEnglishWords: ordinary).dropFirst().first, "review")
        XCTAssertEqual(engine.suggestions(context: "on ", neural: ["monday"]).first, "Monday")
        XCTAssertEqual(engine.suggestions(context: "we ", neural: ["may"]).first, "may")
        XCTAssertEqual(engine.suggestions(context: "ask ", neural: ["Mark"], lowercaseEnglishWords: ordinary, properForms: ["mark": "Mark"]).first, "Mark")
        XCTAssertEqual(engine.suggestions(context: "mark ", neural: ["API"]).first, "API")
        XCTAssertEqual(engine.suggestions(context: "but ", neural: ["i'm"]).first, "I'm")
        XCTAssertEqual(PredictionEngine(language: .german).suggestions(context: "deine ", neural: ["Hilfe"]).first, "Hilfe")
    }

    func testMultilingualPhraseSuggestionsCombineAllThreeLanguages() {
        for layout in KeyboardLanguage.allCases {
            let engine = PredictionEngine(language: layout, multilingual: true)
            XCTAssertTrue(engine.suggestions(context: "baie ").contains("dankie"))
            XCTAssertTrue(engine.suggestions(context: "vielen ").contains("Dank"))
            XCTAssertTrue(engine.suggestions(context: "on my ").contains("way"))
            XCTAssertEqual(engine.suggestions(context: "say dag", corrections: ["dad"]).first, "dag")
        }
    }

    func testLearningChangesPredictionAndStaysSerializable() throws {
        var memory = LearningMemory()
        for _ in 0..<8 { memory.learn(word: "deployment", previous: "the") }
        let engine = PredictionEngine(memory: memory)
        XCTAssertEqual(engine.suggestions(context: "the ").first, "deployment")
        XCTAssertEqual(engine.suggestions(context: "the dep").first, "dep")
        XCTAssertTrue(engine.suggestions(context: "the dep").contains("deployment"))
        let data = try JSONEncoder().encode(memory)
        XCTAssertEqual(try JSONDecoder().decode(LearningMemory.self, from: data), memory)
        XCTAssertFalse(PredictionEngine().suggestions(context: "the ").contains("deployment"))
    }

    func testLearningRejectsStructuredDataAndBoundsStorage() {
        var memory = LearningMemory()
        for word in ["user@example.com", "123456", "https://example.com", String(repeating: "a", count: 25)] {
            memory.learn(word: word, previous: "hello")
        }
        XCTAssertTrue(memory.words.isEmpty)
        XCTAssertTrue(memory.pairs.isEmpty)
        for index in 0..<700 {
            let suffix = String(UnicodeScalar(97 + index % 26)!) + String(UnicodeScalar(97 + index / 26 % 26)!) +
                String(UnicodeScalar(97 + index / 676)!)
            memory.learn(word: "word" + suffix, previous: "previous")
        }
        XCTAssertEqual(memory.words.count, 256)
        XCTAssertEqual(memory.pairs.count, 512)
    }

    func testTouchLearningNeedsSamplesAndLimitsMovement() throws {
        var model = TouchModel()
        model.learn(key: "a", x: 0.1, y: -0.1)
        XCTAssertEqual(model.offset(for: "a").count, 0)
        model.learn(key: "a", x: 0.1, y: -0.1)
        model.learn(key: "a", x: 0.1, y: -0.1)
        XCTAssertEqual(model.offset(for: "a").x, 0)
        for _ in 0..<40 { model.learn(key: "a", x: 1, y: -1) }
        XCTAssertLessThanOrEqual(model.offset(for: "a", variant: .candidate).x, 0.2)
        XCTAssertGreaterThanOrEqual(model.offset(for: "a").y, -0.2)
        model.learn(key: "delete", x: 0, y: 0)
        model.learn(key: "b", x: .nan, y: 0)
        model.learn(key: "c", x: 20, y: 0)
        XCTAssertNil(model.offsets["delete"])
        XCTAssertNil(model.offsets["b"])
        XCTAssertNil(model.offsets["c"])
        XCTAssertEqual(try JSONDecoder().decode(TouchModel.self, from: JSONEncoder().encode(model)), model)
    }
    func testLanguageContextUsesRecentClearEvidenceAndPreferenceOnlyForTies() {
        let words: [String: Set<TypingLanguage>] = [
            "hello": [.english], "dankie": [.afrikaans], "brauche": [.german],
            "shared": [.english, .german, .afrikaans], "pair": [.german, .afrikaans]
        ]
        for preference in PreferredLanguage.allCases {
            func resolve(_ context: String) -> TypingLanguage {
                LanguageContext.resolve(context, preference: preference) { words[$0.lowercased()] ?? [] }
            }
            XCTAssertEqual(resolve(""), preference.language ?? .english)
            XCTAssertEqual(resolve("shared "), [.german, .afrikaans].contains(preference) ? preference.language : .english)
            XCTAssertEqual(resolve("hello brauche dankie shared "), .afrikaans)
            XCTAssertEqual(resolve("dankie brauche hello, shared "), .english)
            XCTAssertEqual(resolve("hello dankie brauche! "), .german)
            XCTAssertEqual(resolve("hello dankie"), .english)
            XCTAssertEqual(resolve("pair "), preference == .german ? .german : .afrikaans)
        }
    }

    func testLanguageRankingKeepsOriginalAndOtherLanguageCandidates() {
        for layout in KeyboardLanguage.allCases {
            let predictor = PredictionEngine(language: layout, multilingual: true)
            let values = predictor.suggestions(context: "xx", completions: ["xxenglish", "xxgerman"],
                writingLanguage: .german, languageScores: ["xxgerman": 500])
            XCTAssertEqual(values.map { $0.lowercased() }, ["xx", "xxgerman", "xxenglish"])
        }
    }

    func testCompletionOrderBreaksTiesWithoutOverridingLearningOrNeuralScores() {
        let engine = PredictionEngine()
        let candidates = ["xyzulu", "xyalpha"]
        XCTAssertEqual(engine.suggestions(context: "say xy", completions: candidates), ["xy", "xyzulu", "xyalpha"])
        XCTAssertEqual(engine.suggestions(context: "say xy", completions: candidates, neural: ["xyalpha"]),
            ["xy", "xyalpha", "xyzulu"])
        var memory = LearningMemory()
        memory.learn(word: "xyalpha", previous: "say")
        XCTAssertEqual(PredictionEngine(memory: memory).suggestions(context: "say xy", completions: candidates),
            ["xy", "xyalpha", "xyzulu"])
        XCTAssertTrue(engine.suggestions(context: "use ap", completions: ["API"]).contains("API"))
    }

    func testOnlyEnglishUsesTheEnglishPronounCaseRule() {
        let predictor = PredictionEngine(multilingual: true)
        for language in [TypingLanguage.italian, .swedish, .norwegian] {
            let suggestions = predictor.suggestions(context: "vi ses ", neural: ["i"],
                                                    sentenceStart: false, writingLanguage: language)
            XCTAssertTrue(suggestions.contains("i"), language.rawValue)
            XCTAssertFalse(suggestions.contains("I"), language.rawValue)
        }
        XCTAssertTrue(predictor.suggestions(context: "please ", neural: ["i"], sentenceStart: false,
                                            writingLanguage: .english).contains("I"))
        XCTAssertTrue(predictor.suggestions(context: "kommer ", sentenceStart: false, writingLanguage: .danish).contains("I"))
        XCTAssertTrue(predictor.suggestions(context: "vi ses ", sentenceStart: false, writingLanguage: .danish).contains("i"))
        XCTAssertEqual(TypingLanguage.english.neuralLanguage, .english)
        XCTAssertEqual(TypingLanguage.german.neuralLanguage, .german)
    }

    func testWesternAccentCorrectionsAndCanonicalComposition() {
        let words = WordLexicon(words: ["citt\u{00e0}", "cos\u{00ec}", "per\u{00f2}", "men\u{00f9}",
                                        "ma\u{00f1}ana", "cora\u{00e7}\u{00e3}o", "hj\u{00e6}lp", "caf\u{00e9}", "caf\u{00e9}ine"])
        for (input, expected) in [("citta", "citt\u{00e0}"), ("cosi", "cos\u{00ec}"), ("pero", "per\u{00f2}"),
                                  ("menu", "men\u{00f9}"), ("manana", "ma\u{00f1}ana"),
                                  ("cora\u{00e7}ao", "cora\u{00e7}\u{00e3}o"), ("hjalp", "hj\u{00e6}lp")] {
            XCTAssertTrue(words.corrections(input).contains(expected), input)
        }
        XCTAssertTrue(words.contains("cafe\u{0301}"))
        XCTAssertEqual(words.completions("CAFE\u{0301}"), ["caf\u{00e9}ine"])
    }

}
