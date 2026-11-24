import Foundation

public struct TouchOffset: Codable, Equatable {
    public var x: Double = 0
    public var y: Double = 0
    public var count: Int = 0
    public var varianceX: Double = 0
    public var varianceY: Double = 0
    public var covariance: Double = 0
    public var confusions: [String: Int] = [:]
    public var histogram: [Int] = Array(repeating: 0, count: 25)

    public init() {}
    private enum CodingKeys: String, CodingKey { case x, y, count, varianceX, varianceY, covariance, confusions, histogram }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        count = max(0, min(10_000, try values.decode(Int.self, forKey: .count)))
        varianceX = try values.decodeIfPresent(Double.self, forKey: .varianceX) ?? 0
        varianceY = try values.decodeIfPresent(Double.self, forKey: .varianceY) ?? 0
        covariance = try values.decodeIfPresent(Double.self, forKey: .covariance) ?? 0
        confusions = try values.decodeIfPresent([String: Int].self, forKey: .confusions) ?? [:]
        histogram = try values.decodeIfPresent([Int].self, forKey: .histogram) ?? Array(repeating: 0, count: 25)
        guard [x, y, varianceX, varianceY, covariance].allSatisfy(\.isFinite), abs(x) <= 1.5, abs(y) <= 1,
              varianceX >= 0, varianceX <= 2.25, varianceY >= 0, varianceY <= 1,
              abs(covariance) <= 1.5, histogram.count == 25, histogram.allSatisfy({ (0...10_000).contains($0) }),
              confusions.count <= 40, confusions.allSatisfy({ $0.key.count == 1 && (0...10_000).contains($0.value) }) else {
            throw DecodingError.dataCorruptedError(forKey: .x, in: values, debugDescription: "Invalid touch statistics")
        }
    }
}

public struct TouchProfile: Codable, Hashable {
    public let layout: KeyboardLanguage
    public let landscape: Bool
    public let width: Int
    public let geometry: String
    public init(layout: KeyboardLanguage, landscape: Bool, width: Double, geometry: String = "") {
        self.layout = layout
        self.landscape = landscape
        self.width = max(20, Int((width / 20).rounded()) * 20)
        self.geometry = geometry
    }
    public var identifier: String { layout.rawValue + (landscape ? ".landscape." : ".portrait.") + String(width) + geometry }
}

public struct TouchValidation: Codable, Equatable {
    public var samples = 0
    public var baselineCorrect = 0
    public var activeCorrect = 0
    public var candidateCorrect = 0
    public init() {}
}

