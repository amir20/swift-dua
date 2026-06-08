import Foundation

let helpText = """
duaswift — a tiny Swift reimplementation of `dua aggregate`

USAGE:
    duaswift [OPTIONS] [PATH...]

    With no PATH, aggregates each entry in the current directory.

OPTIONS:
    -A, --apparent-size       Use apparent size (st_size) instead of disk usage
    -l, --count-hard-links    Count hard-linked files each time they are seen
    -t, --threads <N>         Worker threads (default: logical CPU count)
    -f, --format <FMT>        Byte format: metric (default) or bytes
    -h, --help                Print this help
"""

// MARK: - Argument parsing

var apparent = false
var countHardLinks = false
var format = "metric"
var threads = ProcessInfo.processInfo.activeProcessorCount
var inputs: [String] = []

let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "-A", "--apparent-size": apparent = true
    case "-l", "--count-hard-links": countHardLinks = true
    case "-f", "--format":
        i += 1
        if i < args.count { format = args[i] }
    case "-t", "--threads":
        i += 1
        if i < args.count, let n = Int(args[i]) { threads = max(1, n) }
    case "-h", "--help":
        print(helpText)
        exit(0)
    default:
        inputs.append(args[i])
    }
    i += 1
}

if inputs.isEmpty {
    let cwd = FileManager.default.currentDirectoryPath
    inputs = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?.sorted() ?? ["."]
}

// MARK: - Formatting

func formatMetric(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1000 && unit < units.count - 1 {
        value /= 1000
        unit += 1
    }
    return unit == 0 ? "\(bytes) B" : String(format: "%.2f %@", value, units[unit])
}

func renderSize(_ bytes: Int64) -> String {
    format == "bytes" ? "\(bytes) b" : formatMetric(bytes)
}

func leftPad(_ s: String, to width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

// MARK: - Run

let scanner = DiskScanner(apparent: apparent, countHardLinks: countHardLinks, threadCount: threads)

var results: [(path: String, size: Int64)] = []
var grandTotal: Int64 = 0
for input in inputs {
    let r = scanner.scan(input)
    results.append((input, r.size))
    grandTotal += r.size
}

results.sort { $0.size < $1.size }   // ascending, like dua

let width = max(10, results.map { renderSize($0.size).count }.max() ?? 10)
for r in results {
    print("\(leftPad(renderSize(r.size), to: width)) \(r.path)")
}
if results.count > 1 {
    print("\(leftPad(renderSize(grandTotal), to: width)) total")
}
