import Foundation

/// Decodes a provider JSON body, mapping failures to `ProviderError.decoding`.
/// - Parameters:
///   - type: Target type.
///   - data: Response body.
/// - Returns: Decoded value.
/// - Throws: `ProviderError.decoding` on invalid or unknown JSON.
func decodeProvider<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        SanitizedLogger.log("decoding \(T.self) failed: \(error)")
        throw ProviderError.decoding
    }
}
