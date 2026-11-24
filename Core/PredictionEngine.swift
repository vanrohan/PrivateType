import Foundation

public enum TypingLanguage: String, CaseIterable, Codable, Sendable {
    case english, afrikaans, german, spanish, french, italian, portuguese, dutch, swedish, danish, norwegian, finnish

    public var code: String {
        switch self {
        case .english: return "en"
        case .afrikaans: return "af"
        case .german: return "de"
        case .spanish: return "es"
        case .french: return "fr"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .dutch: return "nl"
        case .swedish: return "sv"
        case .danish: return "da"
        case .norwegian: return "nb"
        case .finnish: return "fi"
        }
    }

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    public var neuralLanguage: KeyboardLanguage? {
        switch self {
        case .english: return .english
        case .german: return .german
        default: return nil
        }
    }
}

public enum PreferredLanguage: String, CaseIterable, Codable {
    case automatic, english, afrikaans, german, spanish, french, italian, portuguese, dutch, swedish, danish, norwegian, finnish
    public var title: String { language?.title ?? "Auto" }
    public var language: TypingLanguage? { TypingLanguage(rawValue: rawValue) }
}

public enum LanguageContext {
    public static func resolve(_ context: String, preference: PreferredLanguage = .automatic,
                               memberships: (String) -> Set<TypingLanguage>) -> TypingLanguage {
        let complete = context.last?.isWhitespace == true ? context : String(context.dropLast((TextRules.suggestionToken(before: context) ?? TextRules.token(before: context)).count))
        let words = complete.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" }).suffix(6)
        var scores: [TypingLanguage: Int] = [:]
        var latestClear: TypingLanguage?
        for (index, token) in words.enumerated() {
            let matches = memberships(String(token))
            for language in matches { scores[language, default: 0] += index + 1 }
            if matches.count == 1 { latestClear = matches.first }
        }
        if let latestClear { return latestClear }
        let highest = scores.values.max() ?? 0
        let choices = TypingLanguage.allCases.filter { scores[$0, default: 0] == highest }
        if let preferred = preference.language, choices.contains(preferred) { return preferred }
        return choices.contains(.english) ? .english : choices.first ?? preference.language ?? .english
    }
}

public enum KeyboardLanguage: String, Codable, CaseIterable {
    case english = "en_US"
    case german = "de_DE"

    public var title: String { self == .english ? "English" : "Deutsch" }
    public var badge: String { self == .english ? "EN" : "DE" }
}

public struct LearningMemory: Codable, Equatable {
    public private(set) var words: [String: Int] = [:]
    public private(set) var pairs: [String: Int] = [:]

    public init() {}

    public mutating func forget(_ word: String) {
        let word = word.lowercased()
        words.removeValue(forKey: word)
        pairs = pairs.filter { !$0.key.split(separator: " ").contains(Substring(word)) }
    }

    public mutating func learn(word: String, previous: String?) {
        let word = word.lowercased()
        guard TextRules.isWord(word), word.count <= 24 else { return }
        words[word] = min((words[word] ?? 0) + 1, 1000)
        if let previous = previous?.lowercased(), TextRules.isWord(previous), previous.count <= 24 {
            let key = previous + " " + word
            pairs[key] = min((pairs[key] ?? 0) + 1, 1000)
        }
        words = bounded(words, limit: 256)
        pairs = bounded(pairs, limit: 512)
    }

    public func merging(_ other: LearningMemory) -> LearningMemory {
        var result = self
        for (word, count) in other.words {
            result.words[word] = min(1000, max(0, min(1000, result.words[word] ?? 0)) + max(0, min(1000, count)))
        }
        for (pair, count) in other.pairs {
            result.pairs[pair] = min(1000, max(0, min(1000, result.pairs[pair] ?? 0)) + max(0, min(1000, count)))
        }
        result.words = bounded(result.words, limit: 256)
        result.pairs = bounded(result.pairs, limit: 512)
        return result
    }