public struct TouchModel: Codable, Equatable {
    public enum Variant { case baseline, active, candidate }
    public private(set) var offsets: [String: TouchOffset] = [:]
    public private(set) var observations = 0
    public private(set) var validation = TouchValidation()
    public private(set) var lastValidation: TouchValidation?
    public private(set) var promotions = 0
    public private(set) var rejections = 0
    public private(set) var rollbacks = 0
    public private(set) var suspended = false
    private var validationPhase = 0
    private var active: [String: TouchOffset]?
    private var candidate: [String: TouchOffset]?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case offsets, observations, validation, lastValidation, promotions, rejections, rollbacks, suspended, active, candidate, validationPhase
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        offsets = try values.decode([String: TouchOffset].self, forKey: .offsets)
        observations = try values.decodeIfPresent(Int.self, forKey: .observations) ?? 0
        validationPhase = try values.decodeIfPresent(Int.self, forKey: .validationPhase) ?? observations % 5
        validation = try values.decodeIfPresent(TouchValidation.self, forKey: .validation) ?? .init()
        lastValidation = try values.decodeIfPresent(TouchValidation.self, forKey: .lastValidation)
        promotions = try values.decodeIfPresent(Int.self, forKey: .promotions) ?? 0
        rejections = try values.decodeIfPresent(Int.self, forKey: .rejections) ?? 0
        rollbacks = try values.decodeIfPresent(Int.self, forKey: .rollbacks) ?? 0
        suspended = try values.decodeIfPresent(Bool.self, forKey: .suspended) ?? false
        active = try values.decodeIfPresent([String: TouchOffset].self, forKey: .active)
        candidate = try values.decodeIfPresent([String: TouchOffset].self, forKey: .candidate)
        for map in [offsets, active ?? [:], candidate ?? [:]] {
            guard map.count <= 40, map.keys.allSatisfy({ $0.count == 1 && $0.first?.isLetter == true }) else {
                throw DecodingError.dataCorruptedError(forKey: .offsets, in: values, debugDescription: "Invalid touch keys")
            }
        }
        guard (0...1_000_000).contains(observations), (0...4).contains(validationPhase), [promotions, rejections, rollbacks].allSatisfy({ (0...10_000).contains($0) }),
              [validation, lastValidation ?? .init()].allSatisfy({ entry in
                  (0...20).contains(entry.samples) && [entry.baselineCorrect, entry.activeCorrect, entry.candidateCorrect]
                      .allSatisfy { (0...entry.samples).contains($0) }
              }) else {
            throw DecodingError.dataCorruptedError(forKey: .validation, in: values, debugDescription: "Invalid touch validation")
        }
    }
    public var hasApprovedModel: Bool { active != nil }
    public var shouldValidateNext: Bool { candidate != nil && observations >= 20 && validationPhase == 4 }
    private mutating func advanceObservation() {
        observations = min(observations + 1, 1_000_000)
        validationPhase = (validationPhase + 1) % 5
    }
    public mutating func learn(key: String, x: Double, y: Double, observedKey: String? = nil) {
        guard key.count == 1, key.first?.isLetter == true, x.isFinite, y.isFinite,
              abs(x) <= 1.5, abs(y) <= 1 else { return }
        var offset = offsets[key] ?? .init()
        let weight = Double(min(offset.count, 199))
        let newX = (offset.x * weight + x) / (weight + 1)
        let newY = (offset.y * weight + y) / (weight + 1)
        offset.varianceX = max(0, (offset.varianceX * weight + (x - offset.x) * (x - newX)) / (weight + 1))
        offset.varianceY = max(0, (offset.varianceY * weight + (y - offset.y) * (y - newY)) / (weight + 1))
        offset.covariance = (offset.covariance * weight + (x - offset.x) * (y - newY)) / (weight + 1)
        offset.x = newX
        offset.y = newY
        offset.count = min(offset.count + 1, 10_000)
        let column = max(0, min(4, Int((x + 1.25) / 0.5)))
        let row = max(0, min(4, Int((y + 1.25) / 0.5)))
        offset.histogram[row * 5 + column] = min(offset.histogram[row * 5 + column] + 1, 10_000)
        if let observedKey, observedKey != key, observedKey.count == 1, observedKey.first?.isLetter == true {
            offset.confusions[observedKey] = min((offset.confusions[observedKey] ?? 0) + 1, 10_000)
        }
        offsets[key] = offset
        advanceObservation()
        if candidate == nil && observations >= 20 { candidate = offsets }
    }
    public mutating func validate(baselineCorrect: Bool, activeCorrect: Bool, candidateCorrect: Bool) {
        guard shouldValidateNext else { return }
        advanceObservation()
        validation.samples += 1
        validation.baselineCorrect += baselineCorrect ? 1 : 0
        validation.activeCorrect += activeCorrect ? 1 : 0
        validation.candidateCorrect += candidateCorrect ? 1 : 0
        guard validation.samples == 20 else { return }
        lastValidation = validation
        if validation.activeCorrect < validation.baselineCorrect {
            active = nil
            suspended = true
            rollbacks = min(rollbacks + 1, 10_000)
        }
        if validation.candidateCorrect > validation.baselineCorrect,
           validation.candidateCorrect >= validation.activeCorrect, validation.candidateCorrect >= 16 {
            active = candidate
            suspended = false
            promotions = min(promotions + 1, 10_000)
        } else { rejections = min(rejections + 1, 10_000) }
        candidate = offsets
        validation = .init()
    }
    public func offset(for key: String, variant: Variant = .active) -> TouchOffset {
        guard variant != .baseline else { return .init() }
        let stats = variant == .candidate ? candidate?[key] : active?[key]
        guard var offset = stats, offset.count >= 3 else { return .init() }
        let confidence = Double(offset.count) / Double(offset.count + 2)
        let larger = (variant == .candidate || active != nil) && offset.count >= 20
        let limit = larger ? 0.2 : 0.12
        offset.x = max(-limit, min(limit, offset.x * confidence))
        offset.y = max(-limit, min(limit, offset.y * confidence))
        return offset
    }
    public func score(key: String, x: Double, y: Double, variant: Variant = .active) -> Double {
        let offset = offset(for: key, variant: variant)
        let dx = x - offset.x, dy = y - offset.y
        let useSpread = offset.count >= 20 && (variant == .candidate || hasApprovedModel)
        let confidence = Double(offset.count) / Double(offset.count + 20)
        let vx = useSpread ? max(0.09, min(0.25, 0.16 * (1 - confidence) + offset.varianceX * confidence)) : 0.16
        let vy = useSpread ? max(0.09, min(0.25, 0.16 * (1 - confidence) + offset.varianceY * confidence)) : 0.16
        let covariance = useSpread ? max(-0.4 * sqrt(vx * vy), min(0.4 * sqrt(vx * vy), offset.covariance * confidence)) : 0
        let determinant = vx * vy - covariance * covariance
        return (vy * dx * dx + vx * dy * dy - 2 * covariance * dx * dy) / determinant + log(determinant)
    }
}
