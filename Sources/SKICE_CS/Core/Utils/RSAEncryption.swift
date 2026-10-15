import Foundation
import Security

/// Errors raised while preparing the RSA-encrypted password payload.
public enum RSAEncryptionError: LocalizedError, Sendable {
    case malformedKey
    case keyImportFailed(String)
    case encryptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .malformedKey:
            return "Steam returned a malformed RSA public key."
        case .keyImportFailed(let detail):
            return "Could not import the Steam RSA public key: \(detail)"
        case .encryptionFailed(let detail):
            return "Could not encrypt the password for Steam: \(detail)"
        }
    }
}

/// RSA password encryption for Steam's login flow.
///
/// Steam hands out a 2048-bit RSA public key (modulus + exponent, hexadecimal)
/// and expects the account password, PKCS#1 v1.5 padded, encrypted with that
/// key and base64-encoded. The padding mode matches the reference clients that
/// talk to this endpoint; using OAEP instead would be silently rejected.
public enum RSAEncryption {

    /// Encrypts the plaintext with the RSA public key described by the
    /// hexadecimal modulus and exponent, returning the raw ciphertext.
    public static func encrypt(
        plaintext: String,
        modulusHex: String,
        exponentHex: String
    ) throws -> Data {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw RSAEncryptionError.encryptionFailed("password is not valid UTF-8")
        }

        let der = try pkcs1PublicKeyDER(modulusHex: modulusHex, exponentHex: exponentHex)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: der.keySizeBits
        ]

        var importError: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(der.der as CFData, attributes as CFDictionary, &importError) else {
            let detail = importError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            throw RSAEncryptionError.keyImportFailed(detail)
        }

        var encryptError: Unmanaged<CFError>?
        guard let ciphertext = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionPKCS1,
            plaintextData as CFData,
            &encryptError
        ) else {
            let detail = encryptError.map { String(describing: $0.takeRetainedValue()) } ?? "unknown error"
            throw RSAEncryptionError.encryptionFailed(detail)
        }

        return ciphertext as Data
    }

    // MARK: - PKCS#1 DER assembly

    private struct PublicKeyDER {
        let der: Data
        let keySizeBits: Int
    }

    /// Builds the PKCS#1 RSAPublicKey DER structure that SecKeyCreateWithData expects.
    private static func pkcs1PublicKeyDER(modulusHex: String, exponentHex: String) throws -> PublicKeyDER {
        let modulus = try hexData(modulusHex)
        var exponent = try hexData(exponentHex)
        guard modulus.count >= 64, !exponent.isEmpty else {
            throw RSAEncryptionError.malformedKey
        }

        // A small exponent can arrive with redundant leading zero bytes; DER
        // integers are minimal, so strip them while keeping the sign bit clear.
        while exponent.count > 1 && exponent.first == 0 {
            exponent.removeFirst()
        }

        var body = Data()
        body.append(derInteger(modulus))
        body.append(derInteger(exponent))
        let der = derWrap(tag: 0x30, body: body)

        return PublicKeyDER(der: der, keySizeBits: modulus.count * 8)
    }

    private static func derInteger(_ value: Data) -> Data {
        var bytes = value
        while bytes.count > 1 && bytes.first == 0 {
            bytes.removeFirst()
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return derWrap(tag: 0x02, body: bytes)
    }

    private static func derWrap(tag: UInt8, body: Data) -> Data {
        var out = Data([tag])
        out.append(derLengthPrefix(body.count))
        out.append(body)
        return out
    }

    private static func derLengthPrefix(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    /// Decodes a hexadecimal string (as returned by Steam) into bytes.
    public static func hexData(_ hex: String) throws -> Data {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else {
            throw RSAEncryptionError.malformedKey
        }

        var out = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw RSAEncryptionError.malformedKey
            }
            out.append(byte)
            index = next
        }
        return out
    }
}
