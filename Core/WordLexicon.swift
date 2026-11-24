import Foundation

public struct WordLexicon {
    private let bytes: Data
    private let offsets: [UInt32]
    public init(words: [String]) {
        let normalized = Set(words.filter { !$0.isEmpty }.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        self.init(data: normalized.isEmpty ? Data() : Data((normalized.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.joined(separator: "\n") + "\n").utf8))
    }
    private init(data: Data) {
        bytes = data
        var offsets: [UInt32] = []
        if !data.isEmpty { offsets.append(0) }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var position = 0
            while position < buffer.count,
                  let newline = memchr(base.advanced(by: position), 10, buffer.count - position) {
                position = base.distance(to: newline) + 1
                if position < buffer.count { offsets.append(UInt32(position)) }
            }
        }
        self.offsets = offsets
    }
    public init(bundle: Bundle, resource: String = "AfrikaansWords", subdirectory: String = "Dictionaries") {
        let url = bundle.url(forResource: resource, withExtension: "txt", subdirectory: subdirectory)
        self.init(data: url.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) } ?? Data())
    }
    public var count: Int { offsets.count }
    private func end(_ index: Int) -> Int {
        (index + 1 < count ? Int(offsets[index + 1]) : bytes.count) - 1
    }
    private func compare(_ index: Int, to key: [UInt8]) -> Int {
        var position = Int(offsets[index]), other = 0
        let limit = end(index)
        while position < limit && bytes[position] != 9 && other < key.count {
            if bytes[position] != key[other] { return bytes[position] < key[other] ? -1 : 1 }
            position += 1
            other += 1
        }
        let finished = position == limit || bytes[position] == 9
        return finished ? (other == key.count ? 0 : -1) : 1
    }
    private func lowerBound(_ key: [UInt8]) -> Int {
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            if compare(middle, to: key) < 0 { low = middle + 1 } else { high = middle }
        }
        return low
    }
    private func display(_ index: Int) -> String {
        let line = bytes[Int(offsets[index])..<end(index)]
        let tab = line.firstIndex(of: 9)
        let text = String(decoding: tab.map { line[..<$0] } ?? line[...], as: UTF8.self)
        return tab != nil ? text.prefix(1).uppercased() + text.dropFirst() : text
    }
    public func contains(_ word: String) -> Bool {
        let key = Array(word.precomposedStringWithCanonicalMapping.lowercased().utf8)
        let index = lowerBound(key)
        return index < count && compare(index, to: key) == 0
    }
    public func values(for key: String) -> [String] {
        guard !key.isEmpty else { return [] }
        let key = Array(key.precomposedStringWithCanonicalMapping.lowercased().utf8)
        let index = lowerBound(key)
        guard index < count, compare(index, to: key) == 0 else { return [] }
        let line = bytes[Int(offsets[index])..<end(index)]
        guard let tab = line.firstIndex(of: 9) else { return [] }
        return String(decoding: line[line.index(after: tab)...], as: UTF8.self)
            .split(separator: "\t").map(String.init)
    }
    public func completions(_ prefix: String, limit: Int = 8) -> [String] {
        let prefix = prefix.precomposedStringWithCanonicalMapping.lowercased()
        guard !prefix.isEmpty else { return [] }
        var result: [String] = []
        var index = lowerBound(Array(prefix.utf8))
        while index < count && result.count < 128 {
            let word = display(index)
            guard word.lowercased().hasPrefix(prefix) else { break }
            if word.lowercased() != prefix { result.append(word) }
            index += 1
        }
        return Array(result.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }.prefix(limit))
    }
    public func corrections(_ word: String, limit: Int = 12, maximumDistance: Int = 1, includingKnownWords: Bool = false) -> [String] {
        guard TextRules.isWord(word), (3...32).contains(word.count), includingKnownWords || !contains(word) else { return [] }
        if maximumDistance == 2 { return nearbyWords(word, limit: limit) }
        let characters = Array(word.precomposedStringWithCanonicalMapping.lowercased())
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz\u{00e2}\u{00e4}\u{00e8}\u{00e9}\u{00ea}\u{00eb}\u{00ee}\u{00ef}\u{00f4}\u{00f6}\u{00fb}\u{00fc}\u{00df}\u{00e0}\u{00ec}\u{00f2}\u{00f9}\u{00e1}\u{00e3}\u{00e5}\u{00e6}\u{00e7}\u{00ed}\u{00f1}\u{00f3}\u{00f5}\u{00f8}\u{00fa}\u{0153}'")
        var matches = Set<String>()
        func check(_ value: [Character]) {
            let key = Array(String(value).utf8)
            let index = lowerBound(key)
            if index < count && compare(index, to: key) == 0 { matches.insert(display(index)) }
        }
        for index in characters.indices {
            var value = characters
            value.remove(at: index)
            check(value)
            if index + 1 < characters.count {
                value = characters
                value.swapAt(index, index + 1)
                check(value)
            }
            for letter in alphabet where letter != characters[index] {
                value = characters
                value[index] = letter
                check(value)
            }
        }
        for index in 0...characters.count {
            for letter in alphabet {
                var value = characters
                value.insert(letter, at: index)
                check(value)
            }
        }
        return Array(matches.sorted().prefix(max(0, limit)))
    }

    private func nearbyWords(_ word: String, limit: Int) -> [String] {
        let target = Array(word.precomposedStringWithCanonicalMapping.lowercased())
        var prior: [Character] = []
        var rows = [Array(0...target.count)]
        var matches: [(String, Int)] = []
        var index = 0
        while index < count {
            let candidate = display(index)
            let letters = Array(candidate.lowercased())
            var shared = 0
            while shared < min(prior.count, letters.count), prior[shared] == letters[shared] { shared += 1 }
            rows = Array(rows.prefix(shared + 1))
            var pruned = false
            for position in shared..<letters.count {
                let previous = rows[position]
                var row = [position + 1]
                for column in target.indices {
                    var cost = min(row[column] + 1, previous[column + 1] + 1,
                                   previous[column] + (letters[position] == target[column] ? 0 : 1))
                    if position > 0, column > 0, letters[position] == target[column - 1],
                       letters[position - 1] == target[column] {
                        cost = min(cost, rows[position - 1][column - 1] + 1)
                    }
                    row.append(cost)
                }
                rows.append(row)
                if row.min()! > 2 {
                    // Skip every word with this prefix.
                    let prefix = Array(letters.prefix(position + 1))
                    index = lowerBound(Array(String(prefix).utf8) + [255])
                    prior = prefix
                    pruned = true
                    break
                }
            }
            if pruned { continue }
            if let distance = rows.last?.last, distance <= 2 { matches.append((candidate, distance)) }
            prior = letters
            index += 1
        }
        return matches.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .prefix(max(0, limit)).map(\.0)
    }
}
