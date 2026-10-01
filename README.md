# Whisper

A native macOS menu bar dictation app. Hold or tap a hotkey, speak, and the text is typed into whatever app you are using. Transcription runs on ElevenLabs Scribe v2 Realtime with your own API key, with first-class support for Uzbek.

## Features

- **Push to talk or toggle**: hold `⌥ Space` to dictate, or tap it to start and tap again to stop. `esc` cancels.
- **Realtime transcription**: words appear while you speak (ElevenLabs Scribe v2 Realtime / Turbo / Lite, 90+ languages).
- **Auto paste**: the result is pasted at the cursor and your clipboard is restored afterwards.
- **Uzbek Latin output**: Cyrillic Uzbek is converted to Latin script automatically (`o‘`, `g‘`, `sh`, `ch`).
- **Recorder overlay**: a minimal pill at the top of the screen with a live waveform, hover controls, a mode switcher (`⌥⇧K`) and an expanded window with stop / cancel.
- **Vocabulary and replacements**: bias recognition toward your own terms and auto-replace words after every dictation.
- **History and stats**: words, average WPM, apps used and time saved.
- **Bring your own key**: no account, no subscription; the key is stored locally with `0600` permissions.

## Requirements

- macOS 15 or later
- Swift 6.2 toolchain (Xcode or Command Line Tools)
- An [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys) with the Speech to Text permission

## Build and install

```sh
./build.sh            # builds build.noindex/Whisper.app
./build.sh --install  # installs to /Applications and launches it
```

The build script creates a self-signed code signing certificate on first run so macOS keeps the Microphone and Accessibility permissions across rebuilds.

On first launch:

1. Open **Models library** and add your ElevenLabs API key.
2. Grant **Microphone** access when asked.
3. Grant **Accessibility** access (Configuration → Permissions) so the text can be pasted for you.

## Local customization

`build.sh` reads optional overrides from `~/Library/Application Support/Whisper/Brand/`, which never enter the repository:

| File | Effect |
|---|---|
| `name` | App display name and installed bundle name |
| `bundle-id` | Bundle identifier |
| `icon-1024.png` | App icon |
| `menubar/IconReady@2x.png`, `IconRecording@2x.png`, `IconWorking@2x.png` | Menu bar template icons |

Custom sound effects can be placed in `~/Library/Application Support/Whisper/Sounds/` as `Start.m4a`, `Stop.m4a`, `StartClassic.m4a`, `StopClassic.m4a`, `NotificationError.m4a` and `noResult1.m4a`; system sounds are used otherwise.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/Whisper/Dictation.swift` | Recording state machine, hotkeys, paste |
| `Sources/Whisper/ScribeClient.swift` | ElevenLabs realtime WebSocket client |
| `Sources/Whisper/AudioCapture.swift` | Microphone capture and 16 kHz PCM conversion |
| `Sources/Whisper/Overlay.swift` | Recorder pill and expanded window |
| `Sources/Whisper/MainWindow.swift` | Settings, history, vocabulary UI |
| `Scripts/make-icon.swift` | Renders the default app icon |

## License

[MIT](LICENSE)
