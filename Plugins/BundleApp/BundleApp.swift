import PackagePlugin
import Foundation

/// `swift package bundle-app`
///
/// Builds the executable in release mode and assembles it into a
/// double-clickable macOS `.app` bundle in the package root.
@main
struct BundleApp: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Product to bundle: first non-flag argument, defaulting to Halo.
        let appName = arguments.first { !$0.hasPrefix("-") } ?? "Halo"
        let displayName = appName
        // Bundle identifier and signing identity are overridable from the
        // environment so CI can inject release values; both fall back to local
        // defaults (ad-hoc signing, "-", needs no certificate).
        let env = ProcessInfo.processInfo.environment
        let bundleID = env["BUNDLE_ID"] ?? "me.amirraminfar.\(appName.lowercased())"
        let signIdentity = env["SIGN_IDENTITY"].flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        // Marketing/build version, injected by CI from the release tag
        // (v1.2.3 -> 1.2.3). Local builds default to 0.0.0 so a dev bundle
        // never looks newer than a real release to Sparkle.
        let version = env["VERSION"].flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0"

        // Sparkle auto-update: where installed copies look for new releases,
        // and the public half of the EdDSA key updates are signed with in CI
        // (private half lives in the SPARKLE_PRIVATE_KEY GitHub secret).
        let feedURL = "https://github.com/amir20/Halo.app/releases/latest/download/appcast.xml"
        let publicEDKey = "fRWUpysh3o8jnC2aj7k0HvZX2eTkC2pwwvB4H/N4uRw="

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
        guard let binary = build.builtArtifacts.first(where: { $0.kind == .executable })?.url else {
            Diagnostics.error("Could not locate the built executable.")
            return
        }

        // 2. Assemble the .app bundle layout in the package root.
        let fm = FileManager.default
        let root = context.package.directoryURL
        let bundle = root.appending(component: "\(appName).app")
        let macOSDir = bundle.appending(component: "Contents").appending(component: "MacOS")
        let resourcesDir = bundle.appending(component: "Contents").appending(component: "Resources")
        let frameworksDir = bundle.appending(component: "Contents").appending(component: "Frameworks")

        try? fm.removeItem(at: bundle)
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
        let bundledBinary = macOSDir.appending(component: appName)
        try fm.copyItem(at: binary, to: bundledBinary)

        // 2a. Embed Sparkle.framework. SwiftPM places the framework next to
        // the built binary; the binary references it as @rpath/Sparkle… with
        // only a @loader_path rpath (right for the flat build dir, wrong for
        // a bundle), so add the conventional Frameworks rpath too.
        let sparkleSrc = binary.deletingLastPathComponent()
            .appending(component: "Sparkle.framework")
        guard fm.fileExists(atPath: sparkleSrc.path(percentEncoded: false)) else {
            Diagnostics.error("Sparkle.framework not found next to the built binary at \(sparkleSrc.path(percentEncoded: false)).")
            return
        }
        try fm.copyItem(at: sparkleSrc, to: frameworksDir.appending(component: "Sparkle.framework"))
        guard run("/usr/bin/install_name_tool",
                  ["-add_rpath", "@executable_path/../Frameworks",
                   bundledBinary.path(percentEncoded: false)]) == 0 else {
            Diagnostics.error("install_name_tool failed to add the Frameworks rpath.")
            return
        }

        // 2b. App icon: copy Icons/AppIcon.icns into Resources (if present).
        let iconSrc = root.appending(component: "Icons").appending(component: "AppIcon.icns")
        let hasIcon = fm.fileExists(atPath: iconSrc.path(percentEncoded: false))
        if hasIcon {
            try fm.copyItem(at: iconSrc,
                            to: resourcesDir.appending(component: "AppIcon.icns"))
        }

        // 3. Write Info.plist as a compiled *binary* property list — the format
        // Xcode actually ships — built from typed data instead of an XML string.
        var info: [String: Any] = [
            "CFBundleName": appName,
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": bundleID,
            "CFBundleVersion": version,
            "CFBundleShortVersionString": version,
            "SUFeedURL": feedURL,
            "SUPublicEDKey": publicEDKey,
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": appName,
            "LSMinimumSystemVersion": "26.0",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
        ]
        if hasIcon {
            info["CFBundleIconFile"] = "AppIcon"
            info["CFBundleIconName"] = "AppIcon"
        }
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        try infoData.write(to: bundle.appending(component: "Contents").appending(component: "Info.plist"))

        // 4. Code signatures. With SIGN_IDENTITY set (a "Developer ID
        //    Application: …" identity) produce a real, distributable signature:
        //    hardened runtime + secure timestamp, both required by notarization.
        //    Unset, it ad-hoc signs ("-") so a local build runs without a cert.
        //
        //    Sparkle's nested executables ship signed by the Sparkle project's
        //    team; the hardened runtime's library validation only loads code
        //    signed by *our* team (or Apple), so every nested component is
        //    re-signed with our identity, deepest first, before the app seal.
        //    Downloader.xpc is sandboxed — its entitlements must survive the
        //    re-sign or in-app downloads break.
        func codesign(_ item: URL, preserveEntitlements: Bool = false) -> Bool {
            var args = ["--force", "--sign", signIdentity]
            if signIdentity != "-" {
                args += ["--options", "runtime", "--timestamp"]
            }
            if preserveEntitlements {
                args.append("--preserve-metadata=entitlements")
            }
            args.append(item.path(percentEncoded: false))
            return run("/usr/bin/codesign", args) == 0
        }

        let sparkle = frameworksDir.appending(component: "Sparkle.framework")
        let sparkleB = sparkle.appending(component: "Versions").appending(component: "B")
        let xpcServices = sparkleB.appending(component: "XPCServices")
        let nested: [(URL, Bool)] = [
            (xpcServices.appending(component: "Downloader.xpc"), true),
            (xpcServices.appending(component: "Installer.xpc"), true),
            (sparkleB.appending(component: "Autoupdate"), false),
            (sparkleB.appending(component: "Updater.app"), false),
            (sparkle, false),
        ]
        for (item, preserveEntitlements) in nested {
            guard codesign(item, preserveEntitlements: preserveEntitlements) else {
                Diagnostics.error("codesign failed on \(item.lastPathComponent) (identity: \(signIdentity)).")
                return
            }
        }
        guard codesign(bundle) else {
            Diagnostics.error("codesign failed (identity: \(signIdentity)).")
            return
        }

        Diagnostics.remark("Created \(bundle.path(percentEncoded: false))")
        print("✅ Built \(appName).app — open it with:  open \(appName).app")
    }

    /// Runs a command-line tool to completion; returns its exit status.
    private func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
