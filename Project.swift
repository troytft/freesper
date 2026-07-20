import ProjectDescription

let version = Environment.version.getString(default: "0.0.0")
let sentryDSN = Environment.sentryDSN.getString(default: "")
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
            bundleId: "me.troytft.freesper",
            deploymentTargets: .macOS("14.0"),
            // Not .extendingDefault: it injects NSMainStoryboardFile, fatal under Sentry's NSException handler.
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundlePackageType": "APPL",
                "CFBundleName": "Freesper",
                "CFBundleDisplayName": "$(APP_DISPLAY_NAME)",
                "CFBundleShortVersionString": .string(version),
                "CFBundleVersion": .string(version),
                "CFBundleIconName": "AppIcon",
                "LSMinimumSystemVersion": "14.0",
                "LSUIElement": true,
                "NSPrincipalClass": "NSApplication",
                "NSMicrophoneUsageDescription": "Freesper uses the microphone to capture speech and convert it to text.",
                "SUFeedURL": "$(SPARKLE_FEED_URL)",
                "SUPublicEDKey": "5nJWhGe7diYZtxoGYGYlfc0DrFINJGfmWK/tC3Wq4ys=",
                "SentryDSN": .string(sentryDSN),
            ]),
            sources: ["Sources/Freesper/**"],
            resources: ["AppIcon.icon", "Assets.xcassets"],
            entitlements: .dictionary([
                "com.apple.security.app-sandbox": false,
                "com.apple.security.device.audio-input": true,
            ]),
            dependencies: [
                .external(name: "FluidAudio"),
                .external(name: "Sparkle"),
                .external(name: "Sentry"),
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
                ],
                configurations: [
                    .debug(
                        name: "Debug",
                        settings: [
                            "PRODUCT_BUNDLE_IDENTIFIER": "me.troytft.freesper.dev",
                            "APP_DISPLAY_NAME": "Freesper Dev",
                            "SPARKLE_FEED_URL": "",
                        ]
                    ),
                    .release(
                        name: "Release",
                        settings: [
                            "PRODUCT_BUNDLE_IDENTIFIER": "me.troytft.freesper",
                            "APP_DISPLAY_NAME": "Freesper",
                            "SPARKLE_FEED_URL":
                                "https://github.com/troytft/freesper/releases/latest/download/appcast.xml",
                        ]
                    ),
                ]
            )
        ),
    ]
)
