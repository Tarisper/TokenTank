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
        let snippet = String(decoding: data.prefix(512), as: UTF8.self)
        SanitizedLogger.log("decoding \(T.self) failed: \(error); body: \(snippet)")
        throw ProviderError.decoding
    }
}
