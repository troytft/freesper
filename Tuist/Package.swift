// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [:]
    )
#endif

let package = Package(
    name: "OpenWhisper",
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.14.4"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.22.0"),
    ]
)
