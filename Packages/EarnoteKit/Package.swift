// swift-tools-version: 6.2
import PackageDescription

// Abhängigkeitsregeln (siehe docs/ARCHITECTURE.md):
// - EarnoteCore: nur Apple-Frameworks ohne Oberfläche (Foundation, AVFoundation, Security, OSLog, Observation).
//   Kein AppKit/UIKit/SwiftUI, keine Drittanbieter-Pakete – läuft auf Mac und iPad.
// - EarnoteML: EarnoteCore + WhisperKit/MLX (lokale Transkription und lokales Sprachmodell).
let package = Package(
    name: "EarnoteKit",
    platforms: [.macOS("14.4"), .iOS("26.0")],
    products: [
        .library(name: "EarnoteCore", targets: ["EarnoteCore"]),
        .library(name: "EarnoteML", targets: ["EarnoteML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.1.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "EarnoteCore"),
        .target(
            name: "EarnoteML",
            dependencies: [
                "EarnoteCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]),
        .testTarget(name: "EarnoteCoreTests", dependencies: ["EarnoteCore"]),
    ],
    // Swift-6-Sprachmodus folgt später; neuer Code ist trotzdem Sendable-sauber geschrieben.
    swiftLanguageModes: [.v5]
)
