// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SoloVolume",
    platforms: [.macOS("14.2")],
    dependencies: [
        // In-app updates from GitHub Releases ("Check for Updates…"). Pinned to one version;
        // SwiftPM checks the binary's checksum in Package.resolved.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "SoloVolume",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources",
            linkerSettings: [
                // Sparkle.framework is copied into Contents/Frameworks by build.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
