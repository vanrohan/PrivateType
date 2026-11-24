import Foundation
import os

enum KeyboardPerformance {
    static let signposter = OSSignposter(subsystem: "com.sonnesolutions.simplekeyboard", category: "Performance")
}

final class NeuralPredictionService {
    struct Result {
        let words: [String]
        let engine: String
    }
    private let queue = DispatchQueue(label: "SimpleKeyboard.prediction", qos: .userInitiated)
    private let bundle: Bundle
    private let hasGermanModel: Bool
    private let factory: (KeyboardLanguage, Bundle) throws -> NeuralWordModel
    private var pending: DispatchWorkItem?
    private var generation = 0
    // The worker queue owns these values.
    private var model: NeuralWordModel?
    private var loadedLanguage: KeyboardLanguage?
    private var failedLanguage: KeyboardLanguage?

    init(bundle: Bundle = .main, factory: @escaping (KeyboardLanguage, Bundle) throws -> NeuralWordModel = { language, bundle in
        if language == .english { return try EnglishNeuralModel(bundle: bundle) }
        return try GermanNeuralModel(bundle: bundle)
    }) {
        self.bundle = bundle
        self.factory = factory
        self.hasGermanModel = bundle.url(forResource: "German", withExtension: "mlmodelc") != nil
            && bundle.url(forResource: "GermanTokenizer", withExtension: "json") != nil
    }

    func supports(_ language: KeyboardLanguage) -> Bool {
        language == .english || hasGermanModel
    }

    func request(context: String, language: KeyboardLanguage, candidates: [String] = [], completion: @escaping (Result) -> Void) {
        pending?.cancel()
        generation += 1
        let requestID = generation
        let context = String(context.suffix(512))
        let token = TextRules.suggestionToken(before: context) ?? TextRules.token(before: context)
        let previous = String(context.dropLast(token.count).map { character -> Character in
            if character.isLetter || character.isNumber || character.isWhitespace || "'\u{2019}.!?".contains(character) {
                return character
            }
            return " "
        })
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let interval = KeyboardPerformance.signposter.beginInterval("Neural inference", id: KeyboardPerformance.signposter.makeSignpostID())
            defer { KeyboardPerformance.signposter.endInterval("Neural inference", interval) }
            let result: Result = autoreleasepool {
                do {
                    if self.loadedLanguage != language {
                        self.model = nil
                        self.loadedLanguage = nil
                    }
                    if self.failedLanguage == language { throw NeuralPredictionError.invalidModel }
                    if self.model == nil {
                        self.model = try self.factory(language, self.bundle)
                        self.loadedLanguage = language
                    }
                    guard let model = self.model else { throw NeuralPredictionError.invalidModel }
                    return Result(words: try model.words(context: previous, prefix: token, candidates: candidates), engine: model.name)
                } catch {
                    self.model = nil
                    self.loadedLanguage = nil
                    self.failedLanguage = language
                    return Result(words: [], engine: "Basic predictions")
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard self?.generation == requestID else { return }
                completion(result)
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.045, execute: work)
    }

    func clear() {
        generation += 1
        pending?.cancel()
        pending = nil
        queue.async { [weak self] in
            self?.model = nil
            self?.loadedLanguage = nil
            self?.failedLanguage = nil
        }
    }
}
