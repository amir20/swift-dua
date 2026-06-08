import PackagePlugin
import Foundation

/// `swift package bundle-app`
///
/// Builds the executable in release mode and assembles it into a
/// double-clickable macOS `.app` bundle in the package root.
@main
struct BundleApp: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let appName = "ProgressApp"
        let displayName = "Progress Demo"
        let bundleID = "com.example.\(appName)"

        // 1. Build the executable in release mode.
        Diagnostics.remark("Building \(appName) (release)…")
        let build = try packageManager.build(
            .product(appName),
            parameters: .init(configuration: .release)
        )
        guard build.succeeded else {
            Diagnostics.error("Build failed:\n\(build.logText)")
            return
        }
        guard let binary = build.builtArtifacts.first(where: { $0.kind == .executable })?.path else {
            Diagnostics.error("Could not locate the built executable.")
            return
        }

        // 2. Assemble the .app bundle layout in the package root.
        let fm = FileManager.default
        let root = context.package.directory
        let bundle = root.appending("\(appName).app")
        let macOSDir = bundle.appending("Contents").appending("MacOS")
        let resourcesDir = bundle.appending("Contents").appending("Resources")

        try? fm.removeItem(atPath: bundle.string)
        try fm.createDirectory(atPath: macOSDir.string, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: resourcesDir.string, withIntermediateDirectories: true)
        try fm.copyItem(atPath: binary.string, toPath: macOSDir.appending(appName).string)

        // 3. Write Info.plist.
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>\(appName)</string>
            <key>CFBundleDisplayName</key>
            <string>\(displayName)</string>
            <key>CFBundleIdentifier</key>
            <string>\(bundleID)</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleExecutable</key>
            <string>\(appName)</string>
            <key>LSMinimumSystemVersion</key>
            <string>14.0</string>
            <key>NSHighResolutionCapable</key>
            <true/>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
        </dict>
        </plist>
        """
        try infoPlist.write(
            toFile: bundle.appending("Contents").appending("Info.plist").string,
            atomically: true,
            encoding: .utf8
        )

        // 4. Ad-hoc code signature so Gatekeeper allows local launch.
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--deep", "--sign", "-", bundle.string]
        try? codesign.run()
        codesign.waitUntilExit()

        Diagnostics.remark("Created \(bundle.string)")
        print("✅ Built \(appName).app — open it with:  open \(appName).app")
    }
}
