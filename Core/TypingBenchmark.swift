import Foundation

struct BenchmarkSample: Equatable {
    let id: String
    let text: String
    let initialText: String
}

enum BenchmarkTask: String, Codable, CaseIterable {
    case english = "copy.en.v1", afrikaans = "copy.af.v1", german = "copy.de.v1"
    case mixed = "copy.mixed.v1", repair = "repair.v1"
    case punctuation = "copy.punctuation.v1", numbers = "copy.numbers.v1"
    case symbols = "copy.symbols.v1", emoji = "copy.emoji.v1"

    var title: String {
        switch self {
        case .english: return "English"
        case .afrikaans: return "Afrikaans"
        case .german: return "German"
        case .mixed: return "Mixed languages"
        case .repair: return "Repair a typo"
        case .punctuation: return "Punctuation"
        case .numbers: return "Numbers"
        case .symbols: return "Symbols"
        case .emoji: return "Emoji"
        }
    }
    var samples: [BenchmarkSample] {
        let texts: [String]
        switch self {
        case .english:
            texts = ["Please send the meeting details tomorrow morning.",
                     "Can you send 3 files by 09:30? Thanks!",
                     "The total is 49.95 EUR, including tax."]
        case .afrikaans:
            texts = ["Baie dankie vir jou hulp. Ek sien jou by die huis.",
                     "Is die 3 pakkies gereed? Baie dankie!",
                     "Ons ontmoet om 14:30, by die huis."]
        case .german:
            texts = ["Vielen Dank. Wir treffen uns morgen am Bahnhof.",
                     "Sind die 3 Pakete bereit? Vielen Dank!",
                     "Der Preis ist 49,95 EUR. Bis morgen!"]
        case .mixed:
            texts = ["Hello, baie dankie. Vielen Dank for your help.",
                     "Ready om 09:30? Ja, vielen Dank!",
                     "Order 27 is gereed. Danke, see you soon!"]
        case .repair:
            texts = ["Please send the details.", "Is the meeting at 09:30?"]
        case .punctuation:
            texts = ["Ready? Yes! Bring notes, pens, and paper.",
                     "Please send the details. Is that clear?",
                     "Time: 09:30; place: the office."]
        case .numbers:
            texts = ["Order 27 costs 49.95 EUR. Pay by 18:30.",
                     "Call 0123 456 789 before 17:00.",
                     "We need 12 boxes, 3 bags, and 250 labels."]
        case .symbols:
            texts = ["Email team@example.com; use #42 + 5 = 47.",
                     "Open https://example.com/order?id=27.",
                     "Save 20% on [item_27] & pay 15 EUR."]
        case .emoji:
            texts = ["Thanks! \u{1F600} See you at 18:30.",
                     "Coffee at 09:00? \u{2615} Yes, please!",
                     "Great work! \u{1F44D} Order 27 is ready."]
        }
        return texts.enumerated().map { index, text in
            BenchmarkSample(id: index == 0 ? rawValue : rawValue + ".sample" + String(index + 1), text: text,
                initialText: self == .repair ? (index == 0 ? "Please send teh details." : "Is teh meeting at 09:30?") : "")
        }
    }
    var prompt: String { samples[0].text }
    var initialText: String { samples[0].initialText }
    var timingMethod: String { self == .repair ? "start_to_last_change" : "first_to_last_change" }
}

enum BenchmarkCondition: String, CaseIterable, Codable {
    case keyboard, layout, size, hand, numberRow, learning, prediction, correction, highContrast, largerLabels
    var title: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .layout: return "Layout"
        case .size: return "Size"
        case .hand: return "One-hand mode"
        case .numberRow: return "Number row"
        case .learning: return "Learning state"
        case .prediction: return "Predictions"
        case .correction: return "Correction"
        case .highContrast: return "High contrast"
        case .largerLabels: return "Larger labels"
        }
    }
    var options: [String] {
        let values: [String]
        switch self {
        case .keyboard: values = ["PrivateType", "Apple", "Gboard", "SwiftKey", "Other"]
        case .layout: values = ["EN", "DE", "Other"]
        case .size: values = ["Compact", "Standard", "Tall"]
        case .hand: values = ["Full", "Left", "Right"]
        case .learning: values = ["Off", "Private", "Empty profile", "Existing profile"]
        default: values = ["Off", "On"]
        }
        return ["Not recorded"] + values
    }
}

