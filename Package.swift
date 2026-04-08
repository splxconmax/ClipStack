// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ClipStackCore",
            targets: ["ClipStackCore"]
        ),
        .executable(
            name: "ClipStack",
            targets: ["ClipStackApp"]
        ),
        .executable(
            name: "ClipStackChecks",
            targets: ["ClipStackChecks"]
        ),
    ],
    targets: [
        .target(
            name: "ClipStackCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "ClipStackApp",
            dependencies: ["ClipStackCore"]
        ),
        .executableTarget(
            name: "ClipStackChecks",
            dependencies: ["ClipStackCore"]
        ),
    ]
)
