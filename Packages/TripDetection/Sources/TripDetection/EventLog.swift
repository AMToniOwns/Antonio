import Foundation

/// Reads and writes detector events as JSON lines: one event per line, dates as seconds since
/// 1970. The debug timeline exports this format, and replay tests read it back
/// (Phase 0 §3.6). A session log starts with the restored state, so a replay begins exactly
/// where the phone did.
public enum EventLog {
    public enum Line: Codable, Sendable, Equatable {
        case state(DetectorState)
        case event(DetectionEvent)
    }

    public static func encode(session state: DetectorState, events: [DetectionEvent]) throws -> String {
        try encodeLines([.state(state)] + events.map(Line.event))
    }

    /// The restored state (if the log has one) and the events after it.
    public static func decodeSession(_ text: String) throws -> (state: DetectorState?, events: [DetectionEvent]) {
        var state: DetectorState?
        var events: [DetectionEvent] = []
        for line in try decodeLines(text) {
            switch line {
            case let .state(s): if events.isEmpty { state = s }
            case let .event(e): events.append(e)
            }
        }
        return (state, events)
    }

    static func encodeLines(_ lines: [Line]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try lines.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n")
    }

    static func decodeLines(_ text: String) throws -> [Line] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try text.split(whereSeparator: \.isNewline)
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .map { try decoder.decode(Line.self, from: Data($0.utf8)) }
    }

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
