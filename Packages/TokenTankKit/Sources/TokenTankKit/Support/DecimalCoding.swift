import Foundation

/// Tolerant `Decimal` decoding for provider responses: numbers and decimal
/// strings are accepted, `null`/missing decode to `nil`.
extension KeyedDecodingContainer {
    /// Decodes a `Decimal` tolerantly.
    /// - Parameter key: Coding key.
    /// - Returns: Parsed value, or `nil` when the key is missing or `null`.
    /// - Throws: `DecodingError` when the value is present but not numeric.
    func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if contains(key) == false { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Decimal.self, forKey: key) { return value }
        let string = try decode(String.self, forKey: key)
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a decimal: \(string)")
        }
        return value
    }

    /// Decodes a required `Decimal` tolerantly.
    /// - Parameter key: Coding key.
    /// - Returns: Parsed value.
    /// - Throws: `DecodingError` when the value is missing, `null` or not numeric.
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        guard let value = try decodeDecimalIfPresent(forKey: key) else {
            throw DecodingError.valueNotFound(Decimal.self, .init(codingPath: codingPath + [key], debugDescription: "Missing decimal"))
        }
        return value
    }
}
