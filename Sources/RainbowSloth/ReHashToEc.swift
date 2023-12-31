import CryptoKit
import Foundation

/// Helper functions for creating and manipulating P256 keys.
enum ReHashToEc {

    /// Deterministically maps an input `seed` value to a P256 `SecKey`.
    internal static func rehashToP256(seed: Bytes) -> SecKey {
        let salt = Bytes()
        let info = Bytes()
        var counter: UInt32 = 0
        while true {
            let counterBytes = withUnsafeBytes(of: counter.bigEndian, Array.init)
            let currentSeed = seed + counterBytes

            var arr = HkdfSha256.derive(salt: salt, ikm: currentSeed, info: info, outputLength: 33)
            arr[0] = 0x02 | (arr[0] & 0x01)

            // try to convert and for any failure restart the loop with an incremented counter
            guard let candidateBytes = try? convertCompressedToX963(bytes: arr) else {
                counter += 1
                continue
            }

            guard let candidate = try? SlothSecureEnclave.importPublicKey(bytes: candidateBytes) else {
                counter += 1
                continue
            }

            return candidate
        }
    }

    /// Convert a P256 key from its compressed representation to the X963 represeantation that is expected for importing it the iOS APIs.
    internal static func convertCompressedToX963(bytes: Bytes) throws -> Bytes {
        // Unfortunately, iOS only added support for the SEC1-style compressed representation
        // in iOS 16. That works as expected on an array with 33 bytes with the first one being 0x02/0x03
        // to indicate which of the possible Y values to choose.
        //
        // So, for simplifying our implementation, for devices that do not have iOS 16, we use Apple's
        // "compactRepresentation" which drops the first byte (i.e. it is only one byte long). The resulting
        // curve Y-coordinate will be different, but the algorithm work as usual otherwise
        //
        // More resources (the Apple documentation is really not helpful):
        // https://www.aidanwoods.com/blog/apple-compact-representation
        // https://github.com/golang/go/issues/52221#issuecomment-1111153561

        if #available(iOS 16.0, *) {
            return try convertCompressedToX963_16andAbove(bytes: bytes)
        } else {
            return try convertCompressedToX963_below16(bytes: bytes)
        }
    }

    internal static func convertCompressedToX963_below16(bytes: Bytes) throws -> Bytes {
        // drop the first byte from the compressed SEC-1 representation for Apple's special compact representation
        let trimmedBytes = bytes[1..<bytes.count]
        let convertedData = try P256.Signing.PublicKey.init(compactRepresentation: trimmedBytes).x963Representation
        return Bytes(convertedData)
    }

    @available(iOS 16.0, *)
    internal static func convertCompressedToX963_16andAbove(bytes: Bytes) throws -> Bytes {
        let convertedData =  try P256.Signing.PublicKey.init(compressedRepresentation: bytes).x963Representation
        return Bytes(convertedData)
    }
}
