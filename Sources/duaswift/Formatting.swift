import Foundation
import ArgumentParser

/// Byte-size output format selected by `--format`.
enum ByteFormat: String, ExpressibleByArgument {
    case metric
    case bytes
}

// MARK: - Output formatting helpers

/// Inserts thousands separators: 1234567 -> "1,234,567".
func grouped(_ n: Int) -> String {
    let digits = String(n)
    guard n >= 1000 else { return digits }
    var out = ""
    var count = 0
    for ch in digits.reversed() {
        if count != 0 && count % 3 == 0 { out.append(",") }
        out.append(ch)
        count += 1
    }
    return String(out.reversed())
}

/// Truncates a path to `max` characters, prefixing an ellipsis when shortened.
func truncatePath(_ path: String, max: Int = 44) -> String {
    guard path.count > max else { return path }
    return "…" + path.suffix(max - 1)
}

/// Human-readable metric byte size (1.00 KB, 1.50 MB, …); raw bytes under 1000.
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

/// Renders a size in the chosen format.
func renderSize(_ bytes: Int64, format: ByteFormat) -> String {
    switch format {
    case .bytes:  return "\(bytes) b"
    case .metric: return formatMetric(bytes)
    }
}

/// Right-aligns `s` within `width` columns.
func leftPad(_ s: String, to width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}
