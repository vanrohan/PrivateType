import Foundation

public enum TouchAlignment {
    public struct Assignment: Equatable {
        public let sourceIndex: Int
        public let intended: String
    }
    public static func assignments(original: String, replacement: String) -> [Assignment] {
        guard TextRules.isWord(original), TextRules.isWord(replacement) else { return [] }
        let source = Array(original.lowercased()), target = Array(replacement.lowercased())
        var costs = Array(repeating: Array(repeating: 0, count: target.count + 1), count: source.count + 1)
        for i in 0...source.count { costs[i][0] = i }
        for j in 0...target.count { costs[0][j] = j }
        for i in 1...source.count {
            for j in 1...target.count {
                costs[i][j] = min(costs[i - 1][j] + 1, costs[i][j - 1] + 1,
                                  costs[i - 1][j - 1] + (source[i - 1] == target[j - 1] ? 0 : 1))
            }
        }
        guard costs[source.count][target.count] <= 2 else { return [] }
        var possible = Array(repeating: Set<String>(), count: source.count)
        var pending = [(source.count, target.count)], visited = Set<Int>()
        while let (i, j) = pending.popLast() {
            guard visited.insert(i * (target.count + 1) + j).inserted else { continue }
            if i > 0 && j > 0 && costs[i][j] == costs[i - 1][j - 1] + (source[i - 1] == target[j - 1] ? 0 : 1) {
                possible[i - 1].insert(String(target[j - 1]))
                pending.append((i - 1, j - 1))
            }
            if i > 0 && costs[i][j] == costs[i - 1][j] + 1 {
                possible[i - 1].insert("")
                pending.append((i - 1, j))
            }
            if j > 0 && costs[i][j] == costs[i][j - 1] + 1 { pending.append((i, j - 1)) }
        }
        if source.count == target.count {
            let changed = source.indices.filter { source[$0] != target[$0] }
            if changed.count == 2, changed[1] == changed[0] + 1,
               source[changed[0]] == target[changed[1]], source[changed[1]] == target[changed[0]] {
                for index in changed { possible[index] = [] }
            }
        }
        return possible.indices.compactMap { index in
            guard possible[index].count == 1, let key = possible[index].first, key.count == 1, key.first?.isLetter == true else { return nil }
            return Assignment(sourceIndex: index, intended: key)
        }
    }
}
