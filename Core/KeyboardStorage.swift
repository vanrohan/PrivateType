import Foundation

final class KeyboardStorage {
    private let defaults: UserDefaults
    var privateTyping = false
    var usesPersonalization: Bool { learning && !privateTyping }
    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if CommandLine.arguments.contains("--ui-testing") {
            self.defaults = UserDefaults(suiteName: "com.sonnesolutions.simplekeyboard.uitesting")!
        } else {
            self.defaults = .standard
        }
    }
    var language: KeyboardLanguage {
        get { KeyboardLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .english }
        set { defaults.set(newValue.rawValue, forKey: "language") }
    }
    var learning: Bool {
        get { defaults.object(forKey: "learning") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "learning") }
    }
    var autocorrection: Bool {
        get { defaults.object(forKey: "autocorrection") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autocorrection") }
    }
    var neuralPrediction: Bool {
        get { defaults.object(forKey: "neuralPrediction") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "neuralPrediction") }
    }
    var keyboardSize: KeyboardSize {
        get { KeyboardSize(rawValue: defaults.string(forKey: "keyboardSize") ?? "") ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "keyboardSize") }
    }
    var keyboardHand: KeyboardHand {
        get { KeyboardHand(rawValue: defaults.string(forKey: "keyboardHand") ?? "") ?? .full }
        set { defaults.set(newValue.rawValue, forKey: "keyboardHand") }
    }
    var numberRow: Bool {
        get { defaults.bool(forKey: "numberRow") }
        set { defaults.set(newValue, forKey: "numberRow") }
    }
    var largerKeyLabels: Bool {
        get { defaults.object(forKey: "largerKeyLabels") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "largerKeyLabels") }
    }
    var highContrast: Bool {
        get { defaults.object(forKey: "highContrast") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "highContrast") }
    }
    var cursorSpeed: CursorSpeed {
        get { CursorSpeed(rawValue: defaults.string(forKey: "cursorSpeed") ?? "") ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "cursorSpeed") }
    }
    var preferredLanguage: PreferredLanguage {
        get { PreferredLanguage(rawValue: defaults.string(forKey: "preferredLanguage") ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: "preferredLanguage") }
    }
    var protectedWords: Set<String> {
        Set((defaults.stringArray(forKey: "protectedWords") ?? []).prefix(512).filter(TextRules.isWord).map { $0.lowercased() })
    }
    func setProtected(_ word: String, enabled: Bool) {
        guard TextRules.isWord(word) else { return }
        var words = protectedWords
        let word = word.lowercased()
        if enabled {
            guard words.count < 512 || words.contains(word) else { return }
            words.insert(word)
        } else { words.remove(word) }
        defaults.set(words.sorted(), forKey: "protectedWords")
    }
    func forgetWord(_ word: String) {
        for key in ["words.multilingual"] + KeyboardLanguage.allCases.map({ "words." + $0.rawValue }) {
            guard let data = defaults.data(forKey: key), data.count < 200_000,
                  var memory = try? JSONDecoder().decode(LearningMemory.self, from: data) else { continue }
            memory.forget(word)
            defaults.set(try? JSONEncoder().encode(memory), forKey: key)
        }
    }
    var emojiUsage: EmojiUsage {
        get {
            guard !privateTyping, let data = defaults.data(forKey: "emoji.usage"), data.count <= 100_000,
                  let usage = try? JSONDecoder().decode(EmojiUsage.self, from: data) else { return .init() }
            return usage
        }
        set {
            guard !privateTyping else { return }
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "emoji.usage")
        }
    }
    func recordEmoji(_ emoji: String, at date: Date = Date()) {
        var usage = emojiUsage
        usage.record(emoji, at: date)
        emojiUsage = usage
    }
    func clearEmojiUsage() { defaults.removeObject(forKey: "emoji.usage") }

    func memory(for language: KeyboardLanguage) -> LearningMemory {
        guard usesPersonalization, let data = defaults.data(forKey: "words." + language.rawValue),
              data.count < 200_000,
              let memory = try? JSONDecoder().decode(LearningMemory.self, from: data) else { return .init() }
        return memory
    }
    var multilingualMemory: LearningMemory {
        guard usesPersonalization else { return .init() }
        if let data = defaults.data(forKey: "words.multilingual"), data.count < 200_000,
           let memory = try? JSONDecoder().decode(LearningMemory.self, from: data) { return memory }
        return KeyboardLanguage.allCases.reduce(LearningMemory()) { $0.merging(memory(for: $1)) }
    }
    func saveMultilingual(memory: LearningMemory, touches: TouchModel, layout: KeyboardLanguage) {
        guard usesPersonalization else { return }
        defaults.set(try? JSONEncoder().encode(memory), forKey: "words.multilingual")
        defaults.set(try? JSONEncoder().encode(touches), forKey: "touches." + layout.rawValue)
    }
    func saveWords(_ memory: LearningMemory) {
        guard usesPersonalization else { return }
        defaults.set(try? JSONEncoder().encode(memory), forKey: "words.multilingual")
    }
    func touches(profile: TouchProfile) -> TouchModel {
        guard usesPersonalization else { return .init() }
        let key = "touches.profile." + profile.identifier
        if let data = defaults.data(forKey: key), data.count < 500_000,
           let model = try? JSONDecoder().decode(TouchModel.self, from: data) { return model }
        let migration = "touches.migrated." + profile.layout.rawValue
        if !profile.landscape, profile.geometry.isEmpty, !defaults.bool(forKey: migration),
           defaults.data(forKey: "touches." + profile.layout.rawValue) != nil {
            let legacy = touches(for: profile.layout)
            saveTouches(legacy, profile: profile)
            defaults.set(true, forKey: migration)
            return legacy
        }
        return .init()
    }
    func saveTouches(_ model: TouchModel, profile: TouchProfile) {
        guard usesPersonalization else { return }
        let prefix = "touches.profile."
        var order = defaults.stringArray(forKey: prefix + "order") ?? []
        order.removeAll { $0 == profile.identifier }
        order.append(profile.identifier)
        while order.count > 32 { defaults.removeObject(forKey: prefix + order.removeFirst()) }
        defaults.set(order, forKey: prefix + "order")
        defaults.set(try? JSONEncoder().encode(model), forKey: prefix + profile.identifier)
    }
    func touches(for language: KeyboardLanguage) -> TouchModel {
        guard usesPersonalization, let data = defaults.data(forKey: "touches." + language.rawValue), data.count < 500_000,
              let model = try? JSONDecoder().decode(TouchModel.self, from: data) else { return .init() }
        return model
    }
    func save(memory: LearningMemory, touches: TouchModel, language: KeyboardLanguage) {
        guard usesPersonalization else { return }
        defaults.set(try? JSONEncoder().encode(memory), forKey: "words." + language.rawValue)
        defaults.set(try? JSONEncoder().encode(touches), forKey: "touches." + language.rawValue)
    }
    func clear() {
        defaults.removeObject(forKey: "protectedWords")
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("touches.profile.") || key.hasPrefix("touches.migrated.") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "words.multilingual")
        for language in KeyboardLanguage.allCases {
            defaults.removeObject(forKey: "words." + language.rawValue)
            defaults.removeObject(forKey: "touches." + language.rawValue)
        }
    }
}
