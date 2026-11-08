import Foundation

/// Reads and writes detector events as JSON lines: one event per line, dates as seconds since
/// 1970. The debug timeline exports this format, and replay tests read it back
/// (Phase 0 §3.6).
public enum EventLog {
    public static func encode(_ events: [DetectionEvent]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try events.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
    }

    public static func decode(_ text: String) throws -> [DetectionEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try text.split(whereSeparator: \.isNewline)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .map { try decoder.decode(DetectionEvent.self, from: Data($0.utf8)) }
    }
}
