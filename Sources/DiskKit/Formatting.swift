import Foundation

/// Formats a byte count the way the design does: `1.4 GB`, `820 MB`, `12 KB`.
public func formatSize(_ bytes: Int64) -> String {
    let kb = 1024.0
    let mb = kb * 1024
    let gb = mb * 1024
    let tb = gb * 1024
    let b = Double(bytes)
    if b >= tb { return String(format: "%.1f TB", b / tb) }
    if b >= gb { return String(format: "%.1f GB", b / gb) }
    if b >= mb { return String(format: "%.0f MB", (b / mb).rounded()) }
    if b >= kb { return String(format: "%.0f KB", (b / kb).rounded()) }
    return bytes <= 0 ? "0 KB" : "\(max(1, bytes / 1024)) KB"
}

/// One-decimal percentage of `part` within `whole`.
public func percent(_ part: Int64, of whole: Int64) -> Double {
    whole > 0 ? (Double(part) / Double(whole) * 1000).rounded() / 10 : 0
}