    private func bounded(_ values: [String: Int], limit: Int) -> [String: Int] {
        guard values.count > limit else { return values }
        let ranked = values.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return Dictionary(uniqueKeysWithValues: ranked.prefix(limit).map { ($0.key, $0.value) })
    }
}

public struct PredictionEngine {
    private let words: [String: Int]
    private let pairs: [String: Int]
    private let triples: [String: Int]
    private let forms: [String: String]
    private let language: KeyboardLanguage
    static let commonEnglishWords = Set(phrases.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() })
    private let seedLanguages: [String: Set<TypingLanguage>]
    private let contextualForms: [String: String]
    public var memory: LearningMemory

    public init(language: KeyboardLanguage = .english, memory: LearningMemory = .init(), multilingual: Bool = false) {
        self.memory = memory
        self.language = language
        var words: [String: Int] = [:], pairs: [String: Int] = [:]
        var triples: [String: Int] = [:]
        var forms: [String: String] = [:]
        let phrases = multilingual ? Self.phrases + "\n" + Self.germanPhrases + "\n" + Self.afrikaansPhrases + "\n" + WesternPhrases.corpora.map(\.1).joined(separator: "\n") :
            (language == .english ? Self.phrases : Self.germanPhrases)
        for line in phrases.split(separator: "\n") {
            let originals = line.split(separator: " ").map(String.init)
            for word in originals { forms[word.lowercased()] = word }
            let tokens = originals.map { $0.lowercased() }
            for (index, word) in tokens.enumerated() {
                words[word, default: 0] += 1
                if index > 0 { pairs[tokens[index - 1] + " " + word, default: 0] += 1 }
                if index > 1 { triples[tokens[index - 2] + " " + tokens[index - 1] + " " + word, default: 0] += 1 }
            }
        }
        self.words = words
        self.pairs = pairs
        self.triples = triples
        var seedLanguages: [String: Set<TypingLanguage>] = [:]
        var contextualForms: [String: String] = [:]
        for (language, corpus) in [(TypingLanguage.english, Self.phrases), (.german, Self.germanPhrases), (.afrikaans, Self.afrikaansPhrases)] + WesternPhrases.corpora {
            for word in corpus.split(whereSeparator: { $0.isWhitespace }) {
                seedLanguages[word.lowercased(), default: []].insert(language)
            }
            for line in corpus.split(separator: "\n") {
                let tokens = line.split(separator: " ").map(String.init)
                for index in tokens.indices where index > 0 {
                    for length in 1...min(2, index) {
                        let key = language.rawValue + " " + tokens[(index - length)...index].map { $0.lowercased() }.joined(separator: " ")
                        contextualForms[key] = tokens[index]
                    }
                }
            }
        }
        self.seedLanguages = seedLanguages
        self.contextualForms = contextualForms
        if language == .english { forms["i"] = "I" }
        self.forms = forms
    }

    public func suggestions(context: String, completions: [String] = [], corrections: [String] = [], neural: [String] = [],
                            lowercaseEnglishWords: Set<String> = [], properForms: [String: String] = [:],
                            capitalizationLanguage: KeyboardLanguage? = nil, sentenceStart: Bool? = nil,
                            writingLanguage: TypingLanguage? = nil, languageScores: [String: Int] = [:], limit: Int = 3) -> [String] {
        guard let token = TextRules.suggestionToken(before: context) else { return [] }
        let prefix = token.lowercased()
        let previousContext = String(context.dropLast(token.count))
        let sentence = previousContext.split(whereSeparator: { ".!?\n\r".contains($0) }).last.map(String.init) ?? ""
        let sentenceEnded = TextRules.beginsSentence(previousContext)
        let previousTwo = sentenceEnded ? [] : sentence.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" }).suffix(2).map(String.init)
        let previous = previousTwo.last?.lowercased()
        let triplePrefix = previousTwo.count == 2 && previousTwo.allSatisfy(TextRules.isWord) ?
            previousTwo.map { $0.lowercased() }.joined(separator: " ") + " " : ""
        var candidates = Set<String>()
        for word in words.keys where prefix.isEmpty || word.hasPrefix(prefix) {
            if prefix.isEmpty, let writingLanguage, seedLanguages[word]?.contains(writingLanguage) != true { continue }
            candidates.insert(word)
        }
        for word in memory.words.keys where prefix.isEmpty || word.hasPrefix(prefix) { candidates.insert(word) }
        candidates.formUnion(completions.map { $0.lowercased() }.filter { TextRules.isWord($0) })
        candidates.formUnion(corrections.filter {
            TextRules.isWord($0) || TextRules.isSplitCorrection(word: token, candidate: $0)
        }.map { $0.lowercased() })
        let closeCorrections = Set(corrections.filter { TextRules.isSuggestionCorrection(word: token, candidate: $0) }.map { $0.lowercased() })
        let crossLanguageRepair = writingLanguage.map { language in
            closeCorrections.contains { word in
                if languageScores[word] == 0 { return true }
                guard let languages = seedLanguages[word] else { return false }
                return !languages.contains(language)
            }
        } ?? false
        let neural = neural.filter {
            TextRules.isWord($0) && ($0.lowercased().hasPrefix(prefix) || closeCorrections.contains($0.lowercased()))
        }
        candidates.formUnion(neural.map { $0.lowercased() })
        if !prefix.isEmpty { candidates.insert(prefix) }
        // Keep existing word ranks independent from the new split candidates.
        let correctionRanks = Dictionary([corrections.filter { !$0.contains(" ") }, corrections.filter { $0.contains(" ") }]
            .flatMap { $0.enumerated().map { ($0.element.lowercased(), 100 - $0.offset) } }, uniquingKeysWith: max)
        let neuralRanks = Dictionary(neural.enumerated().map { ($0.element.lowercased(), max(0, 2000 - $0.offset * 50)) },
                                     uniquingKeysWith: max)
        let completionRanks = Dictionary(completions.enumerated().map { ($0.element.lowercased(), $0.offset) },
                                         uniquingKeysWith: min)
        func score(_ word: String) -> Int {
            let key = (previous ?? "") + " " + word
            var languageScore = max(languageScores[word] ?? 0,
                writingLanguage.map { seedLanguages[word]?.contains($0) == true ? 400 : 0 } ?? 0)
            if closeCorrections.contains(word) { languageScore /= 5 }
            var inputScore = 0
            if !prefix.isEmpty, !closeCorrections.isEmpty, word != prefix {
                if word.hasPrefix(prefix) {
                    inputScore = max(0, 480 - (word.count - prefix.count) * 60)
                } else if closeCorrections.contains(word) {
                    let plain = word.filter { $0 != "'" && $0 != "\u{2019}" }
                    inputScore = plain == prefix ? 1200 :
                        (TextRules.distance(prefix, word) == 1 ? 700 : 300) + (words[word] != nil ? 400 : 0)
                }
            }
            if prefix.isEmpty, !neural.isEmpty {
                let rank = neural.firstIndex(where: { $0.lowercased() == word })
                let modelScore = rank.map { 10_000 - $0 * 200 } ?? 0
                let learnedCount = memory.pairs[key] ?? 0
                let learnedScore = learnedCount >= 2 ? 10_000 + min(1000, learnedCount * 100) : learnedCount * 100
                return modelScore + min(150, (pairs[key] ?? 0) * 25 + (triples[triplePrefix + word] ?? 0) * 50) +
                    learnedScore + languageScore
            }
            return (words[word] ?? 0) + (pairs[key] ?? 0) * 50 + (triples[triplePrefix + word] ?? 0) * 300 +
                (memory.words[word] ?? 0) * 10 + (memory.pairs[key] ?? 0) * 100 +
                (correctionRanks[word] ?? 0) * 10 + (crossLanguageRepair && closeCorrections.contains(word) ? (neuralRanks[word] ?? 0) / 10 : neuralRanks[word] ?? 0) +
                (word == prefix ? 200 : 0) + languageScore + inputScore
        }
        let scores = Dictionary(uniqueKeysWithValues: candidates.map { ($0, score($0)) })
        var ranked = candidates.sorted {
            let left = scores[$0] ?? 0, right = scores[$1] ?? 0
            if left != right { return left > right }
            let leftRank = completionRanks[$0] ?? Int.max, rightRank = completionRanks[$1] ?? Int.max
            return leftRank == rightRank ? $0 < $1 : leftRank < rightRank
        }
        if !prefix.isEmpty {
            ranked.removeAll { $0 == prefix }
            // Keep both input paths. Give exact apostrophe repairs the first alternative slot.
            let completion = ranked.first(where: { $0.hasPrefix(prefix) })
            let apostropheRepair = ranked.first { word in
                closeCorrections.contains(word) && word.filter { $0 != "'" && $0 != "\u{2019}" } == prefix
            }
            let exactSplit = corrections.first { TextRules.isSplitCorrection(word: token, candidate: $0) &&
                $0.replacingOccurrences(of: " ", with: "").lowercased() == prefix }?.lowercased()
            let singleRepair = ranked.first { closeCorrections.contains($0) && !$0.contains(" ") && !$0.hasPrefix(prefix) }
            let splitRepair = corrections.first { TextRules.isSplitCorrection(word: token, candidate: $0) }?.lowercased()
            let preferredSplit = exactSplit.flatMap { phrase -> String? in
                // Keep a common whole-word repair ahead of an unsupported split.
                if let singleRepair, words[singleRepair] != nil, pairs[phrase] == nil { return nil }
                return phrase
            }
            let correction = apostropheRepair ?? preferredSplit ?? singleRepair ?? splitRepair
            var alternatives = ranked.filter { $0 == completion || $0 == correction }
            // Keep a repair that preserves all letters visible in a narrow row.
            if let boundaryRepair = apostropheRepair ?? preferredSplit ?? (singleRepair == nil ? splitRepair : nil) {
                alternatives.removeAll { $0 == boundaryRepair }
                alternatives.insert(boundaryRepair, at: 0)
            }
            ranked.removeAll { alternatives.contains($0) }
            ranked.insert(contentsOf: alternatives, at: 0)
            ranked.insert(prefix, at: 0)
        }
        let language = capitalizationLanguage ?? self.language
        var displayForms = forms
        for word in neural + completions + corrections { displayForms[word.lowercased()] = word }
        return ranked.prefix(max(0, min(limit, 8))).map { word in
            if word == prefix { return token }
            var display = displayForms[word] ?? word
            if writingLanguage.map({ $0 == .english }) ?? (language == .english) {
                if word == "i" || word.hasPrefix("i'") || word.hasPrefix("i\u{2019}") {
                    display = "I" + word.dropFirst()
                } else if Self.unambiguousEnglishCapitalWords.contains(word) {
                    display = word.prefix(1).uppercased() + word.dropFirst()
                } else if display.first?.isUppercase == true, let proper = properForms[word] {
                    display = proper
                } else if !Self.englishCapitalWords.contains(word),
                          !(display.count > 1 && display == display.uppercased()),
                          Self.commonEnglishWords.contains(word) || lowercaseEnglishWords.contains(word) {
                    display = word
                }
            }
            if let writingLanguage, writingLanguage != .english, word == "i" {
                display = word
                if writingLanguage == .danish {
                    let tripleKey = writingLanguage.rawValue + " " + triplePrefix + word
                    let pairKey = writingLanguage.rawValue + " " + (previous ?? "") + " " + word
                    display = contextualForms[tripleKey] ?? contextualForms[pairKey] ?? word
                }
            }
            if !token.isEmpty { return TextRules.matchCase(display, to: token) }
            return (sentenceStart ?? TextRules.beginsSentence(context)) ? display.prefix(1).uppercased() + display.dropFirst() : display
        }
    }

    private static let englishCapitalWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "english", "german"
    ]

    private static let unambiguousEnglishCapitalWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "april", "june", "july", "august", "september", "october", "november", "december",
        "english", "german"
    ]

    // This small seed model supplies common phrases. It is not a large language model.
    private static let phrases = """
    i am on my way
    i am on my way home
    i am going to the office
    i am going to be late
    i am looking forward to it
    i am looking forward to seeing you
    i am not sure
    i am sorry about that
    i am happy to help
    i will be there soon
    i will call you later
    i will let you know
    i will send you the details
    i will check and get back to you
    i would like to book a table
    i would like to know more
    i have a question about the project
    i have sent you an email
    i have been working on it
    i need to check the details
    i need to get some food
    i think that is a good idea
    i think we should try it
    i can do that tomorrow
    i can help you with that
    i want to make sure
    i want to go home
    i don't know what to do
    i don't think so
    i love you
    i miss you
    you are welcome
    you can call me anytime
    you can send it to me
    we can meet at the station
    we can talk about it later
    we should be able to do that
    we need to find a way
    we are going to the park
    it is a good idea
    it is nice to meet you
    it is not a problem
    it was great to see you
    it looks good to me
    it works for me
    that sounds good to me
    that sounds like a plan
    that would be great
    that is fine with me
    that is a good question
    this is exactly what i need
    this is the best way
    this should work well
    there is no need to worry
    there are a few things to discuss
    thank you for your help
    thank you for letting me know
    thank you so much
    thanks for the update
    thanks for your time
    thanks for getting back to me
    thanks i will check it
    please let me know
    please send me the details
    please give me a call
    please find the attached file
    please check your email
    can you send me the address
    can you give me a call
    can you help me with this
    can we meet tomorrow morning
    can we talk later today
    could you please check this
    could you let me know
    do you want to come over
    do you have time tomorrow
    do you know where it is
    do you need anything else
    did you get my message
    did you see the email
    what do you think about this
    what time do you want to meet
    what are you doing today
    what would you like to eat
    where are you right now
    where should we meet
    when will you be home
    when can we talk
    how are you doing
    how was your day
    how much does it cost
    how can i help you
    good morning how are you
    good afternoon everyone
    good evening see you tomorrow
    good night sleep well
    have a good day
    have a great weekend
    have a safe trip
    see you soon
    see you in a few minutes
    see you tomorrow morning
    talk to you later
    let me know when you arrive
    let me check the schedule
    let us know if you need help
    no problem at all
    no worries take your time
    yes that works for me
    yes please thank you
    not yet but soon
    sorry i am running late
    sorry for the delay
    happy birthday to you
    happy to hear that
    on my way now
    at the moment i am busy
    at the end of the day
    in the morning we can meet
    in a few minutes
    as soon as possible
    as far as i know
    for the first time
    looking forward to hearing from you
    the meeting is at ten
    the project is ready for review
    the next step is to test it
    the weather is nice today
    the train is running late
    the food was very good
    the report is ready
    the position is open
    the risk is too high
    the market is closed
    the payment is complete
    the order is ready
    my phone is almost out of battery
    my address is in the email
    your message is clear
    your order is on the way
    all the best for tomorrow
    a little bit more time
    a lot of work to do
    be right back
    just a moment please
    okay see you there
    maybe we can try again
    because i need more time
    if you have any questions please ask
    if that works for you
    and then we can go home
    but i am not sure yet
    so we can get started
    really looking forward to it
    always happy to help
    never mind it is fine
    after the meeting i will call
    before we start please check
    during the week i am busy
    about the same time tomorrow
    tomorrow afternoon would be great
    today is a good day
    tonight we can have dinner
    lunch at the usual place
    dinner with the family
    coffee in the morning
    hello how are you
    hi are you free today
    hey what is the plan
    well done that looks great
    work from home today
    back in the office tomorrow
    sent from my phone
    available for a quick call
    sounds good thanks
    sure i can do that
    absolutely thank you
    of course i will help
    happy new year
    merry christmas and happy new year
    best regards
    kind regards
    """

    private static let afrikaansPhrases = """
    goeie more hoe gaan dit
    goeiemore hoe gaan dit
    goeie dag hoe gaan dit
    baie dankie vir jou hulp
    dankie vir die boodskap
    ek is op pad huis toe
    ek sal jou later bel
    ek sien jou more
    ek het dit gekry
    ek weet nie
    ek is lief vir jou
    ons kan more praat
    dit klink goed
    dit is 'n goeie idee
    lekker slaap
    lekker dag vir jou
    geniet jou dag
    tot siens
    ja dit is reg
    nee dankie
    asseblief stuur die besonderhede
    hallo hoe gaan dit vandag
    wanneer kom jy huis toe
    hoe laat is dit
    """

    private static let germanPhrases = """
    ich bin auf dem Weg
    ich bin auf dem Weg nach Hause
    ich bin gleich da
    ich bin noch im Büro
    ich bin mir nicht sicher
    ich bin heute zu Hause
    ich habe eine Frage
    ich habe dir eine Nachricht geschickt
    ich habe es noch nicht gesehen
    ich habe keine Zeit
    ich habe heute Zeit
    ich werde mich darum kümmern
    ich werde dir Bescheid geben
    ich würde mich freuen
    ich würde gerne kommen
    ich kann dir helfen
    ich kann Morgen kommen
    ich kann dich später anrufen
    ich muss noch arbeiten
    ich muss kurz nachsehen
    ich möchte einen Tisch reservieren
    ich möchte mehr darüber wissen
    ich denke das ist eine gute Idee
    ich glaube das passt gut
    ich freue mich auf dich
    ich freue mich auf das Wochenende
    ich melde mich später
    ich rufe dich später an
    ich weiß es noch nicht
    ich weiß nicht genau
    ich brauche noch etwas Zeit
    ich komme etwas später
    ich liebe dich
    ich vermisse dich
    wir können uns Morgen treffen
    wir können später darüber sprechen
    wir sind gleich da
    wir sehen uns Morgen
    wir müssen noch einkaufen
    wir brauchen eine Lösung
    du kannst mich jederzeit anrufen
    du kannst mir eine Nachricht schicken
    du hast recht
    du bist herzlich willkommen
    das ist eine gute Idee
    das ist kein problem
    das ist sehr nett von dir
    das klingt gut
    das passt mir gut
    das sieht gut aus
    das freut mich sehr
    das können wir so machen
    es tut mir leid
    es gibt noch viel zu tun
    es geht mir gut
    es war schön dich zu sehen
    es ist alles in Ordnung
    vielen Dank für deine Hilfe
    vielen Dank für die Nachricht
    vielen Dank für die Rückmeldung
    danke für deine Zeit
    danke dir bis Morgen
    danke das ist sehr nett
    bitte gib mir Bescheid
    bitte schick mir die Adresse
    bitte ruf mich an
    bitte lass mich wissen
    kannst du mir helfen
    kannst du mich später anrufen
    kannst du mir die Unterlagen schicken
    können wir uns Morgen treffen
    können wir kurz telefonieren
    hast du heute Zeit
    hast du meine Nachricht bekommen
    hast du Lust auf einen Kaffee
    was machst du gerade
    was hältst du davon
    was möchtest du Essen
    wann bist du zu Hause
    wann treffen wir uns
    wann hast du Zeit
    wo bist du gerade
    wo wollen wir uns treffen
    wie geht es dir
    wie war dein Tag
    wie viel kostet das
    wie kann ich dir helfen
    guten Morgen wie geht es dir
    guten Abend zusammen
    gute Nacht schlaf gut
    einen schönen Tag noch
    schönes Wochenende bis Montag
    bis später mach es gut
    bis Morgen früh
    bis bald liebe Grüße
    liebe Grüße an die Familie
    mit freundlichen grüßen
    alles gute zum Geburtstag
    frohe Weihnachten und ein gutes neues Jahr
    kein problem bis dann
    kein Stress lass dir Zeit
    ja das passt gut
    ja gerne vielen Dank
    nein danke vielleicht später
    noch nicht aber bald
    leider kann ich nicht kommen
    entschuldigung für die Verspätung
    auf jeden Fall
    auf dem Weg zum Bahnhof
    in ein paar Minuten
    in der nächsten Woche
    am Wochenende habe ich Zeit
    am Montag bin ich im Büro
    nach dem Essen gehen wir spazieren
    vor dem Termin rufe ich an
    heute Abend können wir reden
    Morgen früh habe ich Zeit
    der Termin ist Morgen
    der Zug hat Verspätung
    die Unterlagen sind fertig
    die Bestellung ist unterwegs
    die Zahlung ist angekommen
    die Besprechung beginnt um zehn
    das Risiko ist zu hoch
    die Position ist offen
    der Markt ist geschlossen
    mein Handy ist fast leer
    meine Adresse steht in der Nachricht
    deine Nachricht ist angekommen
    zum Beispiel Morgen Nachmittag
    vielleicht können wir später reden
    natürlich helfe ich dir gerne
    gerne bis zum nächsten Mal
    hallo wie geht es dir
    hallo hast du kurz Zeit
    """
}


