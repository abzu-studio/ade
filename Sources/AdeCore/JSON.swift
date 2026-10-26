import CoreFoundation
import Foundation

public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public static func parse(_ data: Data) throws -> JSONValue {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return from(any)
    }

    public static func fromEncodable<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try parse(encoder.encode(value))
    }

    static func from(_ any: Any) -> JSONValue {
        if any is NSNull { return .null }
        if let value = any as? String { return .string(value) }
        if let value = any as? [Any] { return .array(value.map(from)) }
        if let value = any as? [String: Any] {
            return .object(value.mapValues(from))
        }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            if double.isFinite, double.rounded() == double, abs(double) <= Double(Int.max) {
                return .int(number.intValue)
            }
            return .double(double)
        }
        return .null
    }

    public func strippingUpdatedAt() -> JSONValue {
        switch self {
        case .array(let items):
            return .array(items.map { $0.strippingUpdatedAt() })
        case .object(let fields):
            var next: [String: JSONValue] = [:]
            for (key, value) in fields where key != "updatedAt" {
                next[key] = value.strippingUpdatedAt()
            }
            return .object(next)
        default:
            return self
        }
    }
}

public func canonical(_ value: JSONValue) -> String {
    jsonText(value.strippingUpdatedAt())
}

public func canonical<T: Encodable>(_ value: T) -> String {
    guard let json = try? JSONValue.fromEncodable(value) else { return "" }
    return canonical(json)
}

private func jsonText(_ value: JSONValue) -> String {
    switch value {
    case .null:
        return "null"
    case .bool(let flag):
        return flag ? "true" : "false"
    case .int(let number):
        return String(number)
    case .double(let number):
        return jsonNumber(number)
    case .string(let text):
        return jsonString(text)
    case .array(let items):
        return "[" + items.map(jsonText).joined(separator: ",") + "]"
    case .object(let fields):
        let body = fields.keys.sorted().map { key in
            jsonString(key) + ":" + jsonText(fields[key] ?? .null)
        }.joined(separator: ",")
        return "{" + body + "}"
    }
}

private func jsonNumber(_ number: Double) -> String {
    guard number.isFinite else { return "null" }
    if number.rounded() == number, abs(number) <= Double(Int.max) {
        return String(Int(number))
    }
    var text = String(format: "%.15g", locale: Foundation.Locale(identifier: "en_US_POSIX"), number)
    if !text.contains("."), !text.contains("e"), !text.contains("E") {
        return text
    }
    return text
}

private func jsonString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0x22: out += "\\\""
        case 0x5C: out += "\\\\"
        case 0x08: out += "\\b"
        case 0x0C: out += "\\f"
        case 0x0A: out += "\\n"
        case 0x0D: out += "\\r"
        case 0x09: out += "\\t"
        case ..<0x20:
            out += String(format: "\\u%04x", scalar.value)
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
    return out
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public func encodeJSON<T: Encodable>(_ value: T, pretty: Bool) throws -> Data {
    let encoder = JSONEncoder()
    var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
    if pretty { formatting.insert(.prettyPrinted) }
    encoder.outputFormatting = formatting
    return try encoder.encode(value)
}
