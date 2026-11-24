import Foundation

public struct EmojiEntry: Equatable, Sendable {
    public let text: String
    public let name: String
    public let keywords: String
}

public enum EmojiCategory: String, CaseIterable, Sendable {
    case faces = "Faces", people = "People", nature = "Nature", food = "Food"
    case travel = "Travel", activities = "Activities", objects = "Objects", symbols = "Symbols", flags = "Flags"
}

public enum EmojiCatalog {
    public static let entries: [EmojiEntry] = {
        let aliases: [UInt32: String] = [
            0x1F600: "happy smile grin lachen smiley froh", 0x1F602: "laugh tears funny lol lachen lustig",
            0x1F60A: "happy smile blush happy freundlich", 0x1F622: "sad cry traurig weinen",
            0x1F44D: "like yes good thumbs up daumen hoch", 0x1F44E: "dislike no thumbs down daumen runter",
            0x2764: "love heart red liebe herz", 0x1F525: "hot fire feuer",
            0x1F389: "party celebrate celebration feier", 0x1F436: "dog hund", 0x1F431: "cat katze",
            0x1F44B: "hello goodbye wave hallo", 0x1F64F: "thanks please pray danke bitte",
            0x1F382: "birthday cake geburtstag kuchen torte", 0x1F381: "gift present geschenk",
            0x1F618: "kiss love kuss liebe", 0x1F60D: "love heart eyes liebe verliebt",
            0x1F60E: "cool sunglasses sonnenbrille", 0x1F914: "think thinking denken nachdenken",
            0x1F970: "love hearts liebe", 0x1F607: "angel innocent engel",
            0x1F62D: "cry sad tears weinen traurig", 0x1F621: "angry mad wut sauer",
            0x1F643: "upside down sarcasm verkehrt", 0x1F480: "dead skull tot schaedel",
            0x1F4A9: "poop poo scheisse", 0x1F4AA: "strong muscle flex stark muskel",
            0x1F44F: "clap applause klatschen", 0x1F91D: "handshake agreement handschlag",
            0x1F44C: "ok okay perfekt", 0x1F91E: "luck fingers crossed glueck gluck",
            0x1F680: "rocket launch rakete", 0x1F4B0: "money geld", 0x1F4B8: "money spend geld",
            0x1F37B: "cheers beer bier prost", 0x1F37A: "beer bier", 0x2615: "coffee tea kaffee tee",
            0x1F355: "pizza food essen", 0x1F354: "burger food essen", 0x1F32F: "burrito food essen",
            0x1F338: "flower blossom blume", 0x1F339: "rose flower blume", 0x1F31E: "sun sunny sonne",
            0x2600: "sun sunny sonne", 0x1F327: "rain regen", 0x1F3E0: "home house haus zuhause",
            0x2705: "yes done check fertig ja", 0x274C: "no wrong nein falsch", 0x1F4AF: "hundred perfect perfekt"
        ]
        let afrikaans: [UInt32: String] = [
            0x1F600: "glimlag gelukkig", 0x1F602: "lag trane snaaks", 0x1F60A: "glimlag gelukkig bloos",
            0x1F622: "hartseer huil", 0x1F62D: "huil hartseer trane", 0x1F621: "kwaad woede",
            0x1F44D: "duim op ja goed", 0x1F44E: "duim af nee", 0x2764: "liefde hart rooi",
            0x1F525: "vuur warm", 0x1F389: "partytjie vier", 0x1F436: "hond", 0x1F431: "kat",
            0x1F408: "kat", 0x1F415: "hond", 0x1F44B: "waai hallo totsiens", 0x1F64F: "dankie asseblief bid",
            0x1F382: "verjaarsdag koek", 0x1F381: "geskenk", 0x1F618: "soen liefde", 0x1F60D: "liefde verlief",
            0x1F60E: "sonbril koel", 0x1F914: "dink", 0x1F970: "liefde harte", 0x1F607: "engel onskuldig",
            0x1F480: "skedel dood", 0x1F4AA: "sterk spier", 0x1F44F: "klap applous", 0x1F91D: "handskud ooreenkoms",
            0x1F91E: "geluk", 0x1F680: "vuurpyl", 0x1F4B0: "geld", 0x1F4B8: "geld betaal",
            0x1F37B: "bier", 0x1F37A: "bier", 0x2615: "koffie tee", 0x1F355: "kos eet",
            0x1F354: "kos eet", 0x1F338: "blom", 0x1F339: "roos blom", 0x1F31E: "son sonnig",
            0x2600: "son sonnig", 0x1F327: "reen", 0x1F3E0: "huis tuis", 0x2705: "ja klaar", 0x274C: "nee verkeerd"
        ]
        let ranges = [0xA9...0xAE, 0x203C...0x21FF, 0x2300...0x27FF, 0x2B00...0x2BFF, 0x3030...0x3299, 0x1F000...0x1FAFF]
        var result: [EmojiEntry] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmoji,
                      !scalar.properties.isEmojiModifier,
                      !(0x1F1E6...0x1F1FF).contains(value),
                      let name = scalar.properties.name else { continue }
                let text = String(scalar) + (scalar.properties.isEmojiPresentation ? "" : "\u{FE0F}")
                let keywords = (aliases[scalar.value] ?? "") + " " + (afrikaans[scalar.value] ?? "")
                result.append(EmojiEntry(text: text, name: name.lowercased(), keywords: keywords))
                if scalar.properties.isEmojiModifierBase {
                    for (index, tone) in ["light", "medium light", "medium", "medium dark", "dark"].enumerated() {
                        let variant = String(scalar) + String(Unicode.Scalar(0x1F3FB + index)!)
                        result.append(EmojiEntry(text: variant, name: name.lowercased() + " " + tone + " skin tone",
                                                 keywords: keywords))
                    }
                }
            }
        }
        let sequences: [(String, String)] = [
            ("\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", "rainbow flag pride"),
            ("\u{1F3F3}\u{FE0F}\u{200D}\u{26A7}\u{FE0F}", "transgender flag pride"),
            ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", "family parents children"),
            ("\u{2764}\u{FE0F}\u{200D}\u{1F525}", "heart on fire love")
        ]
        result += sequences.map { EmojiEntry(text: $0.0, name: $0.1,
            keywords: $0.1.hasPrefix("family") ? "gesin familie kinders eltern man woman girl boy" :
                $0.1.hasPrefix("heart") ? "liefde hart vuur" : "vlag trots flagge") }
        let people: [(String, String, String)] = [
            ("\u{1F9D1}", "person", "persoon mensch"), ("\u{1F469}", "woman", "vrou frau"), ("\u{1F468}", "man", "man mann")
        ]
        let professions: [(String, String, String)] = [
            ("\u{1F4BB}", "technologist developer programmer", "programmeerder ontwikkelaar entwickler"),
            ("\u{2695}\u{FE0F}", "health worker doctor nurse", "dokter verpleegster arzt aerztin"),
            ("\u{1F3EB}", "teacher", "onderwyser lehrer"), ("\u{1F52C}", "scientist", "wetenskaplike wissenschaftler"),
            ("\u{1F373}", "cook chef", "kok koch"), ("\u{1F33E}", "farmer", "boer bauer"),
            ("\u{1F692}", "firefighter", "brandweerman feuerwehr"), ("\u{1F680}", "astronaut", "ruimtevaarder astronaut")
        ]
        let tones = ["", "light", "medium light", "medium", "medium dark", "dark"]
        for (person, personName, personAliases) in people {
            for (role, roleName, roleAliases) in professions {
                for (index, tone) in tones.enumerated() {
                    let modifier = index == 0 ? "" : String(Unicode.Scalar(0x1F3FA + index)!)
                    result.append(EmojiEntry(text: person + modifier + "\u{200D}" + role,
                        name: personName + " " + roleName + (tone.isEmpty ? "" : " " + tone + " skin tone"),
                        keywords: personAliases + " " + roleAliases))
                }
            }
        }
        let parents = [["\u{1F468}", "\u{1F469}"], ["\u{1F468}", "\u{1F468}"], ["\u{1F469}", "\u{1F469}"], ["\u{1F468}"], ["\u{1F469}"]]
        let children = [["\u{1F466}"], ["\u{1F467}"], ["\u{1F466}", "\u{1F466}"], ["\u{1F467}", "\u{1F466}"], ["\u{1F467}", "\u{1F467}"]]
        let names = ["\u{1F468}": "man", "\u{1F469}": "woman", "\u{1F466}": "boy", "\u{1F467}": "girl"]
        for adults in parents {
            for kids in children {
                let members = adults + kids
                result.append(EmojiEntry(text: members.joined(separator: "\u{200D}"),
                    name: "family " + members.compactMap { names[$0] }.joined(separator: " "),
                    keywords: "gesin familie kinders eltern"))
            }
        }
        let locale = Locale(identifier: "en_US")
        for region in Locale.Region.isoRegions.map(\.identifier).sorted() where region.count == 2 {
            let scalars = region.unicodeScalars
            guard scalars.allSatisfy({ (65...90).contains($0.value) }) else { continue }
            let flag = scalars.map { String(Unicode.Scalar(0x1F1E6 + $0.value - 65)!) }.joined()
            result.append(EmojiEntry(text: flag, name: "flag " + (locale.localizedString(forRegionCode: region) ?? region).lowercased(),
                                     keywords: region.lowercased() + " " + ["de_DE", "af_ZA"].compactMap {
                                         Locale(identifier: $0).localizedString(forRegionCode: region)?.lowercased()
                                     }.joined(separator: " ") + " vlag flagge"))
        }
        var seen = Set<String>()
        result = result.filter { seen.insert($0.text).inserted }
        let favorites: [UInt32] = [0x1F600, 0x1F602, 0x2764, 0x1F44D, 0x1F60A, 0x1F389, 0x1F525, 0x1F64F,
                                   0x1F44B, 0x1F60D, 0x1F618, 0x1F914, 0x1F44F, 0x1F4AA, 0x1F62D, 0x1F609]
        let preferred = favorites.compactMap { value in
            result.first { $0.text.unicodeScalars.first?.value == value }
        }
        let preferredText = Set(preferred.map(\.text))
        return preferred + result.filter { !preferredText.contains($0.text) }
    }()

    private static let byText = Dictionary(uniqueKeysWithValues: entries.map { ($0.text, $0) })
    private static let searchIndex: [(EmojiEntry, [String])] = entries.map {
        ($0, normalized($0.name + " " + $0.keywords).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }
    private static let vocabulary = Set(searchIndex.flatMap { $0.1 })
    public static func entry(for text: String) -> EmojiEntry? { byText[text] }
    public static var popular: [EmojiEntry] { Array(entries.prefix(16)) }

    private static func toneKey(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !(0x1F3FB...0x1F3FF).contains($0.value) && $0.value != 0xFE0F
        }))
    }

    private static let toneGroups: [String: [EmojiEntry]] = Dictionary(grouping: entries, by: { toneKey($0.text) })

    public static func toneVariants(for text: String) -> [EmojiEntry] {
        guard entry(for: text) != nil else { return [] }
        return toneGroups[toneKey(text)] ?? []
    }

    public static func grouped(_ entries: [EmojiEntry]) -> [EmojiEntry] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let key = toneKey(entry.text)
            guard seen.insert(key).inserted else { return nil }
            return toneGroups[key]?.first ?? entry
        }
    }

    public static func category(for entry: EmojiEntry) -> EmojiCategory {
        let values = entry.text.unicodeScalars.map(\.value)
        guard let first = values.first else { return .symbols }
        if (0x1F1E6...0x1F1FF).contains(first) { return .flags }
        // Unicode 17 emoji-test groups define the scalar categories.
        switch first {
        case 0x2620, 0x2639...0x263A, 0x2763...0x2764, 0x1F479...0x1F47B: return .faces
        case 0x1F47D...0x1F480, 0x1F48B...0x1F48C, 0x1F493...0x1F49F, 0x1F4A2: return .faces
        case 0x1F4A4...0x1F4A6, 0x1F4A8...0x1F4A9, 0x1F4AB...0x1F4AD, 0x1F4AF: return .faces
        case 0x1F573, 0x1F5A4, 0x1F5E8, 0x1F5EF: return .faces
        case 0x1F600...0x1F644, 0x1F648...0x1F64A, 0x1F90D...0x1F90E, 0x1F910...0x1F917: return .faces
        case 0x1F920...0x1F925, 0x1F927...0x1F92F, 0x1F970...0x1F976, 0x1F978...0x1F97A: return .faces
        case 0x1F9D0, 0x1F9E1, 0x1FA75...0x1FA77, 0x1FAE0...0x1FAE5: return .faces
        case 0x1FAE8...0x1FAEA, 0x1FAEF: return .faces
        case 0x261D, 0x26F7, 0x26F9, 0x270A...0x270D: return .people
        case 0x1F385, 0x1F3C2...0x1F3C4, 0x1F3C7, 0x1F3CA...0x1F3CC: return .people
        case 0x1F440...0x1F450, 0x1F463...0x1F478, 0x1F47C, 0x1F481...0x1F483: return .people
        case 0x1F485...0x1F487, 0x1F48F, 0x1F491, 0x1F4AA: return .people
        case 0x1F574...0x1F575, 0x1F57A, 0x1F590, 0x1F595...0x1F596: return .people
        case 0x1F5E3, 0x1F645...0x1F647, 0x1F64B...0x1F64F, 0x1F6A3: return .people
        case 0x1F6B4...0x1F6B6, 0x1F6C0, 0x1F6CC, 0x1F90C: return .people
        case 0x1F90F, 0x1F918...0x1F91F, 0x1F926, 0x1F930...0x1F93A: return .people
        case 0x1F93C...0x1F93E, 0x1F977, 0x1F9B4...0x1F9B9, 0x1F9BB: return .people
        case 0x1F9BE...0x1F9BF, 0x1F9CC...0x1F9CF, 0x1F9D1...0x1F9E0, 0x1FAC0...0x1FAC6: return .people
        case 0x1FAC8, 0x1FAE6, 0x1FAF0...0x1FAF8: return .people
        case 0x2618, 0x1F331...0x1F335, 0x1F337...0x1F33C, 0x1F33E...0x1F344: return .nature
        case 0x1F3F5, 0x1F400...0x1F43F, 0x1F490, 0x1F4AE: return .nature
        case 0x1F54A, 0x1F577...0x1F578, 0x1F940, 0x1F980...0x1F9AE: return .nature
        case 0x1FAB0...0x1FAB4, 0x1FAB6...0x1FABF, 0x1FACD...0x1FACF: return .nature
        case 0x2615, 0x1F32D...0x1F330, 0x1F336, 0x1F33D: return .food
        case 0x1F345...0x1F37F, 0x1F382, 0x1F3FA, 0x1F52A: return .food
        case 0x1F942...0x1F944, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CB, 0x1FAD0...0x1FADC: return .food
        case 0x231A...0x231B, 0x23F0...0x23F3, 0x2600...0x2604, 0x2614: return .travel
        case 0x2668, 0x2693, 0x26A1, 0x26C4...0x26C5: return .travel
        case 0x26C8, 0x26E9...0x26EA, 0x26F0...0x26F2, 0x26F4...0x26F5: return .travel
        case 0x26FA, 0x26FD, 0x2708, 0x2744: return .travel
        case 0x2B50, 0x1F300...0x1F321, 0x1F324...0x1F32C, 0x1F3A0...0x1F3A2: return .travel
        case 0x1F3AA, 0x1F3CD...0x1F3CE, 0x1F3D4...0x1F3E6, 0x1F3E8...0x1F3ED: return .travel
        case 0x1F3EF...0x1F3F0, 0x1F488, 0x1F492, 0x1F4A7: return .travel
        case 0x1F4BA, 0x1F525, 0x1F54B...0x1F54D, 0x1F550...0x1F567: return .travel
        case 0x1F570, 0x1F5FA...0x1F5FE, 0x1F680...0x1F6A2, 0x1F6A4...0x1F6A8: return .travel
        case 0x1F6B2, 0x1F6CE, 0x1F6D1, 0x1F6D5...0x1F6D6: return .travel
        case 0x1F6D8, 0x1F6DD...0x1F6DF, 0x1F6E2...0x1F6E5, 0x1F6E9: return .travel
        case 0x1F6EB...0x1F6EC, 0x1F6F0, 0x1F6F3...0x1F6F6, 0x1F6F8...0x1F6FC: return .travel
        case 0x1F9BC...0x1F9BD, 0x1F9ED, 0x1F9F1, 0x1F9F3: return .travel
        case 0x1FA82, 0x1FA90, 0x1FAA8, 0x1FAB5: return .travel
        case 0x265F...0x2660, 0x2663, 0x2665...0x2666, 0x26BD...0x26BE: return .activities
        case 0x26F3, 0x26F8, 0x2728, 0x1F004: return .activities
        case 0x1F0CF, 0x1F380...0x1F381, 0x1F383...0x1F384, 0x1F386...0x1F38B: return .activities
        case 0x1F38D...0x1F391, 0x1F396...0x1F397, 0x1F39F, 0x1F3A3: return .activities
        case 0x1F3A8, 0x1F3AB, 0x1F3AD...0x1F3B4, 0x1F3BD...0x1F3C0: return .activities
        case 0x1F3C5...0x1F3C6, 0x1F3C8...0x1F3C9, 0x1F3CF...0x1F3D3, 0x1F3F8: return .activities
        case 0x1F52B, 0x1F52E, 0x1F579, 0x1F5BC: return .activities
        case 0x1F6F7, 0x1F93F, 0x1F945, 0x1F947...0x1F94F: return .activities
        case 0x1F9E7...0x1F9E9, 0x1F9F5...0x1F9F6, 0x1F9F8, 0x1FA80...0x1FA81: return .activities
        case 0x1FA84...0x1FA86, 0x1FAA1...0x1FAA2, 0x1FAA9: return .activities
        case 0x2328, 0x260E, 0x2692, 0x2694: return .objects
        case 0x2696...0x2697, 0x2699, 0x26B0...0x26B1, 0x26CF: return .objects
        case 0x26D1, 0x26D3, 0x2702, 0x2709: return .objects
        case 0x270F, 0x2712, 0x1F392...0x1F393, 0x1F399...0x1F39B: return .objects
        case 0x1F39E, 0x1F3A4...0x1F3A5, 0x1F3A7, 0x1F3A9: return .objects
        case 0x1F3AC, 0x1F3B5...0x1F3BC, 0x1F3EE, 0x1F3F7: return .objects
        case 0x1F3F9, 0x1F451...0x1F462, 0x1F484, 0x1F489...0x1F48A: return .objects
        case 0x1F48D...0x1F48E, 0x1F4A1, 0x1F4A3, 0x1F4B0: return .objects
        case 0x1F4B3...0x1F4B9, 0x1F4BB...0x1F4DA, 0x1F4DC...0x1F4F2, 0x1F4F7...0x1F4FD: return .objects
        case 0x1F4FF, 0x1F507...0x1F517, 0x1F526...0x1F529, 0x1F52C...0x1F52D: return .objects
        case 0x1F56F, 0x1F576, 0x1F587, 0x1F58A...0x1F58D: return .objects
        case 0x1F5A5, 0x1F5A8, 0x1F5B1...0x1F5B2, 0x1F5C2...0x1F5C4: return .objects
        case 0x1F5D1...0x1F5D3, 0x1F5DC...0x1F5DE, 0x1F5E1, 0x1F5F3: return .objects
        case 0x1F5FF, 0x1F6AA, 0x1F6AC, 0x1F6BD: return .objects
        case 0x1F6BF, 0x1F6C1, 0x1F6CB, 0x1F6CD: return .objects
        case 0x1F6CF, 0x1F6D2, 0x1F6D7, 0x1F6E0...0x1F6E1: return .objects
        case 0x1F941, 0x1F97B...0x1F97F, 0x1F9AF, 0x1F9BA: return .objects
        case 0x1F9E2...0x1F9E6, 0x1F9EA...0x1F9EC, 0x1F9EE...0x1F9F0, 0x1F9F2: return .objects
        case 0x1F9F4, 0x1F9F7, 0x1F9F9...0x1F9FF, 0x1FA70...0x1FA74: return .objects
        case 0x1FA78...0x1FA7C, 0x1FA83, 0x1FA87...0x1FA8A, 0x1FA8E...0x1FA8F: return .objects
        case 0x1FA91...0x1FAA0, 0x1FAA3...0x1FAA7, 0x1FAAA...0x1FAAE, 0x1FAE7: return .objects
        case 0xA9, 0xAE, 0x203C, 0x2049: return .symbols
        case 0x2122, 0x2139, 0x2194...0x2199, 0x21A9...0x21AA: return .symbols
        case 0x23CF, 0x23E9...0x23EF, 0x23F8...0x23FA, 0x24C2: return .symbols
        case 0x25AA...0x25AB, 0x25B6, 0x25C0, 0x25FB...0x25FE: return .symbols
        case 0x2611, 0x2622...0x2623, 0x2626, 0x262A: return .symbols
        case 0x262E...0x262F, 0x2638, 0x2640, 0x2642: return .symbols
        case 0x2648...0x2653, 0x267B, 0x267E...0x267F, 0x2695: return .symbols
        case 0x269B...0x269C, 0x26A0, 0x26A7, 0x26AA...0x26AB: return .symbols
        case 0x26CE, 0x26D4, 0x2705, 0x2714: return .symbols
        case 0x2716, 0x271D, 0x2721, 0x2733...0x2734: return .symbols
        case 0x2747, 0x274C, 0x274E, 0x2753...0x2755: return .symbols
        case 0x2757, 0x2795...0x2797, 0x27A1, 0x27B0: return .symbols
        case 0x27BF, 0x2934...0x2935, 0x2B05...0x2B07, 0x2B1B...0x2B1C: return .symbols
        case 0x2B55, 0x3030, 0x303D, 0x3297: return .symbols
        case 0x3299, 0x1F170...0x1F171, 0x1F17E...0x1F17F, 0x1F18E: return .symbols
        case 0x1F191...0x1F19A, 0x1F201...0x1F202, 0x1F21A, 0x1F22F: return .symbols
        case 0x1F232...0x1F23A, 0x1F250...0x1F251, 0x1F3A6, 0x1F3E7: return .symbols
        case 0x1F4A0, 0x1F4B1...0x1F4B2, 0x1F4DB, 0x1F4F3...0x1F4F6: return .symbols
        case 0x1F500...0x1F506, 0x1F518...0x1F524, 0x1F52F...0x1F53D, 0x1F549: return .symbols
        case 0x1F54E, 0x1F6AB, 0x1F6AD...0x1F6B1, 0x1F6B3: return .symbols
        case 0x1F6B7...0x1F6BC, 0x1F6BE, 0x1F6C2...0x1F6C5, 0x1F6D0: return .symbols
        case 0x1F6DC, 0x1F7E0...0x1F7EB, 0x1F7F0, 0x1FAAF: return .symbols
        case 0x1FADF: return .symbols
        case 0x1F38C, 0x1F3C1, 0x1F3F3...0x1F3F4, 0x1F6A9: return .flags
        default: return .symbols
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func search(_ query: String) -> [EmojiEntry] {
        guard query.count <= 64 else { return [] }
        let words = normalized(query).split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" }).map(String.init)
        guard words.count <= 8, words.allSatisfy({ $0.count <= 32 }) else { return [] }
        guard !words.isEmpty else { return entries }
        func matches(approximate: [String: Set<String>]) -> [EmojiEntry] {
            var results: [(EmojiEntry, Int, Int)] = []
            for (index, item) in searchIndex.enumerated() {
                let (entry, tokens) = item
                var cost = 0
                var accepted = true
                for term in words {
                    if entry.text == term || tokens.contains(term) { continue }
                    if tokens.contains(where: { $0.hasPrefix(term) }) { cost += 1; continue }
                    if let alternatives = approximate[term], tokens.contains(where: alternatives.contains) { cost += 4; continue }
                    accepted = false
                    break
                }
                if accepted { results.append((entry, cost, index)) }
            }
            return results.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1 }.map { $0.0 }
        }
        let ordinary = matches(approximate: [:])
        if !ordinary.isEmpty { return ordinary }
        var approximate: [String: Set<String>] = [:]
        for term in words where (4...24).contains(term.count) {
            approximate[term] = Set(vocabulary.filter {
                abs($0.count - term.count) <= 1 && $0.count <= 24 && TextRules.distance(term, $0) <= 1
            })
        }
        return approximate.isEmpty ? [] : matches(approximate: approximate)
    }
}
