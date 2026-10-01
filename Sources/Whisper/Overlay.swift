import AppKit
import SwiftUI

final class OverlayController {
    private let panel: NSPanel
    private let dictation: Dictation
    private let size = NSSize(width: 420, height: 150)
    private var visible = false
    private var defaultsObserver: NSObjectProtocol?
    private var hitRect = CGRect.zero
    private var monitors: [Any] = []

    init(dictation: Dictation) {
        self.dictation = dictation
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0
        let hosting = NSHostingView(rootView: OverlayView(dictation: dictation) { _ in })
        panel.contentView = hosting
        hosting.rootView = OverlayView(dictation: dictation) { [weak self] rect in
            self?.hitRect = rect
            self?.refreshHitTesting()
        }

        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHitTesting() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func refreshHitTesting() {
        guard visible, !hitRect.isEmpty else {
            panel.ignoresMouseEvents = true
            return
        }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let inside = hitRect.insetBy(dx: -6, dy: -6).contains(local)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }

    func update() {
        let style = RecorderStyle.current
        let alwaysShow = UserDefaults.standard.bool(forKey: Preferences.alwaysShowKey)
        let active = dictation.phase != .idle || dictation.message != nil || dictation.modeSwitcherVisible
        let shouldShow = active ? (style != .none || dictation.message != nil || dictation.modeSwitcherVisible) : (alwaysShow && style != .none)
        shouldShow ? show() : hide()
    }

    private func show() {
        if !visible {
            position()
            panel.orderFrontRegardless()
        }
        visible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.visible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func position() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 1))
    }
}

struct OverlayView: View {
    let dictation: Dictation
    let onHitRect: (CGRect) -> Void
    @AppStorage(Preferences.recorderStyleKey) private var style = RecorderStyle.mini.rawValue

    private var isClassic: Bool { style == RecorderStyle.classic.rawValue }
    private var isActive: Bool { dictation.phase != .idle }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if isActive && isClassic {
                    ClassicRecorder(dictation: dictation)
                        .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                } else if isActive {
                    MiniRecorder(dictation: dictation)
                        .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                } else {
                    IdleCapsule(dictation: dictation)
                        .transition(.opacity)
                }
            }
            .contextMenu {
                Button("Expand Window") { dictation.setExpanded(true) }
                Button("Open Settings") { dictation.openMain?(.configuration) }
                Button("Open History") { dictation.openMain?(.history) }
            }

            if dictation.confirmingCancel {
                CancelConfirm(dictation: dictation)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if dictation.modeSwitcherVisible {
                ModeList { dictation.hideModeSwitcher() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let message = dictation.message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.85), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { rect in
            onHitRect(rect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: dictation.phase)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: dictation.message)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dictation.confirmingCancel)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: dictation.modeSwitcherVisible)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: style)
    }
}

private struct ModeList: View {
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: "mic").font(.system(size: 10))
                    Text("Voice to text")
                    Spacer()
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(4)
        .frame(width: 150)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

private struct CancelConfirm: View {
    let dictation: Dictation

    var body: some View {
        HStack(spacing: 8) {
            Text("Discard this recording?")
                .foregroundStyle(.white.opacity(0.9))
            Button("Keep") { dictation.keepRecording() }
                .buttonStyle(OverlayChipStyle(tint: .white.opacity(0.14)))
            Button("Discard") { dictation.cancel() }
                .buttonStyle(OverlayChipStyle(tint: Color(red: 0.75, green: 0.16, blue: 0.2)))
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .frame(height: 30)
        .background(Color(white: 0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

private struct OverlayChipStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 21)
            .background(tint.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

private enum PillAction: Hashable {
    case modes, record, expand

    var tip: String {
        switch self {
        case .modes: "Change mode"
        case .record: "Start recording"
        case .expand: "Expand window"
        }
    }

    var keys: [String] {
        switch self {
        case .modes: ["⌥⇧K"]
        case .record: ["⌥", "Space"]
        case .expand: []
        }
    }
}

private struct IdleCapsule: View {
    let dictation: Dictation
    @State private var hovering = ProcessInfo.processInfo.arguments.contains("-forceHover")
    @State private var hovered: PillAction? = ProcessInfo.processInfo.arguments.contains("-forceHover") ? .record : nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if hovering || dictation.modeSwitcherVisible {
                    HStack(spacing: 2) {
                        pillButton(.modes, symbol: "sparkle") {
                            dictation.modeSwitcherVisible ? dictation.hideModeSwitcher() : dictation.showModeSwitcher()
                        }
                        pillButton(.record, symbol: "") { dictation.toggleFromMenu() }
                        pillButton(.expand, symbol: "arrow.up.left.and.arrow.down.right") { dictation.setExpanded(true) }
                    }
                    .padding(4)
                    .frame(width: 144, height: 40)
                    .background(Color(white: 0.045), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.13)))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Capsule()
                        .fill(Color(white: 0.05).opacity(0.5))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1.4))
                        .frame(width: 46, height: 9)
                        .padding(.top, 3)
                        .padding(.bottom, 9)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                guard !ProcessInfo.processInfo.arguments.contains("-forceHover") else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    hovering = inside
                    if !inside { hovered = nil }
                }
            }

