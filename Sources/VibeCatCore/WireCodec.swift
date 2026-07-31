import Foundation

/// Newline-delimited JSON. One message per line, so a reader can frame a stream
/// without a length prefix and a human can read the traffic in a log.
public enum WireCodec {
    static let newline = UInt8(ascii: "\n")

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted keys make encoded output stable, which makes tests and logs readable.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(newline)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let line = data.last == newline ? data.dropLast() : data[...]
        return try JSONDecoder().decode(type, from: Data(line))
    }

    /// Pulls every complete line out of `buffer`, leaving any partial tail behind
    /// for the next read.
    public static func splitLines(_ buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: newline) {
            lines.append(Data(buffer[buffer.startIndex..<idx]))
            buffer = Data(buffer[buffer.index(after: idx)...])
        }
        return lines
    }
}
