import UIKit
import NaturalLanguage

final class MultilingualSpelling {
    typealias WritingLanguage = TypingLanguage
    private let checker = UITextChecker()
    private let recognizer = NLLanguageRecognizer()
    private var languageCache: (String, PreferredLanguage, TypingLanguage)?
    private var repairCache: [String: [String]] = [:]
    static let afrikaans = WordLexicon(bundle: .main)
    static let german = WordLexicon(bundle: .main, resource: "GermanWords")
    static let englishPrefixes = WordLexicon(bundle: .main, resource: "EnglishCompletions")
    private static let supplementalPrefixes = WordLexicon(bundle: .main, resource: "EnglishSupplementCompletions", subdirectory: "Dictionaries/Western")
    private static let englishNameForms = Dictionary(uniqueKeysWithValues: [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "eBay", "iPad", "iPadOS", "iPhone", "iPod", "iOS", "iTunes", "macOS"
    ].map { ($0.lowercased(), $0) })
    private static let supplementalEnglish: (words: WordLexicon, ranks: [String: Int], contractions: [String: [String]]) = {
        let url = Bundle.main.url(forResource: "EnglishRanked", withExtension: "txt", subdirectory: "Dictionaries/Western")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let words = text.split(separator: "\n").map(String.init)
        var contractions: [String: [String]] = [:]
        for word in words {
            let plain = word.filter { $0 != "'" && $0 != "\u{2019}" }
            if plain != word { contractions[plain, default: []].append(word) }
        }
        return (WordLexicon(bundle: .main, resource: "EnglishWords", subdirectory: "Dictionaries/Western"),
                Dictionary(words.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min), contractions)
    }()
    private static let englishVocabulary: (words: WordLexicon, ranks: [String: Int], forms: [String: String], lowercaseWords: Set<String>, contractions: [String: [String]]) = {
        let url = Bundle.main.url(forResource: "EnglishVocabulary", withExtension: "txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        var ranks: [String: Int] = [:], forms: [String: String] = [:]
        var lowercaseWords = Set<String>()
        var contractions: [String: [String]] = [:]
        for (rank, entry) in text.split(separator: "\n").enumerated() {
            let word = String(entry).precomposedStringWithCanonicalMapping
            let key = word.lowercased()
            guard TextRules.isWord(word), word.count <= 32 else { continue }
            if word == key { lowercaseWords.insert(key) }
            guard ranks[key] == nil else { continue }
            ranks[key] = rank
            forms[key] = word
            let plain = key.filter { $0 != "'" && $0 != "\u{2019}" }
            if plain != key { contractions[plain, default: []].append(word) }
        }
        return (WordLexicon(words: Array(ranks.keys)), ranks, forms, lowercaseWords, contractions)
    }()
    static func englishCorrections(_ word: String) -> [String] {
        let vocabulary = englishVocabulary
        let contractions = vocabulary.contractions[word.lowercased()] ?? []
        let edits = vocabulary.words.corrections(word, limit: Int.max)
        return Set(edits + contractions.map { $0.lowercased() }).sorted {
            let left = vocabulary.ranks[$0] ?? Int.max, right = vocabulary.ranks[$1] ?? Int.max
            return left == right ? $0 < $1 : left < right
        }.prefix(12).map { vocabulary.forms[$0] ?? $0 }
    }
    func contractions(_ word: String, language: TypingLanguage) -> [String] {
        guard language == .english else { return [] }
        let lookup = word.precomposedStringWithCanonicalMapping.lowercased()
        let model = Self.englishVocabulary.contractions[lookup] ?? []
        let supplemental = Self.supplementalEnglish.contractions[lookup] ?? []
        return interleave([model, checkedEnglishUsage(supplemental)])
    }
    private static let western = TypingLanguage.allCases.filter {
        ![TypingLanguage.english, .german, .afrikaans].contains($0)
    }.map { language in
        (language, WordLexicon(bundle: .main, resource: language.code + "Words", subdirectory: "Dictionaries/Western"),
         WordLexicon(bundle: .main, resource: language.code + "Completions", subdirectory: "Dictionaries/Western"))
    }
    private lazy var languages: [(String, WritingLanguage)] = {
        let available = UITextChecker.availableLanguages
        return [("en_US", WritingLanguage.english), ("de_DE", .german)].compactMap { code, language in
            guard let supported = available.first(where: { $0 == code }) ?? available.first(where: { $0.hasPrefix(String(code.prefix(2))) }),
                  !self.accepts("qzxqzxqz", language: supported) else { return nil }
            return (supported, language)
        }
    }()
    private var membershipCache: [String: Set<TypingLanguage>] = [:]
    private func accepts(_ word: String, language: String) -> Bool {
        checker.rangeOfMisspelledWord(in: word, range: NSRange(word.startIndex..., in: word),
                                     startingAt: 0, wrap: false, language: language).location == NSNotFound
    }
    func isKnown(_ word: String) -> Bool {
        !memberships(word).isEmpty
    }
    func memberships(_ word: String) -> Set<TypingLanguage> {
        guard TextRules.isWord(word) else { return [] }
        let word = word.precomposedStringWithCanonicalMapping
        if let cached = membershipCache[word] { return cached }
        var result = Set<TypingLanguage>()
        if Self.afrikaans.contains(word) { result.insert(.afrikaans) }
        if Self.german.contains(word) { result.insert(.german) }
        for (language, words, _) in Self.western where words.contains(word) { result.insert(language) }
        for (code, language) in languages {
            if accepts(word, language: code) || (language == .german && accepts(word.capitalized, language: code)) {
                result.insert(language)
            }
        }
        if membershipCache.count >= 512 { membershipCache.removeAll(keepingCapacity: true) }
        membershipCache[word] = result
        return result
    }
    func rankingScores(_ candidates: [String], language: TypingLanguage) -> [String: Int] {
        var result: [String: Int] = [:]
        for word in candidates.prefix(96) {
            let parts = word.split(separator: " ").map(String.init)
            result[word.lowercased()] = !parts.isEmpty && parts.allSatisfy { memberships($0).contains(language) } ? 500 : 0
        }
        return result
    }
    private static func canonicalMixedCase(_ word: String) -> String {
        let lowercase = word.lowercased()
        guard let form = englishVocabulary.forms[lowercase] ?? englishNameForms[lowercase],
              form != form.uppercased(), form.dropFirst().contains(where: { $0.isUppercase }) else { return word }
        return form
    }
    private func checkedEnglishUsage(_ words: [String]) -> [String] {
        let forms = words.map { Self.englishNameForms[$0] ?? Self.canonicalMixedCase($0) }
        guard let code = languages.first(where: { $0.1 == .english })?.0 else { return forms }
        return forms.filter { accepts($0, language: code) }
    }
    func completions(_ word: String, language: TypingLanguage? = nil) -> [String] {
        guard TextRules.isWord(word) else { return [] }
        let lists: [(TypingLanguage, [String])] = [
            (.english, Self.englishPrefixes.values(for: word) + checkedEnglishUsage(Self.supplementalPrefixes.values(for: word))),
            (.german, Self.german.completions(word)), (.afrikaans, Self.afrikaans.completions(word))
        ] + Self.western.map { language, words, prefixes in
            (language, word.count <= 4 ? prefixes.values(for: word) : words.completions(word))
        }
        if let language, let primary = lists.first(where: { $0.0 == language }) {
            // Keep the active language before the candidate limit.
            return interleave([primary.1 + interleave(lists.filter { $0.0 != language }.map(\.1))])
        }
        return interleave(lists.map(\.1))
    }
    func corrections(_ word: String, language: TypingLanguage? = nil) -> [String] {
        guard TextRules.isWord(word), (2...32).contains(word.count) else { return [] }
        let lookup = word.lowercased()
        let contractions = language.map { self.contractions(lookup, language: $0) } ?? []
        if word.count < 3 { return contractions }
        if let language {
            if memberships(lookup).contains(language) || (language == .english && Self.englishVocabulary.words.contains(lookup)) {
                return contractions
            }
        } else if isKnown(word) { return [] }
        let range = NSRange(word.startIndex..., in: word)
        var lists = languages.filter { language == nil || $0.1 == language }.map { code, _ in
            Array((checker.guesses(forWordRange: range, in: word, language: code) ?? []).prefix(8))
        }
        if language == nil || language == .english { lists.append(Self.englishCorrections(word)) }
        if language == nil || language == .german { lists.append(Self.german.corrections(word)) }
        if language == nil || language == .afrikaans { lists.append(Self.afrikaans.corrections(word)) }
        for (candidateLanguage, words, _) in Self.western where language == nil || candidateLanguage == language {
            lists.append(words.corrections(word))
        }
        let candidates = interleave(lists)
        guard language == .english else { return candidates }
        let originalRanks = Dictionary(candidates.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return candidates.sorted {
            let leftDistance = TextRules.distance(word, $0), rightDistance = TextRules.distance(word, $1)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            let left = Self.englishVocabulary.ranks[$0.lowercased()] ?? Int.max
            let right = Self.englishVocabulary.ranks[$1.lowercased()] ?? Int.max
            return left == right ? originalRanks[$0, default: 0] < originalRanks[$1, default: 0] : left < right
        }
    }
    private func repairFrequency(_ word: String) -> Int {
        word.split(separator: " ").reduce(0) { score, part in
            score + (Self.supplementalEnglish.ranks[String(part).lowercased()] ??
                     Self.englishVocabulary.ranks[String(part).lowercased()] ?? 100_000)
        }
    }

    private func splitCorrections(_ word: String, language: TypingLanguage) -> [String] {
        guard (4...32).contains(word.count), word.allSatisfy({ $0.isLetter }),
              !Self.englishVocabulary.words.contains(word) else { return [] }
        let searchLanguages: [TypingLanguage] = language == .english ? [.english] : [language, .english]
        func known(_ part: String, _ language: TypingLanguage) -> Bool {
            if part.count == 1 { return language == .english && ["a", "i"].contains(part) }
            if language == .english {
                return Self.englishVocabulary.words.contains(part) ||
                    (Self.supplementalEnglish.words.contains(part) && !checkedEnglishUsage([part]).isEmpty)
            }
            return memberships(part).contains(language)
        }
        guard !searchLanguages.contains(where: { known(word, $0) }) else { return [] }
        func form(_ part: String, _ language: TypingLanguage) -> String {
            if language == .english {
                if !Self.englishVocabulary.lowercaseWords.contains(part),
                   let form = Self.englishVocabulary.forms[part] ?? Self.englishNameForms[part] { return form }
                return Self.canonicalMixedCase(part)
            }
            if language == .german, !Self.german.values(for: part).isEmpty {
                return part.prefix(1).uppercased() + part.dropFirst()
            }
            return part
        }
        func repairs(_ part: String, _ language: TypingLanguage) -> [String] {
            guard part.count >= 3 else { return [] }
            let sources: [WordLexicon]
            switch language {
            case .english: sources = [Self.englishVocabulary.words, Self.supplementalEnglish.words]
            case .german: sources = [Self.german]
            case .afrikaans: sources = [Self.afrikaans]
            default: sources = Self.western.filter { $0.0 == language }.map { $0.1 }
            }
            let candidates = sources.flatMap { $0.corrections(part, limit: Int.max, includingKnownWords: true) }
            return Array(Set(candidates.map { $0.lowercased() }).filter {
                known($0, language) && TextRules.distance(part, $0) == 1
            }.sorted {
                let left = repairFrequency($0), right = repairFrequency($1)
                return left == right ? $0 < $1 : left < right
            }.prefix(4))
        }
        let letters = Array(word)
        var candidates: [String: String] = [:]
        for language in searchLanguages {
            for boundary in 1..<letters.count {
                let left = String(letters[..<boundary]), right = String(letters[boundary...])
                let leftKnown = known(left, language), rightKnown = known(right, language)
                // One exact part bounds the search to one spelling edit.
                guard leftKnown || rightKnown else { continue }
                var pairs: [(String, String)] = []
                if leftKnown && rightKnown { pairs.append((left, right)) }
                if rightKnown { pairs += repairs(left, language).map { ($0, right) } }
                if leftKnown { pairs += repairs(right, language).map { (left, $0) } }
                for (first, second) in pairs {
                    let phrase = form(first, language) + " " + form(second, language)
                    if TextRules.isSplitCorrection(word: word, candidate: phrase), candidates[phrase.lowercased()] == nil {
                        candidates[phrase.lowercased()] = phrase
                    }
                }
            }
        }
        return Array(candidates.values.sorted {
            let leftDistance = TextRules.suggestionDistance(word, $0), rightDistance = TextRules.suggestionDistance(word, $1)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            let left = repairFrequency($0), right = repairFrequency($1)
            return left == right ? $0 < $1 : left < right
        }.prefix(8))
    }

    func manualCorrections(_ word: String, language: TypingLanguage) -> [String] {
        guard TextRules.isWord(word), (2...32).contains(word.count) else { return [] }
        let lookup = word.precomposedStringWithCanonicalMapping.lowercased()
        let key = language.rawValue + " " + lookup
        if let cached = repairCache[key] { return cached }
        let contractions = contractions(lookup, language: language)
        // Valid words retain only explicit contraction alternatives.
        guard !memberships(lookup).contains(language) else { return contractions }
        var lists = [contractions, corrections(lookup, language: language)]
        let secondary = TypingLanguage.allCases.filter { $0 != language }
        for other in secondary { lists.append(corrections(lookup, language: other)) }
        let distance = lookup.count >= 6 ? 2 : 1
        lists.append(checkedEnglishUsage(Self.supplementalEnglish.words.corrections(lookup, limit: Int.max, maximumDistance: distance)))
        if distance == 2 {
            switch language {
            case .afrikaans: lists.append(Self.afrikaans.corrections(lookup, maximumDistance: 2))
            case .german: lists.append(Self.german.corrections(lookup, maximumDistance: 2))
            case .english: lists.append(Self.englishVocabulary.words.corrections(lookup, limit: Int.max, maximumDistance: 2))
            default:
                if let words = Self.western.first(where: { $0.0 == language })?.1 {
                    lists.append(words.corrections(lookup, maximumDistance: 2))
                }
            }
        }
        let splits = splitCorrections(lookup, language: language)
        let candidates = interleave(lists).filter { TextRules.isSuggestionCorrection(word: lookup, candidate: $0) }
        let order = Dictionary(candidates.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let result = candidates.sorted {
            let leftDistance = TextRules.suggestionDistance(lookup, $0), rightDistance = TextRules.suggestionDistance(lookup, $1)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            let left = repairFrequency($0), right = repairFrequency($1)
            return left == right ? order[$0, default: 0] < order[$1, default: 0] : left < right
        }
        // Keep each source available before final context ranking.
        let reserved = lists.compactMap { $0.first(where: { TextRules.isSuggestionCorrection(word: lookup, candidate: $0) }) }
        let singleWords = interleave([Array(result.prefix(16)), reserved]).map(Self.canonicalMixedCase)
        let output = interleave([singleWords, splits], splitToken: lookup)
        if repairCache.count >= 128 { repairCache.removeAll(keepingCapacity: true) }
        repairCache[key] = output
        return output
    }
    func automaticCorrection(_ word: String, candidates: [String]) -> String? {
        guard !isKnown(word) else { return nil }
        let safe = candidates.filter {
            TextRules.safeCorrection(word: word, candidate: $0) &&
                !(word.first?.isLowercase == true && $0.first?.isUppercase == true)
        }
        let transposed = safe.filter { candidate in
            let original = Array(word.lowercased())
            let target = candidate.lowercased()
            return original.indices.dropLast().contains { index in
                var value = original
                value.swapAt(index, index + 1)
                return String(value) == target
            }
        }
        let choices = transposed.isEmpty ? (word.count >= 4 ? safe : []) : transposed
        let unique = Dictionary(choices.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return unique.count == 1 ? unique.values.first : nil
    }
    func writingLanguage(in context: String, preference: PreferredLanguage = .automatic) -> WritingLanguage {
        let complete = context.last?.isWhitespace == true ? context : String(context.dropLast((TextRules.suggestionToken(before: context) ?? TextRules.token(before: context)).count))
        let recent = String(complete.suffix(512))
        if let cached = languageCache, cached.0 == recent, cached.1 == preference { return cached.2 }
        var result = LanguageContext.resolve(recent, preference: preference, memberships: memberships)
        let tokens = recent.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" }).suffix(4).map(String.init)
        if tokens.count >= 2 {
            recognizer.reset()
            recognizer.processString(tokens.joined(separator: " "))
            if let (candidate, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
               confidence >= 0.6,
               let detected = TypingLanguage.allCases.first(where: { $0.code == candidate.rawValue || ($0 == .norwegian && candidate.rawValue == "no") }),
               tokens.suffix(2).allSatisfy({ memberships($0).contains(detected) }) {
                let preferredFits = preference.language == result && tokens.allSatisfy { memberships($0).contains(result) }
                if !preferredFits { result = detected }
            }
        }
        languageCache = (recent, preference, result)
        return result
    }
    private func interleave(_ lists: [[String]], splitToken: String? = nil) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where list.indices.contains(index) {
                let word = list[index]
                if TextRules.isWord(word) || splitToken.map({ TextRules.isSplitCorrection(word: $0, candidate: word) }) == true,
                   seen.insert(word.lowercased()).inserted { result.append(word) }
            }
        }
        return result
    }
}