struct BenchmarkEnvironment: Codable, Equatable {
    var device: String
    var os: String
    var version: String
    var build: String
    var orientation: String
    var automated: Bool

    var isValid: Bool {
        [device, os, version, build, orientation].allSatisfy { !$0.isEmpty && $0.count <= 80 }
            && ["portrait", "landscape", "unknown"].contains(orientation)
    }
}

struct BenchmarkResult: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let protocolVersion: Int
    let task: BenchmarkTask
    let conditions: [String: String]
    let environment: BenchmarkEnvironment
    let timingMethod: String
    var sampleID: String? = nil
    let seconds: Double?
    let characters: Int
    let errors: Int

    var sample: BenchmarkSample? { task.samples.first { $0.id == (sampleID ?? task.rawValue) } }
    var sampleNumber: Int { (task.samples.firstIndex { $0.id == sample?.id } ?? 0) + 1 }

    var wordsPerMinute: Double? {
        guard task != .repair, let seconds, seconds > 0 else { return nil }
        return Double(characters) * 12 / seconds
    }
    var isValid: Bool {
        (protocolVersion == 1 || protocolVersion == 2 && sampleID != nil) && sample != nil
            && timingMethod == task.timingMethod && environment.isValid
            && date.timeIntervalSince1970.isFinite
            && (1...512).contains(characters) && (0...512).contains(errors)
            && (seconds == nil || (seconds!.isFinite && seconds! > 0 && seconds! <= 86_400))
            && (wordsPerMinute == nil || wordsPerMinute!.isFinite)
            && conditions.count == BenchmarkCondition.allCases.count
            && BenchmarkCondition.allCases.allSatisfy {
                guard let value = conditions[$0.rawValue] else { return false }
                return $0.options.contains(value) || ($0 == .keyboard && value == "SimpleKeys")
            }
    }
}

enum BenchmarkError: Error, LocalizedError {
    case clock, inputLimit, empty, interrupted, full, duplicate, invalid
    var errorDescription: String? {
        switch self {
        case .clock: return "The timer is invalid. Start again."
        case .inputLimit: return "The sample exceeds 512 characters. Start again."
        case .empty: return "Type a sample before Finish."
        case .interrupted: return "The test stops when the app loses focus. Start again."
        case .full: return "The 50-result limit is reached. Delete a result before saving."
        case .duplicate: return "This result is already saved."
        case .invalid: return "The result is invalid. Start again."
        }
    }
}

struct BenchmarkSession {
    private let task: BenchmarkTask
    let sample: BenchmarkSample
    private let conditions: [String: String]
    private let environment: BenchmarkEnvironment
    private let start: Double
    private var clock: Double
    private var firstChange: Double?
    private var lastChange: Double?
    private(set) var text: String
    private(set) var failure: BenchmarkError?

    init(task: BenchmarkTask, sampleID: String? = nil, conditions: [String: String], environment: BenchmarkEnvironment, now: Double) {
        self.task = task
        sample = task.samples.first { $0.id == (sampleID ?? task.rawValue) } ?? task.samples[0]
        self.conditions = conditions
        self.environment = environment
        start = now
        clock = now
        text = sample.initialText
        if sampleID != nil && sample.id != sampleID { failure = .invalid }
        if !now.isFinite || now < 0 { failure = .clock }
    }

