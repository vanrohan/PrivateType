import Foundation

public enum TextRules {
    public static func wordDeletionSuffixes(before context: String, allowLeadingToken: Bool,
                                            maxCharacters: Int = 256, maxWords: Int = 10) -> [String] {
        guard maxCharacters > 0, maxCharacters <= 256, maxWords > 0 else { return [] }
        let characters = Array(context.suffix(maxCharacters + 1))
        let completeStart = allowLeadingToken && characters.count == context.count
        var end = characters.count
        var suffixes: [String] = []
        for _ in 0..<min(maxWords, 10) {
            var start = end
            while start > 0, characters[start - 1].isWhitespace {
                if characters[start - 1].isNewline { return suffixes }
                start -= 1
            }
            let tokenEnd = start
            while start > 0, !characters[start - 1].isWhitespace { start -= 1 }
            guard start < tokenEnd, start > 0 || completeStart,
                  characters.count - start <= maxCharacters else { break }
            suffixes.append(String(characters[start...]))
            end = start
        }
        return suffixes
    }

    public static func isWord(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 32 && text.first?.isLetter == true &&
        text.last?.isLetter == true && text.allSatisfy { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }
    }

    public static func token(before context: String) -> String {
        String(context.reversed().prefix { !$0.isWhitespace }.reversed())
    }

    public static func suggestionToken(before context: String) -> String? {
        let raw = token(before: context)
        let lower = raw.lowercased()
        let domainParts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let isDomain = domainParts.count > 1 && domainParts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        guard !raw.contains("@"), !raw.contains("://"), !lower.hasPrefix("www."), !isDomain else { return nil }
        let active = String(raw.reversed().prefix {
            $0.isLetter || $0.isNumber || $0 == "'" || $0 == "\u{2019}"
        }.reversed())
        return active.isEmpty || isWord(active) ? active : nil
    }

    public static func prefix(before context: String) -> String {
        suggestionToken(before: context) ?? ""
    }

    public static func urlCompletions(before context: String) -> [String]? {
        let token = token(before: context)
        guard !token.isEmpty, token == context else { return nil }
        let lower = token.lowercased()
        if lower == "http" || lower == "https" {
            return ["https://", "http://"].filter { $0.hasPrefix(lower) }
        }
        let schemeLength = lower.hasPrefix("https://") ? 8 : lower.hasPrefix("http://") ? 7 : 0
        guard schemeLength > 0 || lower.contains(".") else { return nil }
        let host = String(token.dropFirst(schemeLength))
        guard token.count <= 512,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return [] }
        if host.isEmpty { return [token + "www."] }
        guard !host.hasPrefix("."), !host.contains(".."), host.lowercased() != "www.",
              host.split(separator: ".").allSatisfy({ !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else { return [] }
        let suffixes = ["com", "de", "org"]
        if !host.contains(".") || (host.lowercased().hasPrefix("www.") && host.filter({ $0 == "." }).count == 1 && !host.hasSuffix(".")) {
            return suffixes.map { token + "." + $0 }
        }
        guard let dot = token.lastIndex(of: ".") else { return [] }
        let ending = String(token[token.index(after: dot)...]).lowercased()
        let stem = String(token[...dot])
        return suffixes.filter { $0.hasPrefix(ending) }.map { stem + $0 }.filter { $0 != token }
    }

    public static func previousWord(before context: String) -> String? {
        guard !beginsSentence(context) else { return nil }
        let trimmed = String(context.reversed().drop(while: {
            !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "\u{2019}"
        }).reversed())
        guard let word = suggestionToken(before: trimmed), !word.isEmpty else { return nil }
        return word.lowercased()
    }

    public static func shouldCapitalizeSentence(before: String?, after: String?, hasText: Bool) -> Bool {
        guard let before else { return !hasText && (after ?? "").isEmpty }
        return beginsSentence(before)
    }

    public static func beginsSentence(_ context: String) -> Bool {
        var prefix = context[...]
        var separator = false
        let wrappers: Set<Character> = ["\"", "'", "\u{2018}", "\u{2019}", "\u{201c}", "\u{201d}", "(", ")", "[", "]", "{", "}"]
        while true {
            while let last = prefix.last, last.isWhitespace {
                if last.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) { return true }
                separator = true
                prefix.removeLast()
            }
            if let last = prefix.last, wrappers.contains(last) { prefix.removeLast() }
            else { break }
        }
        guard let last = prefix.last else { return true }
        guard separator, ".!?\u{2026}".contains(last) else { return false }
        guard last == "." else { return true }
        let token = prefix.split(whereSeparator: { $0.isWhitespace }).last.map { $0.lowercased() } ?? ""
        let abbreviations: Set<String> = ["e.g.", "i.e.", "mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "st.",
                                          "vs.", "etc.", "no.", "nr.", "z.b.", "d.h.", "bzw.", "ca.", "u.a.", "o.a.", "m.a.w.",
                                          "bv.", "ds.", "mev.", "mnr.", "mej."]
        if abbreviations.contains(token) || token.contains("://") || token.contains("@") || token.hasPrefix("www.") { return false }
        let initials = token.split(separator: ".")
        if initials.count > 1 && initials.allSatisfy({ $0.count == 1 && $0.first?.isLetter == true }) { return false }
        return true
    }

