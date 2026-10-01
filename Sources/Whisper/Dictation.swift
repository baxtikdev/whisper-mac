import AppKit
import AVFoundation
import Carbon.HIToolbox
import Observation

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case home, modes, vocabulary, configuration, sound, models, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .modes: "Modes"
        case .vocabulary: "Vocabulary"
        case .configuration: "Configuration"
        case .sound: "Sound"
        case .models: "Models library"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .modes: "sparkle"
        case .vocabulary: "book.closed.fill"
        case .configuration: "gearshape.fill"
        case .sound: "speaker.wave.2.fill"
        case .models: "books.vertical.fill"
        case .history: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .home: .orange
        case .modes: .blue
        case .vocabulary: .blue
        case .configuration: .gray
        case .sound: .gray
        case .models: .gray
        case .history: .indigo
        }
    }
}

import SwiftUI

@Observable
final class Dictation {
    enum Phase: Equatable {
        case idle
        case recording
        case finishing
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var levels = Array(repeating: Float(0), count: 32)
    private(set) var message: String?
    private(set) var hotKeyError: String?
    private(set) var modeSwitcherVisible = false
    private(set) var confirmingCancel = false
    var pane: Pane? = .home

    let history: HistoryStore

    @ObservationIgnored var openMain: ((Pane) -> Void)?
    @ObservationIgnored private var audio: AudioCapture?
    @ObservationIgnored private var scribe: ScribeClient?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var pressedAt: ContinuousClock.Instant?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var toggleMode = false
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var cancelKey: HotKey?
    @ObservationIgnored private var modeKey: HotKey?
    @ObservationIgnored private var modeTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private lazy var overlay = OverlayController(dictation: self)

    init(history: HistoryStore) {
        self.history = history
    }

    func activate() {
        Preferences.registerDefaults()
        Theme.apply()
        registerHotKey()
        history.prune(keepingDays: UserDefaults.standard.integer(forKey: Preferences.retentionKey))
        overlay.update()
    }

    var elapsed: TimeInterval {
        guard phase != .idle, let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    func setExpanded(_ expanded: Bool) {
        UserDefaults.standard.set((expanded ? RecorderStyle.classic : RecorderStyle.mini).rawValue, forKey: Preferences.recorderStyleKey)
    }

    func showModeSwitcher() {
        modeSwitcherVisible = true
        overlay.update()
        modeTask?.cancel()
        modeTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hideModeSwitcher()
        }
    }

    func hideModeSwitcher() {
        modeTask?.cancel()
        modeSwitcherVisible = false
        overlay.update()
    }

    func keepRecording() {
        confirmingCancel = false
    }

    func registerHotKey() {
        modeKey = nil
        modeKey = try? HotKey(keyCode: kVK_ANSI_K, modifiers: optionKey | shiftKey)
        modeKey?.onDown = { [weak self] in self?.showModeSwitcher() }
        hotKey = nil
        do {
            let hotKey = try HotKey(keyCode: kVK_Space, modifiers: optionKey)
            hotKey.onDown = { [weak self] in self?.keyDown() }
            hotKey.onUp = { [weak self] in self?.keyUp() }
            self.hotKey = hotKey
            hotKeyError = nil
        } catch {
            hotKeyError = error.localizedDescription
        }
    }

    func toggleFromMenu() {
        switch phase {
        case .idle:
            toggleMode = true
            start()
        case .recording:
            stop()
        case .finishing:
            break
        }
    }

    func cancel() {
        guard phase == .recording else { return }
        if elapsed >= 30 && !confirmingCancel {
            confirmingCancel = true
            SoundEvent.error.play()
            return
        }
        teardown()
        SoundEvent.cancel.play()
        overlay.update()
    }

    private func keyDown() {
        switch phase {
        case .idle:
            toggleMode = false
            pressedAt = .now
            start()
        case .recording:
            if toggleMode { stop() }
        case .finishing:
            break
        }
    }

    private func keyUp() {
        guard phase == .recording, let pressedAt else { return }
        self.pressedAt = nil
        if ContinuousClock.now - pressedAt < .milliseconds(350) {
            toggleMode = true
        } else {
            stop()
        }
    }

    private func start() {
        guard let apiKey = Preferences.apiKey else {
            flash("Add your ElevenLabs API key in Models library")
            openMain?(.models)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        default:
            flash("Allow microphone access in System Settings")
            return
        }

        let defaults = UserDefaults.standard
        let scribe = ScribeClient(options: ScribeOptions(
            apiKey: apiKey,
            language: defaults.string(forKey: Preferences.languageKey) ?? "uz",
            keyterms: Array(Preferences.vocabulary.prefix(100)),
            noVerbatim: defaults.bool(forKey: Preferences.noVerbatimKey),
            model: defaults.string(forKey: Preferences.modelKey) ?? "scribe_v2_realtime"
        ))
        scribe.onPartial = { [weak self] text in self?.transcript = Preferences.display(text) }
        scribe.onError = { [weak self] text in self?.fail(text) }
        scribe.connect()

        let audio = AudioCapture()
        let stream: AsyncStream<AudioEvent>
        do {
            stream = try audio.start()
        } catch {
            scribe.cancel()
            flash(error.localizedDescription)
            return
        }

        self.scribe = scribe
        self.audio = audio
        startedAt = .now
        transcript = ""
        message = nil
        levels = Array(repeating: 0, count: levels.count)
        phase = .recording
        cancelKey = try? HotKey(keyCode: kVK_Escape, modifiers: 0)
        cancelKey?.onDown = { [weak self] in self?.cancel() }
        SoundEvent.start.play()
        overlay.update()

        pump = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .pcm(let data):
                    self.scribe?.send(data)
                case .level(let level):
                    self.levels.removeFirst()
                    self.levels.append(level)
                }
            }
        }
    }

    private func stop() {
        guard phase == .recording, let audio, let scribe else { return }
        confirmingCancel = false
        phase = .finishing
        cancelKey = nil
        audio.stop()
        SoundEvent.stop.play()
        overlay.update()
        let duration = Date().timeIntervalSince(startedAt ?? .now)
        let app = NSWorkspace.shared.frontmostApplication?.localizedName

        Task {
            await pump?.value
            pump = nil
            let result = await scribe.finish()
            self.audio = nil
            self.scribe = nil
            phase = .idle
            switch result {
            case .success(let raw) where !raw.isEmpty:
                let text = Preferences.polish(raw)
                history.add(HistoryEntry(date: .now, text: text, duration: duration, app: app))
                transcript = ""
                overlay.update()
                if !UserDefaults.standard.bool(forKey: Preferences.autoPasteKey) {
                    Paster.copy(text)
                } else if !Paster.paste(text) {
                    flash("Copied — press ⌘V (Accessibility permission missing)")
                }
            case .success:
                history.add(HistoryEntry(date: .now, text: "", duration: duration, app: app))
                transcript = ""
                overlay.update()
            case .failure(let error):
                flash(error.message)
            }
        }
    }

    private func fail(_ text: String) {
        guard phase == .recording else { return }
        teardown()
        flash(text)
    }

    private func teardown() {
        confirmingCancel = false
        cancelKey = nil
        audio?.stop()
        pump?.cancel()
        pump = nil
        scribe?.cancel()
        audio = nil
        scribe = nil
        transcript = ""
        phase = .idle
    }

    private func flash(_ text: String) {
        message = text
        SoundEvent.error.play()
        overlay.update()
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            message = nil
            overlay.update()
        }
    }
}
