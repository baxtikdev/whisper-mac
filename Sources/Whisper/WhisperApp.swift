import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let dictation = Dictation(history: HistoryStore())

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictation.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        dictation.openMain?(.home)
        return true
    }
}

@main
struct WhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(dictation: delegate.dictation)
        } label: {
            MenuBarIcon(dictation: delegate.dictation)
        }

        Window(AppInfo.name, id: "main") {
            MainView(dictation: delegate.dictation)
        }
        .defaultSize(width: 748, height: 700)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct MenuBarIcon: View {
    let dictation: Dictation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.icon(for: dictation.phase))
            .task {
                dictation.openMain = { pane in
                    dictation.pane = pane
                    openWindow(id: "main")
                    NSApp.activate()
                }
                if Preferences.apiKey == nil {
                    dictation.openMain?(.models)
                }
            }
    }

    private static let outline = render(filled: false)
    private static let solid = render(filled: true)
    private static let custom: [String: NSImage] = loadCustom()

    private static func icon(for phase: Dictation.Phase) -> NSImage {
        switch phase {
        case .idle: custom["IconReady"] ?? outline
        case .recording: custom["IconRecording"] ?? solid
        case .finishing: custom["IconWorking"] ?? custom["IconRecording"] ?? solid
        }
    }

    private static func loadCustom() -> [String: NSImage] {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whisper/Brand/menubar", isDirectory: true)
        var images: [String: NSImage] = [:]
        for name in ["IconReady", "IconRecording", "IconWorking"] {
            let url = folder.appendingPathComponent("\(name)@2x.png")
            guard let image = NSImage(contentsOf: url), let rep = image.representations.first else { continue }
            image.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
            image.isTemplate = true
            images[name] = image
        }
        return images
    }

    private static func render(filled: Bool) -> NSImage {
        let shape = LogoMark(lineWidth: 1.9)
        let view = Group {
            if filled {
                shape.fill(.black)
            } else {
                shape.stroke(.black, style: StrokeStyle(lineWidth: 1.9, lineJoin: .round))
            }
        }
        .frame(width: 17, height: 15)
        .padding(.top, 1)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.size = NSSize(width: 17, height: 16)
        image.isTemplate = true
        return image
    }
}

private struct MenuContent: View {
    let dictation: Dictation
    @AppStorage(Preferences.languageKey) private var language = "uz"
    @AppStorage(Preferences.modelKey) private var model = "scribe_v2_realtime"

    var body: some View {
        Button(dictation.phase == .recording ? "Stop Recording" : "Toggle Recording") {
            dictation.toggleFromMenu()
        }
        Button("History…") { dictation.openMain?(.history) }
        Button("Settings…") { dictation.openMain?(.configuration) }
            .keyboardShortcut(",")
        if let latest = dictation.history.entries.first(where: { !$0.text.isEmpty }) {
            Button("Copy Last Transcript") { Paster.copy(latest.text) }
        }
        Divider()
        Menu(Microphone.currentName) {
            Text(Microphone.currentName)
        }
        Menu("Voice to text") {
            Picker("Language", selection: $language) {
                ForEach(Preferences.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
            Picker("Voice Model", selection: $model) {
                ForEach(Preferences.models) { Text($0.name).tag($0.id) }
            }
        }
        if let error = dictation.hotKeyError {
            Divider()
            Text(error)
            Button("Retry Shortcut") { dictation.registerHotKey() }
        }
        Divider()
        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
