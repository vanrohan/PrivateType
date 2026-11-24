import Foundation
import CoreML
import Accelerate
import ExecuTorch

enum NeuralPredictionError: Error { case missingResource, invalidModel }

protocol NeuralWordModel: AnyObject {
    var name: String { get }
    func words(context: String, prefix: String, candidates: [String]) throws -> [String]
}

extension NeuralWordModel {
    func words(context: String, prefix: String) throws -> [String] {
        try words(context: context, prefix: prefix, candidates: [])
    }
}

final class EnglishNeuralModel: NeuralWordModel {
    let name = "FUTO"
    private let module: Module
    private let vocabulary: [String]
    private let lookup: [String: Int]
    private let lowerLookup: [String: Int]
    private let embeddings: [Float]
    private let biases: [Float]
    private var lastContext: String?
    private var lastScores: [Float] = []

    init(bundle: Bundle) throws {
        guard let path = bundle.path(forResource: "English", ofType: "pte"),
              let vocabURL = bundle.url(forResource: "EnglishVocabulary", withExtension: "txt") else {
            throw NeuralPredictionError.missingResource
        }
        module = Module(filePath: path, loadMode: .mmap)
        try module.load("get_embeddings")
        let values: [Value] = try module.execute("get_embeddings", [])
        guard values.count == 4, let matrix: Tensor<Float> = values[0].tensor(),
              let bias: Tensor<Float> = values[1].tensor() else { throw NeuralPredictionError.invalidModel }
        embeddings = matrix.scalars()
        biases = bias.scalars()
        guard embeddings.count == 32768 * 16, biases.count == 32768 else { throw NeuralPredictionError.invalidModel }
        vocabulary = ["<OOV>"] + (try String(contentsOf: vocabURL, encoding: .utf8)).components(separatedBy: .newlines)
        var lookup: [String: Int] = [:], lowerLookup: [String: Int] = [:]
        for (index, word) in vocabulary.prefix(32768).enumerated() where index > 0 {
            lookup[word] = index
            if lowerLookup[word.lowercased()] == nil { lowerLookup[word.lowercased()] = index }
        }
        self.lookup = lookup
        self.lowerLookup = lowerLookup
        try module.load("forward")
    }

    func words(context: String, prefix: String, candidates: [String] = []) throws -> [String] {
        let words = context.split(whereSeparator: { $0.isWhitespace }).suffix(16).map(String.init)
        let key = words.joined(separator: " ")
        if key != lastContext {
            var ids = [Int64](repeating: 0, count: 16)
            var hashes = [Int64](repeating: 0, count: 32)
            for (index, word) in words.enumerated() {
                if let id = lookup[word] ?? lowerLookup[word.lowercased()] { ids[index] = Int64(id) }
                else {
                    ids[index] = 32768
                    let buckets = FutoHash.buckets(word)
                    hashes[index * 2] = buckets[0]
                    hashes[index * 2 + 1] = buckets[1]
                }
            }
            let outputs: [Value] = try module.forward([
                Tensor<Int64>(ids, shape: [1, 16]), Tensor<Int64>(hashes, shape: [1, 16, 2])
            ])
            guard let tensor: Tensor<Float> = outputs.first?.tensor() else { throw NeuralPredictionError.invalidModel }
            let output = tensor.scalars()
            guard output.count == 256 else { throw NeuralPredictionError.invalidModel }
            let position = max(0, words.count - 1)
            let vector = Array(output[(position * 16)..<(position * 16 + 16)])
            var scores = biases
            cblas_sgemv(CblasRowMajor, CblasNoTrans, 32768, 16, 1, embeddings, 16, vector, 1, 1, &scores, 1)
            lastScores = scores
            lastContext = key
        }
        return rankedWords(scores: lastScores, words: vocabulary, prefix: prefix, candidates: candidates)
    }
}

final class GermanNeuralModel: NeuralWordModel {
    let name = "German BabyLM"
    private let model: MLModel
    private let tokenizer: BytePairTokenizer
    private var lastIDs: [Int] = []
    private var lastScores: [Float] = []
    private let words: [String]

