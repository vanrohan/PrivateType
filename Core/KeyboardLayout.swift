import Foundation

public enum KeyboardSize: String, CaseIterable, Codable {
    case compact, standard, tall
}

public enum KeyboardHand: String, CaseIterable, Codable {
    case full, left, right
}

public enum CursorSpeed: String, CaseIterable, Codable {
    case slow, standard, fast
    public var pointsPerCharacter: Double {
        switch self {
        case .slow: return 18
        case .standard: return 12
        case .fast: return 8
        }
    }
}

public enum KeyboardLayout {
    public static let suggestionHeight: Double = 52
    public static func rowHeight(compact: Bool, size: KeyboardSize = .standard) -> Double {
        let base: Double = compact ? 36 : 48
        switch size {
        case .compact: return base - 4
        case .standard: return base
        case .tall: return base + (compact ? 4 : 8)
        }
    }
    public static func height(compact: Bool, emoji: Bool = false, size: KeyboardSize = .standard,
                              numberRow: Bool = false) -> Double {
        suggestionHeight + Double(numberRow ? 5 : 4) * rowHeight(compact: compact, size: size) + (emoji ? 44 : 0)
    }
    public static func typingWidth(available: Double, hand: KeyboardHand) -> Double {
        hand == .full ? available : min(available, max(280, min(340, available * 0.85)))
    }
}
