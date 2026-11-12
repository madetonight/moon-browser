// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Moon",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Moon", targets: ["Moon"]), .executable(name: "MoonCodexBridge", targets: ["MoonCodexBridge"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "MoonCore"),
        .executableTarget(name: "MoonCodexBridge", dependencies: ["MoonCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Moon", dependencies: ["MoonCore", .product(name: "Sparkle", package: "Sparkle")], path: "Sources/Moon", swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Osize"], .when(configuration: .release))], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MoonCoreTests", dependencies: ["MoonCore"]),
        .testTarget(name: "MoonPortTests", dependencies: ["Moon"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
