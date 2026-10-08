//
//  Relay.swift
//  BitBridge
//
//  Thin wrapper around ntfy.sh – a free, account-less pub/sub relay.
//  Publish = one POST. Subscribe = one long-lived HTTP stream of JSON lines.
//  Payloads > 4 KB are turned into attachments by ntfy automatically.
//

import Foundation

enum Relay {
    static let base = URL(string: "https://ntfy.sh")!

    struct Event: Decodable {
        struct Attachment: Decodable { let url: URL }
        let id: String
        let event: String
        let message: String?
        let attachment: Attachment?
    }

    static func publish(_ body: String, to topic: String) async throws {
        var request = URLRequest(url: base.appending(path: topic))
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    /// Opens the stream. `since` replays messages missed while offline (ntfy keeps them 12 h);
    /// without one – a freshly joined room – everything still cached is replayed.
    static func subscribe(to topic: String, since: String?) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        var components = URLComponents(url: base.appending(path: "\(topic)/json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "since", value: since ?? "all")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 90 // ntfy sends a keepalive every 45 s
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return bytes.lines
    }

    /// The encrypted payload, either inline or (if large) from the attachment URL.
    static func payload(of event: Event) async throws -> String {
        if let url = event.attachment?.url {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(decoding: data, as: UTF8.self)
        }
        return event.message ?? ""
    }
}
