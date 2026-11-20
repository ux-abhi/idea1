// swift-tools-version: 6.2
// Blink's natural voice: Kokoro-82M (Apache-2.0) through KokoroSwift (MIT) on MLX Swift (MIT), on the Mac's GPU.
// Its own package so BlinkKit and its tests stay free of the speech engine. Built with Xcode (MLX's Metal kernels).
import PackageDescription

let package = Package(
    name: "BlinkVoice",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "BlinkVoice", targets: ["BlinkVoice"])],
    dependencies: [
        .package(url: "https://github.com/mlalma/kokoro-ios.git", exact: "1.0.11"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
    ],
    targets: [
        .target(
            name: "BlinkVoice",
            dependencies: [.product(name: "KokoroSwift", package: "kokoro-ios"),
                           .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                           .product(name: "MLX", package: "mlx-swift")],
            resources: [.copy("Resources/voices.npz")]
        ),
    ]
)
