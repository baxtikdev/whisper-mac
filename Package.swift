// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Whisper",
            path: "Sources/Whisper",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