            if hovering, !dictation.modeSwitcherVisible, let hovered {
                HStack(spacing: 9) {
                    Text(hovered.tip)
                        .foregroundStyle(.white.opacity(0.88))
                    if !hovered.keys.isEmpty {
                        Text(hovered.keys.joined(separator: " "))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .font(.system(size: 13))
                .padding(.leading, 12)
                .padding(.trailing, hovered.keys.isEmpty ? 12 : 8)
                .frame(height: 40)
                .background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
    }

    private func pillButton(_ action: PillAction, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Group {
                if symbol.isEmpty {
                    LogoMark(lineWidth: 2.8)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.8, lineJoin: .round))
                        .frame(width: 19, height: 16)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
                .frame(width: 42, height: 31)
                .background(.white.opacity(hovered == action ? 0.18 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside { hovered = action } else if hovered == action { hovered = nil }
            }
        }
    }
}

private struct MiniRecorder: View {
    let dictation: Dictation
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            if hovering {
                Button {
                    dictation.toggleFromMenu()
                } label: {
                    Group {
                        if dictation.phase == .finishing {
                            Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold))
                        } else {
                            LogoMark(lineWidth: 1.8)
                                .stroke(style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                                .frame(width: 11, height: 10)
                        }
                    }
                        .foregroundStyle(Color(red: 1, green: 0.25, blue: 0.32))
                        .frame(width: 32, height: 21)
                        .background(Color(red: 0.34, green: 0.08, blue: 0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Stop recording")
                .padding(.leading, 3)
                .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
            Waveform(dictation: dictation, count: hovering ? 14 : 7, barWidth: 1.8, spacing: 2.2, maxHeight: 12)
                .frame(maxWidth: .infinity)
        }
        .frame(width: hovering ? 114 : 48, height: hovering ? 29 : 22)
        .background(Color(white: 0.04), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .contentShape(Capsule())
        .onHover { inside in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { hovering = inside }
        }
    }
}

private struct ClassicRecorder: View {
    let dictation: Dictation

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Minimize") {
                    dictation.setExpanded(false)
                }
                Spacer(minLength: 4)
                Button {
                    dictation.modeSwitcherVisible ? dictation.hideModeSwitcher() : dictation.showModeSwitcher()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "mic").font(.system(size: 10))
                        Text("Voice to text")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Change mode  ⌥⇧K")
                Spacer(minLength: 4)
                IconButton(symbol: "xmark", help: "Cancel  esc") { dictation.cancel() }
                Button {
                    dictation.toggleFromMenu()
                } label: {
                    Group {
                        if dictation.phase == .finishing {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 8, height: 8)
                        }
                    }
                    .frame(width: 24, height: 22)
                    .background(Color(red: 0.86, green: 0.2, blue: 0.24), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Stop  ⌥Space")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Waveform(dictation: dictation, count: 52, barWidth: 2, spacing: 2.4, maxHeight: 30)
                .frame(maxWidth: .infinity)
                .frame(height: 44)

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(dictation.transcript.isEmpty ? 0.45 : 0.92))
                .lineLimit(3)
                .truncationMode(.head)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .animation(.easeOut(duration: 0.15), value: dictation.transcript)
        }
        .frame(width: 320)
        .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private var caption: String {
        if !dictation.transcript.isEmpty { return dictation.transcript }
        return dictation.phase == .finishing ? "Transcribing…" : "Listening…"
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 22)
                .background(.white.opacity(hovering ? 0.16 : 0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct Waveform: View {
    let dictation: Dictation
    let count: Int
    let barWidth: CGFloat
    let spacing: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let levels = dictation.levels
            let finishing = dictation.phase == .finishing
            Canvas { context, size in
                let total = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
                var x = (size.width - total) / 2
                for index in 0..<count {
                    let height = barHeight(index: index, levels: levels, finishing: finishing, time: time)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(.white))
                    x += barWidth + spacing
                }
            }
        }
    }

    private func barHeight(index: Int, levels: [Float], finishing: Bool, time: TimeInterval) -> CGFloat {
        let minimum = barWidth
        let center = Double(count - 1) / 2
        let distance = abs(Double(index) - center) / max(center, 1)
        let envelope = 1 - distance * 0.55
        if finishing {
            let wave = (sin(time * 7 - Double(index) * 0.55) + 1) / 2
            return minimum + CGFloat(wave * envelope) * maxHeight * 0.45
        }
        let offset = Int(distance * Double(levels.count - 1))
        let sample = levels[max(levels.count - 1 - offset, 0)]
        let value = Double(sample) * envelope
        return minimum + CGFloat(value) * (maxHeight - minimum)
    }
}

struct LogoMark: Shape {
    var lineWidth: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let r = rect.insetBy(dx: inset, dy: inset)
        let top = CGPoint(x: r.midX, y: r.minY)
        let left = CGPoint(x: r.minX, y: r.maxY)
        let right = CGPoint(x: r.maxX, y: r.maxY)
        let radius = min(r.width, r.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: (left.x + right.x) / 2, y: r.maxY))
        path.addArc(tangent1End: right, tangent2End: top, radius: radius)
        path.addArc(tangent1End: top, tangent2End: left, radius: radius)
        path.addArc(tangent1End: left, tangent2End: right, radius: radius)
        path.closeSubpath()
        return path
    }
}
