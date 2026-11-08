import Foundation

struct AnalysisEvent {
    let name: String
    let data: Data
}

/// The private API emits exactly one JSON data line per event. Foundation's
/// AsyncBytes.lines may omit blank separators, so dispatch on the data line itself.
struct AnalysisEventParser {
    private var pendingName = ""

    mutating func consume(_ rawLine: String) throws -> AnalysisEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty || line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            pendingName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:"), !pendingName.isEmpty else { return nil }
        let text = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard text.utf8.count <= 100_000 else { throw ParseError.oversized }
        defer { pendingName = "" }
        return AnalysisEvent(name: pendingName, data: Data(text.utf8))
    }

    enum ParseError: LocalizedError {
        case oversized
        var errorDescription: String? { "AI 结果过大，请重新分析。" }
    }
}
