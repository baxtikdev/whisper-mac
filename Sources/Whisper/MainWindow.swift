import AVFoundation
import ServiceManagement
import SwiftUI

enum Palette {
    static let content = dynamic(dark: 0.18, light: 0.965)
    static let sidebar = dynamic(dark: 0.18, light: 0.94)
    static let card = dynamic(dark: 0.232, light: 1.0)
    static let selection = dynamic(dark: 0.29, light: 0.87)
    static let separator = dynamic(dark: 0.247, light: 0.86)

    private static func dynamic(dark: CGFloat, light: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: dark, alpha: 1)
                : NSColor(white: light, alpha: 1)
        })
    }
}

struct MainView: View {
    @Bindable var dictation: Dictation
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                Sidebar(selection: $dictation.pane)
                    .frame(width: 184)
                    .background(Palette.sidebar)
                    .transition(.move(edge: .leading))
                Rectangle().fill(Palette.separator).frame(width: 1)
            }
            VStack(spacing: 0) {
                TopBar(sidebarVisible: $sidebarVisible)
                Rectangle().fill(Palette.separator).frame(height: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
            }
            .background(Palette.content)
        }
        .ignoresSafeArea()
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch dictation.pane ?? .home {
        case .home: HomeView(dictation: dictation)
        case .modes: ModesView()
        case .vocabulary: VocabularyView()
        case .configuration: ConfigurationView(dictation: dictation)
        case .sound: SoundView()
        case .models: ModelsView()
        case .history: HistoryView(history: dictation.history)
        }
    }
}

private struct TopBar: View {
    @Binding var sidebarVisible: Bool
    @State private var microphone = Microphone.currentName