    init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "German", withExtension: "mlmodelc"),
              let tokenizerURL = bundle.url(forResource: "GermanTokenizer", withExtension: "json") else {
            throw NeuralPredictionError.missingResource
        }
        tokenizer = try BytePairTokenizer(data: Data(contentsOf: tokenizerURL))
        words = tokenizer.tokenWords.map { $0 ?? "" }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: url, configuration: config)
    }

    private func infer(_ ids: [Int]) throws -> [Float] {
        let input = try MLMultiArray(shape: [1, 32], dataType: .int32)
        for index in 0..<32 { input[index] = NSNumber(value: index < ids.count ? ids[index] : 0) }
        let position = try MLMultiArray(shape: [1], dataType: .int32)
        position[0] = NSNumber(value: ids.count - 1)
        let features = try MLDictionaryFeatureProvider(dictionary: ["input_ids": input, "position": position])
        let result = try model.prediction(from: features)
        guard let scores = result.featureValue(for: "logits")?.multiArrayValue,
              scores.count == words.count else { throw NeuralPredictionError.invalidModel }
        return (0..<scores.count).map { scores[$0].floatValue }
    }

    func words(context: String, prefix: String, candidates: [String] = []) throws -> [String] {
        var ids = Array(tokenizer.encode(context.trimmingCharacters(in: .whitespacesAndNewlines)).suffix(32))
        if ids.isEmpty { ids = [0] }
        if ids != lastIDs {
            lastScores = try infer(ids)
            lastIDs = ids
        }
        let direct = rankedWords(scores: lastScores, words: words, prefix: prefix, candidates: candidates)
        guard !prefix.isEmpty else { return direct }
        var extra: [(String, [Int])] = []
        for word in candidates.prefix(32) where TextRules.isWord(word) &&
            (word.lowercased().hasPrefix(prefix.lowercased()) || TextRules.isSuggestionCorrection(word: prefix, candidate: word)) {
            let tokens = tokenizer.encode(" " + word)
            if tokens.count > 1 && tokens.count <= 5 { extra.append((word, tokens)) }
        }
        guard !extra.isEmpty else { return direct }
        extra.sort { lastScores[$0.1[0]] > lastScores[$1.1[0]] }
        func normalized(_ values: [Float]) -> [Float] {
            let maximum = values.max() ?? 0
            let denominator = maximum + log(values.reduce(Float(0)) { $0 + exp($1 - maximum) })
            return values.map { $0 - denominator }
        }
        let base = normalized(lastScores)
        var ranked = direct.compactMap { word -> (String, Float)? in
            guard let id = tokenizer.encode(" " + word).first else { return nil }
            return (word, base[id])
        }
        var cache: [[Int]: [Float]] = [:]
        var remainingCalls = 6
        for (word, tokens) in extra.prefix(4) {
            var score = base[tokens[0]]
            var complete = true
            for index in 1..<tokens.count {
                let input = Array((ids + tokens.prefix(index)).suffix(32))
                if cache[input] == nil {
                    if remainingCalls == 0 { complete = false; break }
                    cache[input] = normalized(try infer(input))
                    remainingCalls -= 1
                }
                score += cache[input]![tokens[index]]
            }
            if complete { ranked.append((word, score)) }
        }
        ranked.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        var seen = Set<String>()
        return ranked.compactMap { seen.insert($0.0.lowercased()).inserted ? $0.0 : nil }
    }
}

private func rankedWords(scores: [Float], words: [String], prefix: String, candidates: [String] = []) -> [String] {
    let prefix = prefix.lowercased()
    let corrections = Set(candidates.prefix(32).filter {
        TextRules.isSuggestionCorrection(word: prefix, candidate: $0)
    }.map { $0.lowercased() })
    var best: [(String, Float)] = []
    var repairs: [(String, Float)] = []
    var seen = Set<String>()
    for index in 0..<min(scores.count, words.count) {
        let word = words[index]
        let normalized = word.lowercased()
        guard scores[index].isFinite, TextRules.isWord(word) else { continue }
        if corrections.contains(normalized) { repairs.append((word, scores[index])) }
        guard normalized.hasPrefix(prefix) else { continue }
        if best.count == 32 && scores[index] <= best.last!.1 { continue }
        best.append((word, scores[index]))
        best.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        if best.count > 32 { best.removeLast() }
    }
    best += repairs
    best.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    return best.compactMap { word, _ in seen.insert(word.lowercased()).inserted ? word : nil }
}
