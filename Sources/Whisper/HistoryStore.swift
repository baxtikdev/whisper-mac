import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var duration: TimeInterval
    var app: String?

    var words: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let limit = 1_000

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url) {
            entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func prune(keepingDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let before = entries.count
        entries.removeAll { $0.date < cutoff }
        if entries.count != before { save() }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        prune(keepingDays: UserDefaults.standard.integer(forKey: Preferences.retentionKey))
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct HistoryStats {
    let words: Int
    let averageWPM: Int
    let appsUsed: Int
    let timeSaved: TimeInterval

    init(_ entries: [HistoryEntry]) {
        let spoken = entries.filter { !$0.text.isEmpty }
        words = spoken.reduce(0) { $0 + $1.words }
        let speaking = spoken.reduce(0) { $0 + $1.duration }
        averageWPM = speaking > 0 ? Int((Double(words) / (speaking / 60)).rounded()) : 0
        appsUsed = Set(spoken.compactMap(\.app)).count
        timeSaved = max(Double(words) / 40 * 60 - speaking, 0)
    }
}
