// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProgressApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ProgressApp", targets: ["ProgressApp"]),
        .executable(name: "duaswift", targets: ["duaswift"])
    ],
    targets: [
        .executableTarget(
            name: "ProgressApp",
            path: "Sources/ProgressApp"
        ),
        .executableTarget(
            name: "duaswift",
            path: "Sources/duaswift"
        ),
        .plugin(
            name: "BundleApp",
            capability: .command(
                intent: .custom(
                    verb: "bundle-app",
                    description: "Build a release binary and package it into a double-clickable .app bundle"
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Write the generated ProgressApp.app bundle into the project directory"
                    )
                ]
            )
        )
    ]
)
