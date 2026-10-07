// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexIsland", targets: ["CodexIsland"])
    ],
    targets: [
        .executableTarget(
            name: "CodexIsland",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "CodexIslandTests",
            dependencies: ["CodexIsland"]
        )
    ],
    swiftLanguageModes: [.v6]
)
