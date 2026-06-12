// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Halo", targets: ["Halo"]),
        .library(name: "DiskKit", targets: ["DiskKit"]),
    ],
    dependencies: [
        // Auto-update. The only external dependency — replacing a running,
        // translocated app bundle in place is exactly the problem Sparkle
        // solves; see https://sparkle-project.org. DiskKit stays dependency-free.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        // Disk-scanning model behind the Halo GUI: a classified directory tree
        // built from a real, parallel filesystem walk.
        .target(
            name: "DiskKit",
            path: "Sources/DiskKit"
        ),
        // "Halo" — a SwiftUI donut disk visualizer built on DiskKit.
        .executableTarget(
            name: "Halo",
            dependencies: [
                "DiskKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Halo"
        ),
        .testTarget(
            name: "DiskKitTests",
            dependencies: ["DiskKit"],
            path: "Tests/DiskKitTests"
        ),
        .testTarget(
            name: "HaloTests",
            dependencies: ["Halo", "DiskKit"],
            path: "Tests/HaloTests"
        ),
        .plugin(
            name: "BundleApp",
            capability: .command(
                intent: .custom(
                    verb: "bundle-app",
                    description:
                        "Build a release binary and package it into a double-clickable .app bundle"
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Write the generated .app bundle into the project directory"
                    )
                ]
            )
        ),
    ]
)
