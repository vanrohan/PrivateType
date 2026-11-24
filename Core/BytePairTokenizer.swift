import Foundation

public final class BytePairTokenizer {
    public let vocabulary: [String: Int]
    private let ranks: [String: Int]
    private let encoder: [UInt8: String]
    private let decoder: [Unicode.Scalar: UInt8]
    private let pattern: NSRegularExpression
    public let tokenWords: [String?]

    public init(data: Data) throws {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let model = root?["model"] as? [String: Any], model["type"] as? String == "BPE",
              let vocabulary = model["vocab"] as? [String: Int], root?["normalizer"] is NSNull,
              let merges = model["merges"] as? [[String]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.vocabulary = vocabulary
        var ranks: [String: Int] = [:]
        for (index, pair) in merges.enumerated() where pair.count == 2 { ranks[pair[0] + "\u{0000}" + pair[1]] = index }
        self.ranks = ranks
        var visible = Array(33...126) + Array(161...172) + Array(174...255)
        var scalars = visible
        var next = 256
        for byte in 0...255 where !visible.contains(byte) { visible.append(byte); scalars.append(next); next += 1 }
        var encoder: [UInt8: String] = [:], decoder: [Unicode.Scalar: UInt8] = [:]
        for (byte, scalar) in zip(visible, scalars) {
            let scalar = Unicode.Scalar(scalar)!
            encoder[UInt8(byte)] = String(scalar)
            decoder[scalar] = UInt8(byte)
        }
        self.encoder = encoder
        self.decoder = decoder
        pattern = try NSRegularExpression(pattern: "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+")
        var tokenWords = [String?](repeating: nil, count: (vocabulary.values.max() ?? 0) + 1)
        for (token, id) in vocabulary {
            let bytes = token.unicodeScalars.compactMap { decoder[$0] }
            guard bytes.count == token.unicodeScalars.count, let text = String(bytes: bytes, encoding: .utf8),
                  text.first == " ", TextRules.isWord(String(text.dropFirst())) else { continue }
            tokenWords[id] = String(text.dropFirst())
        }
        self.tokenWords = tokenWords
    }

    public func encode(_ text: String) -> [Int] {
        let nsText = text as NSString
        var result: [Int] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            var parts = nsText.substring(with: match.range).utf8.map { encoder[$0]! }
            while parts.count > 1 {
                var best: (Int, Int)?
                for index in 0..<(parts.count - 1) {
                    if let rank = ranks[parts[index] + "\u{0000}" + parts[index + 1]], rank < (best?.1 ?? .max) {
                        best = (index, rank)
                    }
                }
                guard let best else { break }
                let left = parts[best.0], right = parts[best.0 + 1]
                var merged: [String] = []
                var index = 0
                while index < parts.count {
                    if index + 1 < parts.count && parts[index] == left && parts[index + 1] == right {
                        merged.append(left + right)
                        index += 2
                    } else { merged.append(parts[index]); index += 1 }
                }
                parts = merged
            }
            result += parts.compactMap { vocabulary[$0] }
        }
        return result
    }
}