    var body: some View {
        HStack(spacing: 10) {
            if !sidebarVisible {
                Color.clear.frame(width: 64)
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { sidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Toggle sidebar")
            Spacer()
            Text(microphone)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .foregroundStyle(.secondary)
            Image(systemName: "laptopcomputer")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphone = Microphone.currentName
        }
    }
}

enum Microphone {
    static var currentName: String {
        (AVCaptureDevice.default(for: .audio)?.localizedName).map { "\($0) (Default)" } ?? "No microphone"
    }
}

private struct Sidebar: View {
    @Binding var selection: Pane?

    private let groups: [[Pane]] = [[.home], [.modes, .vocabulary], [.configuration, .sound, .models], [.history]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 56)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(groups.indices, id: \.self) { index in
                    VStack(spacing: 1) {
                        ForEach(groups[index]) { pane in
                            SidebarRow(pane: pane, selected: (selection ?? .home) == pane) {
                                selection = pane
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            Spacer()
            VStack(spacing: 8) {
                Text(Preferences.apiKey == nil ? "ElevenLabs not connected" : "ElevenLabs connected")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(AppInfo.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 35)
                    .background(Palette.card.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            }
            .padding(12)
        }
    }
}

private struct SidebarRow: View {
    let pane: Pane
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                Text(pane.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Palette.selection : (hovering ? Palette.selection.opacity(0.5) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct KeyChips: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(Palette.selection, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            }
        }
    }
}

private enum StatsRange: String, CaseIterable, Identifiable {
    case all = "All time"
    case today = "Today"
    case week = "Last 7 days"
    case month = "Last 30 days"

    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        switch self {
        case .all: true
        case .today: Calendar.current.isDateInToday(date)
        case .week: date > .now.addingTimeInterval(-7 * 86_400)
        case .month: date > .now.addingTimeInterval(-30 * 86_400)
        }
    }
}

private struct HomeView: View {
    let dictation: Dictation
    @State private var range = StatsRange.all

    var body: some View {
        let stats = HistoryStats(dictation.history.entries.filter { range.includes($0.date) })
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Menu {
                        Picker("", selection: $range) {
                            ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        HStack(spacing: 5) {
                            Text(range.rawValue)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    HStack(alignment: .top) {
                        StatColumn(value: "\(stats.averageWPM) WPM", label: "Average speed")
                        StatColumn(value: stats.words.formatted(), label: "Words")
                        StatColumn(value: "\(stats.appsUsed)", label: "Apps used")
                        StatColumn(value: Self.format(stats.timeSaved), label: range == .all ? "Saved all time" : "Saved")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle("Get started")
                    GetStartedRow(symbol: "record.circle", title: "Start recording", subtitle: "Turn your voice to text with a single click.", keys: ["⌥", "Space"]) {
                        dictation.toggleFromMenu()
                    }
                    if Preferences.apiKey == nil {
                        GetStartedRow(symbol: "key.fill", title: "Connect ElevenLabs", subtitle: "Add your API key to start transcribing.") {
                            dictation.pane = .models
                        }
                    }
                    GetStartedRow(symbol: "hand.point.up.left", title: "Customize your shortcuts", subtitle: "Change the keyboard shortcuts for \(AppInfo.name).") {
                        dictation.pane = .configuration
                    }
                    GetStartedRow(symbol: "sparkle", title: "Create a mode", subtitle: "Build the perfect mode for your workflow.") {
                        dictation.pane = .modes
                    }
                    GetStartedRow(symbol: "book.closed", title: "Add vocabulary", subtitle: "Teach \(AppInfo.name) custom words, names, or industry terms.") {
                        dictation.pane = .vocabulary
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("What's new?")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.changes, id: \.title) { change in
                            HStack(alignment: .top, spacing: 24) {
                                Text(change.date)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .leading)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(change.title).font(.system(size: 14, weight: .semibold))
                                    Text(change.detail).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
                }
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private static let changes: [(date: String, title: String, detail: String)] = [
        ("Oct 1", "ElevenLabs Scribe v2 Realtime", "Live transcription in 90+ languages with Uzbek as the default."),
        ("Oct 1", "Vocabulary & replacements", "Teach custom terms and auto-replace words after every dictation."),
        ("Oct 1", "Mini & Classic recorder", "Choose how the recording window looks, or keep it always visible."),
    ]

    private static func format(_ interval: TimeInterval) -> String {
        if interval < 60 { return "\(Int(interval)) sec" }
        if interval < 3_600 { return "\(Int(interval / 60)) min" }
        let hours = Int(interval / 3_600)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 15, weight: .semibold))
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }
}

private struct GetStartedRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var keys: [String] = []
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if !keys.isEmpty { KeyChips(keys: keys) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hovering ? Palette.card : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ModesView: View {
    @State private var showingDetail = false

    var body: some View {
        if showingDetail {
            ModeDetailView { showingDetail = false }
        } else {
            modeList
        }
    }

    private var modeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Modes", systemImage: "info.circle")
                        .labelStyle(TitleThenIcon())
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button {} label: {
                        Label("Create mode", systemImage: "plus")
                    }
                    .controlSize(.large)
                    .disabled(true)
                    .help("AI modes with Gemini are coming next")
                }
                Button { showingDetail = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mic")
                            .foregroundStyle(.secondary)
                        Text("Voice to text").font(.system(size: 14, weight: .medium))
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Spacer()
                        Text("ElevenLabs")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(28)
        }
    }
}

private struct TitleThenIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.foregroundStyle(.secondary).font(.system(size: 12))
        }
    }
}

private struct ModeDetailView: View {
    let onBack: () -> Void
    @AppStorage(Preferences.languageKey) private var language = "uz"
    @AppStorage(Preferences.noVerbatimKey) private var noVerbatim = true
    @AppStorage(Preferences.autocapitalizeKey) private var autocapitalize = true
    @AppStorage(Preferences.autoPasteKey) private var autoPaste = true
    @AppStorage(Preferences.modelKey) private var model = "scribe_v2_realtime"
    @AppStorage(Preferences.latinKey) private var latin = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
                Label("Voice to text", systemImage: "mic")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            SettingsPage {
                SettingsSection {
                    SettingsRow("Preset") { Text("Voice to text").foregroundStyle(.secondary) }
                }
                SettingsSection {
                    SettingsRow("Language") {
                        Picker("", selection: $language) {
                            ForEach(Preferences.languages, id: \.code) { Text($0.name).tag($0.code) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsRow("Always Latin script", subtitle: "Convert Cyrillic Uzbek to Latin (o‘, g‘, sh, ch)") {
                        Toggle("", isOn: $latin).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                    }
                    .disabled(language != "uz")
                    SettingsRow("Voice Model") {
                        Picker("", selection: $model) {
                            ForEach(Preferences.models) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsSection {
                    SettingsRow("Keyboard shortcut", subtitle: "Start a recording in this mode") { KeyChips(keys: ["⌥", "Space"]) }
                }
                SettingsSection("Advanced settings") {
                    SettingsRow("Remove filler words") { Toggle("", isOn: $noVerbatim).toggleStyle(.switch).labelsHidden().controlSize(.mini) }
                    SettingsRow("Autocapitalize insert") { Toggle("", isOn: $autocapitalize).toggleStyle(.switch).labelsHidden().controlSize(.mini) }
                    SettingsRow("Auto paste") {
                        Picker("", selection: $autoPaste) {
                            Text("On (Default)").tag(true)
                            Text("Copy only").tag(false)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }
}

struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                Group(subviews: content()) { subviews in
                    ForEach(subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id {
                            Rectangle()
                                .fill(Palette.separator)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    var hasTiles = false
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, tiles: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.hasTiles = tiles
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity, alignment: hasTiles ? .top : .center)
            Spacer(minLength: 12)
            trailing()
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }
}

private struct VocabularyView: View {
    @State private var words = Preferences.vocabulary
    @State private var replacements = Preferences.replacements
    @State private var draft = ""
    @State private var replacingFrom: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let replacingFrom {
                    Text(replacingFrom)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                }
                TextField(replacingFrom == nil ? "New word or replacement" : "Replace with…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.escape) {
                        replacingFrom = nil
                        return .handled
                    }
                Spacer()
                if replacingFrom == nil {
                    HStack(spacing: 6) {
                        Text("Add word").foregroundStyle(.secondary)
                        KeyChips(keys: ["↩"])
                    }
                    Button(action: beginReplacement) {
                        HStack(spacing: 6) {
                            Text("Replace with…").foregroundStyle(.secondary)
                            KeyChips(keys: ["⌘", "↩"])
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    HStack(spacing: 6) {
                        Text("Save").foregroundStyle(.secondary)
                        KeyChips(keys: ["↩"])
                    }
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))

            if words.isEmpty && replacements.isEmpty {
                ContentUnavailableView("No vocabulary yet", systemImage: "book.closed", description: Text("Add names, products and terms like TheCargo or D-System so they are spelled right."))
            } else {
                List {
                    if !words.isEmpty {
                        Section("Words") {
                            ForEach(words, id: \.self) { word in
                                HStack {
                                    Text(word)
                                    Spacer()
                                    Button { remove(word) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    if !replacements.isEmpty {
                        Section("Replacements") {
                            ForEach(replacements) { item in
                                HStack {
                                    Text(item.from)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    Text(item.to)
                                    Spacer()
                                    Button { remove(item) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }

    private func submit() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        if let from = replacingFrom {
            replacements.append(Replacement(from: from, to: value))
            Preferences.replacements = replacements
            replacingFrom = nil
        } else if !words.contains(value) {
            words.append(value)
            Preferences.vocabulary = words
        }
        draft = ""
    }

    private func beginReplacement() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        replacingFrom = value
        draft = ""
    }

    private func remove(_ word: String) {
        words.removeAll { $0 == word }
        Preferences.vocabulary = words
    }

    private func remove(_ item: Replacement) {
        replacements.removeAll { $0.id == item.id }
        Preferences.replacements = replacements
    }
}

private struct ConfigurationView: View {
    let dictation: Dictation
    @AppStorage(Preferences.themeKey) private var theme = Theme.dark.rawValue
    @AppStorage(Preferences.recorderStyleKey) private var recorder = RecorderStyle.mini.rawValue
    @AppStorage(Preferences.alwaysShowKey) private var alwaysShow = false
    @AppStorage(Preferences.retentionKey) private var retention = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = Paster.isTrusted
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        SettingsPage {
            SettingsSection("Appearance") {
                SettingsRow("Theme", tiles: true) {
                    HStack(spacing: 10) {
                        ForEach(Theme.allCases) { item in
                            ChoiceTile(title: item.title, selected: theme == item.rawValue) {
                                ThemePreview(theme: item)
                            } action: {
                                theme = item.rawValue
                                Theme.apply()
                            }
                        }
                    }
                }
                SettingsRow("Recording window", tiles: true) {
                    HStack(spacing: 10) {
                        ForEach(RecorderStyle.allCases) { item in
                            ChoiceTile(title: item.title, selected: recorder == item.rawValue, wide: true) {
                                RecorderPreview(style: item)
                            } action: {
                                recorder = item.rawValue
                            }
                        }
                    }
                }
                SettingsRow("Always show", subtitle: "Keep a small recorder pill at the top of the screen") {
                    Toggle("", isOn: $alwaysShow).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                }
            }

            SettingsSection("Keyboard Shortcuts") {
                SettingsRow("Toggle Recording", subtitle: "Starts and stops recordings") { KeyChips(keys: ["⌥", "Space"]) }
                SettingsRow("Push to talk", subtitle: "Hold to record, release when done") { KeyChips(keys: ["Hold", "⌥", "Space"]) }
                SettingsRow("Cancel Recording", subtitle: "Discards the active recording") { KeyChips(keys: ["esc"]) }
                if let error = dictation.hotKeyError {
                    SettingsRow(error) { Button("Retry") { dictation.registerHotKey() } }
                }
            }

            SettingsSection("Permissions") {
                SettingsRow("Microphone") {
                    PermissionBadge(granted: microphone == .authorized) {
                        if microphone == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in }
                        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                SettingsRow("Accessibility", subtitle: "Needed to paste text into other apps") {
                    PermissionBadge(granted: trusted) {
                        Paster.requestTrust()
                        Paster.openAccessibilitySettings()
                    }
                }
            }

            SettingsSection("Application") {
                SettingsRow("Launch on login") {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                }
                SettingsRow("Keep recordings for") {
                    Picker("", selection: $retention) {
                        Text("Forever").tag(0)
                        Text("30 days").tag(30)
                        Text("7 days").tag(7)
                        Text("1 day").tag(1)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: retention) { _, days in dictation.history.prune(keepingDays: days) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = Paster.isTrusted
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct PermissionBadge: View {
    let granted: Bool
    let action: () -> Void

    var body: some View {
        if granted {
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        } else {
            Button("Grant access", action: action)
        }
    }
}

private struct ChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    var wide = false
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview()
                    .frame(width: wide ? 92 : 68, height: wide ? 44 : 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1)
                            .padding(-3)
                    )
                Text(title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.16, blue: 0.62), Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.08, green: 0.1, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Ellipse()
                .fill(Color(red: 0.55, green: 0.68, blue: 1).opacity(0.55))
                .frame(width: 70, height: 26)
                .rotationEffect(.degrees(-28))
                .offset(x: -18, y: -18)
                .blur(radius: 6)
            HStack(spacing: 3) {
                window(dark: theme != .light)
                if theme == .auto { window(dark: false) }
            }
            .padding(.leading, 6)
            .padding(.top, 9)
        }
    }

    private func window(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(red: 0.42, green: 0.62, blue: 1))
                .frame(height: 7)
                .padding(4)
            Spacer(minLength: 0)
            HStack(spacing: 2.5) {
                Circle().fill(.green).frame(width: 4)
                Circle().fill(.yellow).frame(width: 4)
                Circle().fill(.red).frame(width: 4)
            }
            .padding(5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dark ? Color(white: 0.1) : Color(white: 0.96), in: UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
    }
}

private struct RecorderPreview: View {
    let style: RecorderStyle

    var body: some View {
        ZStack {
            Color(white: 0.16)
            switch style {
            case .classic:
                VStack(spacing: 0) {
                    bars(count: 22, width: 1.5)
                        .frame(maxHeight: .infinity)
                    Rectangle().fill(Color(white: 0.18)).frame(height: 10)
                }
                .frame(width: 88, height: 44)
                .background(.black, in: RoundedRectangle(cornerRadius: 7))
            case .mini:
                bars(count: 7, width: 2)
                    .frame(width: 58, height: 22)
                    .background(.black, in: Capsule())
            case .none:
                Image(systemName: "eye.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bars(count: Int, width: CGFloat) -> some View {
        HStack(spacing: width) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: width, height: [3, 7, 4, 10, 5, 12, 6, 9, 4][index % 9])
            }
        }
    }
}

private struct SoundView: View {
    @AppStorage(Preferences.soundStyleKey) private var style = "classic"
    @AppStorage(Preferences.soundVolumeKey) private var volume = 0.6

    var body: some View {
        SettingsPage {
            SettingsSection("Sound Effects") {
                SettingsRow("Sound effects") {
                    Picker("", selection: $style) {
                        Text("Simple").tag("simple")
                        Text("Classic").tag("classic")
                        Text("Off").tag("off")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: style) { SoundEvent.start.play() }
                }
                SettingsRow("Volume") {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $volume, in: 0...1, step: 0.1) { editing in
                            if !editing { SoundEvent.start.play() }
                        }
                        .frame(width: 220)
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                    }
                    .disabled(style == "off")
                }
            }
        }
    }
}

private struct ModelsView: View {
    @AppStorage(Preferences.modelKey) private var selected = "scribe_v2_realtime"
    @State private var query = ""
    @State private var showingKey = Preferences.apiKey == nil
    @State private var connected = Preferences.apiKey != nil

    var body: some View {
        let models = Preferences.models.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            HStack {
                Menu("ElevenLabs") {}
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(true)
                Spacer()
                Button {
                    showingKey = true
                } label: {
                    Label(connected ? "API key" : "Add API key", systemImage: "key.fill")
                }
                .controlSize(.large)
                .help("ElevenLabs API key")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    Text("")
                    Text("Model name")
                    Text("Type")
                    Text("Speed / Accuracy")
                    Text("Cloud")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
                ForEach(models) { model in
                    GridRow {
                        Image(systemName: selected == model.id ? "star.fill" : "star")
                            .foregroundStyle(selected == model.id ? .primary : .tertiary)
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(.black, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(.system(size: 14, weight: selected == model.id ? .semibold : .regular))
                                Text(model.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: "waveform.badge.mic").foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Meter(value: model.speed)
                            Meter(value: model.accuracy)
                        }
                        Image(systemName: "cloud").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = model.id }
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .safeAreaInset(edge: .top) { SearchBar(text: $query, prompt: "Search models") }
        .sheet(isPresented: $showingKey) {
            APIKeySheet { connected = Preferences.apiKey != nil }
        }
    }
}

private struct Meter: View {
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index < value ? Color.primary.opacity(0.75) : Color.primary.opacity(0.15))
                    .frame(width: 10, height: 3)
            }
        }
    }
}

private struct APIKeySheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = Secrets.read(Preferences.apiKeyAccount) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ElevenLabs API key").font(.headline)
                    Text("Needs the Speech to Text permission. Stored only on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            SecureField("sk_…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Link("Get an API key", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func save() {
        Secrets.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Preferences.apiKeyAccount)
        onSave()
        dismiss()
    }
}

private struct HistoryView: View {
    let history: HistoryStore
    @State private var query = ""

    var body: some View {
        let entries = history.entries.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "waveform", description: Text("Press ⌥ Space anywhere to start dictating."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.key) { day, items in
                            Text(Self.title(for: day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                                .padding(.leading, 4)
                            ForEach(items) { entry in
                                HistoryCard(entry: entry) { history.remove(entry) }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .top) { SearchBar(text: $query, prompt: "Search history") }
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: .now)).day ?? 0
        return "\(days) days ago"
    }
}

private struct HistoryCard: View {
    let entry: HistoryEntry
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if entry.text.isEmpty {
                Text("No voice found in recording")
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if hovering {
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !entry.text.isEmpty {
                    Button {
                        Paster.copy(entry.text)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy")
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Palette.card.opacity(hovering ? 1 : 0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering = $0 }
        .contextMenu {
            if !entry.text.isEmpty {
                Button("Copy") { Paster.copy(entry.text) }
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

private struct SearchBar: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}