enum WesternPhrases {
    static let corpora: [(TypingLanguage, String)] = [
        (.spanish, """
        hola como estas
        muchas gracias por tu ayuda
        estoy en camino a casa
        te llamo mas tarde
        nos vemos ma\u{00f1}ana
        que tengas un buen d\u{00ed}a
        no hay problema
        por favor env\u{00ed}ame los detalles
        """),
        (.french, """
        bonjour comment allez vous
        merci beaucoup pour votre aide
        je suis en route vers la maison
        je vous appelle plus tard
        \u{00e0} demain
        bonne journ\u{00e9}e
        aucun probl\u{00e8}me
        pouvez vous envoyer les d\u{00e9}tails
        """),
        (.italian, """
        ciao come stai
        grazie per il tuo aiuto
        ci vediamo domani
        sono in viaggio verso casa
        ti chiamo pi\u{00f9} tardi
        buona giornata
        non ci sono problemi
        puoi mandarmi i dettagli
        """),
        (.portuguese, """
        muito obrigado pela sua ajuda
        estou a caminho de casa
        at\u{00e9} amanh\u{00e3}
        posso ligar mais tarde
        tenha um bom dia
        n\u{00e3}o h\u{00e1} problema
        envie os detalhes por favor
        estou feliz por ajudar
        """),
        (.dutch, """
        bedankt voor je hulp
        ik ben onderweg naar huis
        tot morgen
        ik bel je later
        fijne dag
        geen probleem
        kun je de details sturen
        ik help je graag
        """),
        (.swedish, """
        tack f\u{00f6}r din hj\u{00e4}lp
        jag \u{00e4}r p\u{00e5} v\u{00e4}g hem
        vi ses i morgon
        jag ringer dig senare
        ha en bra dag
        inga problem
        kan du skicka detaljerna
        jag hj\u{00e4}lper dig g\u{00e4}rna
        """),
        (.danish, """
        tak for din hj\u{00e6}lp
        jeg er p\u{00e5} vej hjem
        vi ses i morgen
        jeg ringer til dig senere
        hav en god dag
        det er ikke noget problem
        kan du sende detaljerne
        jeg vil gerne hj\u{00e6}lpe
        kommer I til middag
        """),
        (.norwegian, """
        takk for hjelpen
        jeg er p\u{00e5} vei hjem
        vi ses i morgen
        jeg ringer deg senere
        ha en fin dag
        det er ikke noe problem
        kan du sende detaljene
        jeg hjelper deg gjerne
        """),
        (.finnish, """
        kiitos avustasi
        olen matkalla kotiin
        n\u{00e4}hd\u{00e4}\u{00e4}n huomenna
        soitan sinulle my\u{00f6}hemmin
        hyv\u{00e4}\u{00e4} p\u{00e4}iv\u{00e4}\u{00e4}
        ei ole ongelmaa
        voitko l\u{00e4}hett\u{00e4}\u{00e4} tiedot
        autan mielell\u{00e4}ni
        """)
    ]
}
