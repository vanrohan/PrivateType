import Foundation

public enum AlternateCharacters {
    public static func options(for key: String, uppercase: Bool = false) -> [String] {
        let variants: [String: String] = [
            "a": "\u{00e0}\u{00e1}\u{00e2}\u{00e4}\u{00e6}\u{00e3}\u{00e5}\u{0101}",
            "e": "\u{00e8}\u{00e9}\u{00ea}\u{00eb}\u{0113}\u{0117}\u{0119}",
            "i": "\u{00ec}\u{00ed}\u{00ee}\u{00ef}\u{012b}\u{0131}",
            "o": "\u{00f2}\u{00f3}\u{00f4}\u{00f6}\u{0153}\u{00f5}\u{00f8}\u{014d}",
            "u": "\u{00f9}\u{00fa}\u{00fb}\u{00fc}\u{016b}",
            "c": "\u{00e7}\u{0107}\u{010d}", "n": "\u{00f1}\u{0144}",
            "s": "\u{00df}\u{015b}\u{0161}", "y": "\u{00ff}\u{00fd}",
            "z": "\u{017e}\u{017a}\u{017c}", "l": "\u{0142}",
            ",": ".;:!?\u{201a}\u{201e}", ".": ",\u{2026}\u{00b7}\u{2022}?!",
            "-": "\u{2013}\u{2014}_", "'": "\u{2018}\u{2019}\u{0060}",
            "\"": "\u{201c}\u{201d}\u{00ab}\u{00bb}", "\u{20ac}": "$\u{00a3}\u{00a5}\u{00a2}"
        ]
        let currencies = ["\u{20ac}", "$", "\u{00a3}", "\u{00a5}", "\u{00a2}"]
        if currencies.contains(key) { return currencies.filter { $0 != key } }
        let key = key.lowercased()
        let sourceKey = ["\u{00e4}": "a", "\u{00f6}": "o", "\u{00fc}": "u"][key] ?? key
        if key == "\u{00df}" { return [uppercase ? "\u{00df}" : "\u{1e9e}"] }
        var options = (variants[sourceKey] ?? "").map(String.init).filter { $0 != key }.map { cased($0, uppercase: uppercase) }
        if key == "s" {
            options.removeAll { $0 == "\u{00df}" || $0 == "\u{1e9e}" }
            options.insert(contentsOf: ["\u{00df}", "\u{1e9e}"], at: 0)
        }
        if key == "i" && uppercase {
            options.removeAll { $0 == "I" }
            options.append(contentsOf: ["\u{0130}", "\u{0131}"])
        }
        return options
    }

    public static func cased(_ symbol: String, uppercase: Bool) -> String {
        guard uppercase else { return symbol }
        // Letter keys use the single-character capital sharp S.
        if symbol == "\u{00df}" { return "\u{1e9e}" }
        let upper = symbol.uppercased().precomposedStringWithCanonicalMapping
        return symbol.count == 1 && upper.count != 1 ? symbol : upper
    }
}
