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
    ]
)
