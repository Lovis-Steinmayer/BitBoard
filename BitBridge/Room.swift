//
//  Room.swift
//  BitBridge
//
//  A room is everything derived from one shared pairing code:
//  the relay topic (where clips travel) and the encryption key.
//  The relay only ever sees the topic hash and ciphertext.
//

import Foundation
import CryptoKit

struct Clip: Codable, Equatable {
    enum Kind: String, Codable {
        case clip
        case hello    // "I just joined" – sent once per room
        case welcome  // reply to a hello, so the newcomer learns who is already here
    }

    let kind: Kind
    let sender: String   // device id, used to ignore our own echoes
    let name: String     // human readable device name
    let text: String
    let date: Date
}

struct Room {
    let code: String
    let topic: String
    private let key: SymmetricKey

    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no 0/O/1/I
    private static let length = 16 // 16 × 5 bit = 80 bit

    /// Fresh random code, formatted as XXXX-XXXX-XXXX-XXXX.
    static func newCode() -> String {
        let chars = (0..<length).map { _ in alphabet.randomElement()! }
        return stride(from: 0, to: length, by: 4)
            .map { String(chars[$0..<$0 + 4]) }
            .joined(separator: "-")
    }

    /// Accepts sloppy input ("k7qm hx2p…", lowercase, spaces, dashes).
    init?(code input: String) {
        let raw = input.uppercased().filter { Self.alphabet.contains($0) }
        guard raw.count == Self.length else { return nil }

        let chars = Array(raw)
        code = stride(from: 0, to: Self.length, by: 4)
            .map { String(chars[$0..<$0 + 4]) }
            .joined(separator: "-")

        let secret = SymmetricKey(data: Data(raw.utf8))
        let salt = Data("BitBridge.v1".utf8)
        key = HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, salt: salt, info: Data("key".utf8), outputByteCount: 32)
        let topicKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, salt: salt, info: Data("topic".utf8), outputByteCount: 16)
        topic = "bitbridge-" + topicKey.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
    }

    func seal(_ clip: Clip) throws -> String {
        let json = try JSONEncoder().encode(clip)
        let packed = try (json as NSData).compressed(using: .lzfse) as Data
        return try AES.GCM.seal(packed, using: key).combined!.base64EncodedString()
    }

    func open(_ payload: String) throws -> Clip {
        guard let data = Data(base64Encoded: payload.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let packed = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        let json = try (packed as NSData).decompressed(using: .lzfse) as Data
        return try JSONDecoder().decode(Clip.self, from: json)
    }
}
