import Foundation
import ArgumentParser
#if canImport(Darwin)
import Darwin
#endif

@main
struct Duaswift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duaswift",
        abstract: "A tiny Swift reimplementation of `dua aggregate`.",
        discussion: "With no PATH, aggregates each entry in the current directory."
    )

    @Flag(name: [.customShort("A"), .long],
          help: "Use apparent size (st_size) instead of disk usage.")
    var apparentSize = false

    @Flag(name: [.customShort("l"), .long],
          help: "Count hard-linked files each time they are seen.")
    var countHardLinks = false

    @Option(name: [.short, .long],
            help: "Worker threads (default: logical CPU count).")
    var threads = ProcessInfo.processInfo.activeProcessorCount

    @Option(name: [.short, .long],
            help: "Byte format: metric or bytes.")
    var format: ByteFormat = .metric

    @Flag(name: .customLong("no-progress"),
          help: "Disable the live progress line on stderr.")
    var noProgress = false

    @Argument(help: "Paths to aggregate (default: entries of the current directory).")
    var paths: [String] = []

    func run() throws {
        let threadCount = max(1, threads)

        var inputs = paths
        if inputs.isEmpty {
            let cwd = FileManager.default.currentDirectoryPath
            inputs = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?.sorted() ?? ["."]
        }

        // Show live progress only when stderr is an interactive terminal.
        let showProgress = !noProgress && isatty(STDERR_FILENO) != 0
        let counter = showProgress ? ProgressCounter() : nil
        let monitor = counter.map { ProgressMonitor(counter: $0) }

        let scanner = DiskScanner(apparent: apparentSize,
                                  countHardLinks: countHardLinks,
                                  threadCount: threadCount,
                                  progress: counter)

        monitor?.begin()
        var results: [(path: String, size: Int64)] = []
        var grandTotal: Int64 = 0
        for input in inputs {
            let r = scanner.scan(input)
            results.append((input, r.size))
            grandTotal += r.size
        }
        monitor?.finish()

        results.sort { $0.size < $1.size }   // ascending, like dua

        let width = max(10, results.map { renderSize($0.size, format: format).count }.max() ?? 10)
        for r in results {
            print("\(leftPad(renderSize(r.size, format: format), to: width)) \(r.path)")
        }
        if results.count > 1 {
            print("\(leftPad(renderSize(grandTotal, format: format), to: width)) total")
        }
    }
}
