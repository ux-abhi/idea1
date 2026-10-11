// swift-tools-version: 6.2
// © Pexilim
import PackageDescription

// BlinkKit: no default isolation (CLAUDE.md, ARCHITECTURE §36.1).
let package = Package(
    name: "BlinkKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "BlinkKit", targets: ["BlinkKit"])],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.3"),
    ],
    targets: [
        .target(name: "BlinkKit", dependencies: [.product(name: "Supabase", package: "supabase-swift")]),
        .testTarget(name: "BlinkKitTests", dependencies: ["BlinkKit"]),
    ]
)
