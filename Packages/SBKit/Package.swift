// swift-tools-version: 6.0
import PackageDescription

// Every module of the app except the app and extension targets themselves.
// The dependency graph runs one way: Core <- Store/Safety <- ScanEngine and the feature modules.
let package = Package(
    name: "SBKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Store", targets: ["Store"]),
        .library(name: "Safety", targets: ["Safety"]),
        .library(name: "ScanEngine", targets: ["ScanEngine"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Media", targets: ["Media"]),
        .library(name: "Reveal", targets: ["Reveal"]),
        .library(name: "Triage", targets: ["Triage"]),
        .library(name: "Actions", targets: ["Actions"]),
        .library(name: "Notifications", targets: ["Notifications"]),
        .library(name: "Paywall", targets: ["Paywall"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK.git", from: "2.0.0"),
        // Nudity filter: a 17 kB Core ML model, BSD-3-Clause. See LICENSES.md.
        .package(url: "https://github.com/lovoo/NSFWDetector.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [.product(name: "TelemetryDeck", package: "SwiftSDK")]
        ),
        .target(
            name: "Store",
            dependencies: ["Core", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "Safety", dependencies: ["Core", .product(name: "NSFWDetector", package: "NSFWDetector")]),
        .target(name: "ScanEngine", dependencies: ["Core", "Store", "Safety"]),
        .target(name: "DesignSystem", dependencies: ["Core"]),
        .target(name: "Media", dependencies: ["Core"]),
        .target(name: "Reveal", dependencies: ["Core", "Store", "Safety", "DesignSystem", "Media"]),
        .target(name: "Triage", dependencies: ["Core", "Store", "DesignSystem"]),
        .target(name: "Actions", dependencies: ["Core", "Store"]),
        .target(name: "Notifications", dependencies: ["Core", "Store"]),
        .target(name: "Paywall", dependencies: ["Core", "DesignSystem"]),

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "SafetyTests", dependencies: ["Safety"]),
        .testTarget(name: "RevealTests", dependencies: ["Reveal", "Store"]),
        .testTarget(name: "ScanEngineTests", dependencies: ["ScanEngine", "Store", "Safety"]),
        .testTarget(
            name: "StoreTests",
            dependencies: ["Store", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
