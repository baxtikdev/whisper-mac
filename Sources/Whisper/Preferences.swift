import AppKit

enum Theme: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var appearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var current: Theme {
        Theme(rawValue: UserDefaults.standard.string(forKey: Preferences.themeKey) ?? "") ?? .dark
    }

    static func apply() {
        NSApp.appearance = current.appearance
    }
}

enum RecorderStyle: String, CaseIterable, Identifiable {
    case classic, mini, none

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static var current: RecorderStyle {
        RecorderStyle(rawValue: UserDefaults.standard.string(forKey: Preferences.recorderStyleKey) ?? "") ?? .mini
    }
}

enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Whisper"
}

enum Preferences {
    static let apiKeyAccount = "elevenlabs"
    static let languageKey = "language"
    static let keytermsKey = "keyterms"
    static let noVerbatimKey = "noVerbatim"
    static let soundsKey = "sounds"
    static let soundVolumeKey = "soundVolume"
    static let themeKey = "theme"
    static let recorderStyleKey = "recorderStyle"
    static let alwaysShowKey = "alwaysShow"
    static let autocapitalizeKey = "autocapitalize"
    static let autoPasteKey = "autoPaste"
    static let retentionKey = "retentionDays"
    static let replacementsKey = "replacements"
    static let modelKey = "model"
    static let soundStyleKey = "soundStyle"
    static let latinKey = "uzbekLatin"

    static let models: [VoiceModel] = [
        VoiceModel(id: "scribe_v2_realtime", name: "Scribe v2 Realtime", detail: "Best accuracy, 90+ languages", speed: 4, accuracy: 5),
        VoiceModel(id: "scribe_v2_realtime_turbo", name: "Scribe v2 Realtime Turbo", detail: "Faster, slightly less accurate", speed: 5, accuracy: 4),
        VoiceModel(id: "scribe_v2_realtime_lite", name: "Scribe v2 Realtime Lite", detail: "Lightest and cheapest", speed: 5, accuracy: 3),
    ]

    static let languages: [(code: String, name: String)] = [
        ("uz", "Uzbek"),
        ("ru", "Russian"),
        ("en", "English"),
        ("tr", "Turkish"),
        ("", "Auto-detect"),
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            languageKey: "uz",
            keytermsKey: "",
            noVerbatimKey: true,
            soundsKey: true,
            soundVolumeKey: 0.6,
            themeKey: Theme.dark.rawValue,
            recorderStyleKey: RecorderStyle.mini.rawValue,
            alwaysShowKey: false,
            autocapitalizeKey: true,
            autoPasteKey: true,
            retentionKey: 0,
            modelKey: "scribe_v2_realtime",
            soundStyleKey: "classic",
            latinKey: true,
        ])
    }

    static var apiKey: String? {
        guard let key = Secrets.read(apiKeyAccount), !key.isEmpty else { return nil }
        return key
    }

    static var vocabulary: [String] {
        get {
            (UserDefaults.standard.string(forKey: keytermsKey) ?? "")
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            UserDefaults.standard.set(newValue.joined(separator: ", "), forKey: keytermsKey)
        }
    }

    static var replacements: [Replacement] {
        get {
            guard let data = UserDefaults.standard.data(forKey: replacementsKey) else { return [] }
            return (try? JSONDecoder().decode([Replacement].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: replacementsKey)
        }
    }

    static var forcesLatin: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: latinKey) && (defaults.string(forKey: languageKey) ?? "uz") == "uz"
    }

    static func display(_ text: String) -> String {
        forcesLatin ? UzbekLatin.convert(text) : text
    }

    static func polish(_ text: String) -> String {
        var result = display(text)
        for replacement in replacements where !replacement.from.isEmpty {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: replacement.from) + "(?![\\p{L}\\p{N}])"
            result = result.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: replacement.to), options: [.regularExpression, .caseInsensitive])
        }
        if UserDefaults.standard.bool(forKey: autocapitalizeKey), let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}

struct Replacement: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: String
    var to: String
}

struct VoiceModel: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let speed: Int
    let accuracy: Int
}

enum SoundEvent {
    case start, stop, cancel, error

    private func files(style: String) -> (file: String, fallback: String)? {
        switch (style, self) {
        case ("off", _): nil
        case ("simple", .start): ("Start", "Tink")
        case ("simple", .stop): ("Stop", "Pop")
        case (_, .start): ("StartClassic", "Glass")
        case (_, .stop): ("StopClassic", "Bottle")
        case (_, .cancel): ("noResult1", "Funk")
        case (_, .error): ("NotificationError", "Basso")
        }
    }

    func play() {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: Preferences.soundStyleKey) ?? "classic"
        guard let pair = files(style: style) else { return }
        let sound = SoundLibrary.url(for: pair.file).flatMap { NSSound(contentsOf: $0, byReference: true) }
            ?? NSSound(named: NSSound.Name(pair.fallback))
        guard let sound else { return }
        sound.volume = Float(defaults.double(forKey: Preferences.soundVolumeKey))
        sound.play()
    }
}

enum SoundLibrary {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whisper/Sounds", isDirectory: true)
    }

    static func url(for name: String) -> URL? {
        let local = folder.appendingPathComponent("\(name).m4a")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
}

enum UzbekLatin {
    private static let map: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "ғ": "g‘", "д": "d", "ё": "yo", "ж": "j", "з": "z",
        "и": "i", "й": "y", "к": "k", "қ": "q", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p",
        "р": "r", "с": "s", "т": "t", "у": "u", "ў": "o‘", "ф": "f", "х": "x", "ҳ": "h", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "’", "ь": "", "ы": "i", "э": "e", "ю": "yu", "я": "ya",
    ]

    private static let vowels: Set<Character> = ["а", "е", "ё", "и", "о", "у", "ў", "э", "ю", "я", "ъ", "ь"]

    static func convert(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) else { return text }
        let characters = Array(text)
        var output = ""
        for (index, character) in characters.enumerated() {
            let lower = Character(character.lowercased())
            let previous = index > 0 ? Character(characters[index - 1].lowercased()) : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            var latin: String
            if lower == "е" {
                let wordStart = previous.map { !$0.isLetter } ?? true
                latin = wordStart || vowels.contains(previous!) ? "ye" : "e"
            } else if let mapped = map[lower] {
                latin = mapped
            } else {
                output.append(character)
                continue
            }
            if character.isUppercase, let first = latin.first {
                let shout = next?.isUppercase == true && next?.isLetter == true
                latin = shout ? latin.uppercased() : String(first).uppercased() + latin.dropFirst()
            }
            output += latin
        }
        return output
    }
}
