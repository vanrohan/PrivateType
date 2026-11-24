import Foundation

public struct EmojiUsage: Codable, Equatable, Sendable {
    private struct Use: Codable, Equatable, Sendable {
        var count: Int
        var lastUsed: TimeInterval
    }
    private var uses: [String: Use] = [:]
    public init() {}

    public var ranked: [EmojiEntry] {
        let valid = uses.filter { EmojiCatalog.entry(for: $0.key) != nil && $0.value.count > 0 && $0.value.lastUsed.isFinite }
        return valid.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.value.lastUsed != $1.value.lastUsed { return $0.value.lastUsed > $1.value.lastUsed }
            return $0.key < $1.key
        }.prefix(64).compactMap { EmojiCatalog.entry(for: $0.key) }
    }

    public mutating func record(_ emoji: String, at date: Date = Date()) {
        guard EmojiCatalog.entry(for: emoji) != nil, date.timeIntervalSince1970.isFinite else { return }
        let count = min(999, max(0, uses[emoji]?.count ?? 0)) + 1
        uses[emoji] = Use(count: count, lastUsed: date.timeIntervalSince1970)
        let keep = Set(ranked.map(\.text))
        uses = uses.filter { keep.contains($0.key) }
    }
}