    public static func matchCase(_ candidate: String, to original: String) -> String {
        if original.count > 1 && original == original.uppercased() { return candidate.uppercased() }
        let firstWord = candidate.prefix { !$0.isWhitespace }
        if firstWord.first?.isLowercase == true, firstWord.contains(where: { $0.isUppercase }) { return candidate }
        if original.first?.isUppercase == true { return candidate.prefix(1).uppercased() + candidate.dropFirst() }
        return candidate
    }

    public static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.lowercased()), b = Array(rhs.lowercased())
        var previous = Array(0...b.count)
        var twoBack = previous
        for (i, left) in a.enumerated() {
            var row = [i + 1]
            for (j, right) in b.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
                if i > 0 && j > 0 && left == b[j - 1] && a[i - 1] == right {
                    row[j + 1] = min(row[j + 1], twoBack[j - 1] + 1)
                }
            }
            twoBack = previous
            previous = row
        }
        return previous[b.count]
    }

    public static func safeCorrection(word: String, candidate: String) -> Bool {
        guard isWord(word), isWord(candidate), word.count >= 3,
              word.lowercased() != candidate.lowercased(),
              !(word.count > 1 && word == word.uppercased()) else { return false }
        return distance(word, candidate) <= 1
    }

    public static func isSplitCorrection(word: String, candidate: String) -> Bool {
        guard isWord(word), (4...32).contains(word.count), candidate.count <= 33 else { return false }
        let parts = candidate.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(isWord) else { return false }
        return distance(word, parts.joined()) <= 1
    }

    public static func suggestionDistance(_ word: String, _ candidate: String) -> Int {
        candidate.contains(" ") ? 1 + distance(word, candidate.replacingOccurrences(of: " ", with: "")) : distance(word, candidate)
    }

    public static func isSuggestionCorrection(word: String, candidate: String) -> Bool {
        if isSplitCorrection(word: word, candidate: candidate) { return true }
        guard isWord(word), isWord(candidate), (2...32).contains(word.count), candidate.count <= 32,
              word.lowercased() != candidate.lowercased() else { return false }
        if word.count >= 3 { return distance(word, candidate) <= (word.count >= 6 ? 2 : 1) }
        let plain = candidate.lowercased().filter { $0 != "'" && $0 != "\u{2019}" }
        return plain == word.lowercased()
    }
}

public struct CorrectionUndo {
    public let original: String
    public let replacement: String
    public let context: String

    public init(original: String, replacement: String, context: String) {
        self.original = original
        self.replacement = replacement
        self.context = context
    }

    public func matches(_ currentContext: String) -> Bool {
        currentContext == context && currentContext.hasSuffix(replacement + " ")
    }
}
