import ProjectDescription

let developmentTeam = Environment.developmentTeam.getString(default: "")
let codeSignIdentity = Environment.codeSignIdentity.getString(default: "Apple Development")
let codeSigningAllowed = Environment.codeSigningAllowed.getString(default: "YES")
let codeSigningRequired = Environment.codeSigningRequired.getString(default: "YES")

let project = Project(
    name: "Freesper",
    organizationName: "Freesper",
    options: .options(
        defaultKnownRegions: ["en", "ru"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "CODE_SIGN_STYLE": "Manual",
            "DEVELOPMENT_TEAM": .string(developmentTeam),
            "CODE_SIGN_IDENTITY": .string(codeSignIdentity),
            "CODE_SIGNING_ALLOWED": .string(codeSigningAllowed),
            "CODE_SIGNING_REQUIRED": .string(codeSigningRequired),
            "PROVISIONING_PROFILE_SPECIFIER": "",
            "ARCHS": "arm64",
            "ONLY_ACTIVE_ARCH": "YES",
            "DEAD_CODE_STRIPPING": "YES",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "Freesper",
            destinations: [.mac],
            product: .app,
            bundleId: "com.freesper.app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleName": "Freesper",
                "CFBundleDisplayName": "Freesper",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "CFBundleIconName": "AppIcon",
                "LSMinimumSystemVersion": "14.0",
                "LSUIElement": true,
                "NSMicrophoneUsageDescription": "Freesper uses the microphone to capture speech and convert it to text.",
            ]),
            sources: ["Sources/Freesper/**"],
            resources: ["AppIcon.icon", "Assets.xcassets"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": false,
                "com.apple.security.device.audio-input": true,
            ]),
            dependencies: [
                .external(name: "FluidAudio"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_STYLE": "Manual",
                    "CODE_SIGN_IDENTITY": .string(codeSignIdentity),
                    "CODE_SIGNING_ALLOWED": .string(codeSigningAllowed),
                    "CODE_SIGNING_REQUIRED": .string(codeSigningRequired),
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                    "PROVISIONING_PROFILE_SPECIFIER": "",
                    "OTHER_LDFLAGS": ["$(inherited)", "-lc++"],
                ]
            )
        ),
    ]
)