    mutating func change(_ value: String, now: Double) {
        guard failure == nil else { return }
        guard now.isFinite, now >= clock else { invalidate(.clock); return }
        clock = now
        guard value.count <= 512 else { invalidate(.inputLimit); return }
        guard value != text else { return }
        if firstChange == nil { firstChange = now }
        lastChange = now
        text = value
    }

    mutating func invalidate(_ reason: BenchmarkError = .interrupted) {
        text = ""
        firstChange = nil
        lastChange = nil
        failure = reason
    }

    mutating func finish(date: Date = Date()) throws -> BenchmarkResult {
        defer { text = ""; firstChange = nil; lastChange = nil; failure = .interrupted }
        if let failure { throw failure }
        guard !text.isEmpty, let lastChange else { throw BenchmarkError.empty }
        let duration = lastChange - (task == .repair ? start : (firstChange ?? lastChange))
        let result = BenchmarkResult(id: UUID(), date: date, protocolVersion: 2, task: task,
            conditions: conditions, environment: environment, timingMethod: task.timingMethod, sampleID: sample.id,
            seconds: duration > 0 ? duration : nil, characters: text.count,
            errors: Self.distance(text, sample.text))
        guard result.isValid else { throw BenchmarkError.invalid }
        return result
    }

    static func distance(_ source: String, _ target: String) -> Int {
        let a = Array(source.precomposedStringWithCanonicalMapping)
        let b = Array(target.precomposedStringWithCanonicalMapping)
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                row[j + 1] = min(previous[j + 1] + 1, row[j] + 1, previous[j] + (character == b[j] ? 0 : 1))
            }
            previous = row
        }
        return previous[b.count]
    }
}

final class BenchmarkStore {
    static let key = "typingBenchmark.results.v1"
    private let defaults: UserDefaults
    private(set) var results: [BenchmarkResult] = []
    private(set) var loadFailed = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        guard data.count <= 131_072, let loaded = try? JSONDecoder().decode([BenchmarkResult].self, from: data),
              loaded.count <= 50, loaded.allSatisfy(\.isValid), Set(loaded.map(\.id)).count == loaded.count else {
            loadFailed = true
            return
        }
        results = loaded
    }

    func save(_ result: BenchmarkResult) throws {
        guard result.isValid else { throw BenchmarkError.invalid }
        guard !results.contains(where: { $0.id == result.id }) else { throw BenchmarkError.duplicate }
        guard results.count < 50 else { throw BenchmarkError.full }
        try persist(results + [result])
    }
    func delete(_ ids: Set<UUID>) throws { try persist(results.filter { !ids.contains($0.id) }) }
    func deleteAll() throws { try persist([]) }

    private func persist(_ values: [BenchmarkResult]) throws {
        let data = try JSONEncoder().encode(values)
        guard data.count <= 131_072 else { throw BenchmarkError.full }
        defaults.set(data, forKey: Self.key)
        results = values
        loadFailed = false
    }

    var csv: String {
        let header = ["id", "date", "protocol", "task", "timing", "seconds", "characters", "errors", "wpm",
            "device", "os", "version", "build", "orientation", "automated", "sample"] + BenchmarkCondition.allCases.map(\.rawValue)
        let formatter = ISO8601DateFormatter()
        let rows = results.map { result in
            [result.id.uuidString, formatter.string(from: result.date), String(result.protocolVersion), result.task.rawValue,
             result.timingMethod, result.seconds.map(String.init(describing:)) ?? "", String(result.characters),
             String(result.errors), result.wordsPerMinute.map(String.init(describing:)) ?? "",
             result.environment.device, result.environment.os, result.environment.version, result.environment.build,
             result.environment.orientation, String(result.environment.automated), result.sample?.id ?? ""]
                + BenchmarkCondition.allCases.map { result.conditions[$0.rawValue] ?? "Not recorded" }
        }
        return ([header] + rows).map { $0.map(Self.csvField).joined(separator: ",") }.joined(separator: "\r\n")
    }

    private static func csvField(_ value: String) -> String {
        let prefix = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = prefix.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
