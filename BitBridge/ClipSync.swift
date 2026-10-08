//
//  ClipSync.swift
//  BitBridge
//
//  App state: the paired room, the live connection and the latest shared clip.
//

import AppKit
import Carbon.HIToolbox
import Observation
import os

struct Member: Codable, Identifiable {
    let id: String
    var name: String
}

@Observable
final class ClipSync {
    static let shared = ClipSync()

    enum Status { case unpaired, connecting, online }
    enum Flash { case sent, copied, failed }
    enum Shortcut { case share, paste }

    private(set) var room: Room?
    private(set) var status: Status = .unpaired
    private(set) var latest: Clip?
    private(set) var unread = false
    private(set) var flash: Flash?
    /// Everyone else in the room, learned from hello / welcome / clip messages.
    private(set) var members: [Member] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(members), forKey: "members") }
    }

    /// Onboarding practice: hotkeys are only recognised, not executed.
    var isPracticing = false {
        didSet { practiced = [] }
    }
    private(set) var practiced: Set<Shortcut> = []

    private var listener: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let deviceID: String

    /// Shown to others next to shared clips. Defaults to the account's first name.
    var name: String {
        didSet { defaults.set(name, forKey: "name") }
    }

    private init() {
        if let id = defaults.string(forKey: "deviceID") {
            deviceID = id
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: "deviceID")
        }
        name = defaults.string(forKey: "name")
            ?? NSFullUserName().split(separator: " ").first.map(String.init)
            ?? "Mac"
        if let data = defaults.data(forKey: "members"),
           let saved = try? JSONDecoder().decode([Member].self, from: data) {
            members = saved
        }
        if let code = defaults.string(forKey: "code") { join(code) }

        let mods = controlKey | optionKey
        HotKeys.shared.register(key: kVK_ANSI_C, modifiers: mods) { [weak self] in self?.handle(.share) }
        HotKeys.shared.register(key: kVK_ANSI_V, modifiers: mods) { [weak self] in self?.handle(.paste) }

        // The stream silently dies during sleep – reconnect on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.connect() }
        }
    }

    // MARK: Pairing

    @discardableResult
    func join(_ code: String) -> Bool {
        guard let room = Room(code: code) else { return false }
        if room.code != defaults.string(forKey: "code") {
            defaults.set(room.code, forKey: "code")
            defaults.removeObject(forKey: "lastEventID")
            latest = nil
            members = []
        }
        self.room = room
        connect()
        return true
    }

    func createRoom() {
        join(Room.newCode())
    }

    func leave() {
        listener?.cancel()
        room = nil
        latest = nil
        unread = false
        members = []
        status = .unpaired
        defaults.removeObject(forKey: "code")
        defaults.removeObject(forKey: "lastEventID")
        defaults.removeObject(forKey: "greeted")
    }

    // MARK: Actions

    private func handle(_ shortcut: Shortcut) {
        if isPracticing {
            practiced.insert(shortcut)
            return
        }
        switch shortcut {
        case .share: share()
        case .paste: paste()
        }
    }

    func share() {
        Task {
            guard let room else { return show(.failed) }
            guard let text = await Keyboard.copySelection(), !text.isEmpty else { return show(.failed) }
            do {
                latest = try await send(.clip, text: text, in: room) // the shared clipboard is the same for everyone, sender included
                unread = false
                show(.sent)
            } catch {
                log.error("share failed: \(error.localizedDescription, privacy: .public)")
                show(.failed)
            }
        }
    }

    func paste() {
        guard let clip = latest else { return show(.failed) }
        unread = false
        Task {
            if !(await Keyboard.paste(clip.text)) {
                Keyboard.requestAccess()
                show(.copied)
            }
        }
    }

    /// "Max", "Max & Anna", "Max + 2"
    var memberNames: String? {
        switch members.count {
        case 0: nil
        case 1: members[0].name
        case 2: "\(members[0].name) & \(members[1].name)"
        default: "\(members[0].name) + \(members.count - 1)"
        }
    }

    func isMine(_ clip: Clip) -> Bool {
        clip.sender == deviceID
    }

    func copyLatest() {
        guard let clip = latest else { return }
        unread = false
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip.text, forType: .string)
        show(.copied)
    }

    private func show(_ flash: Flash) {
        self.flash = flash
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if self.flash == flash { self.flash = nil }
        }
    }

    // MARK: Connection

    private func connect() {
        listener?.cancel()
        guard let room else { return }
        listener = Task { await listen(to: room) }
    }

    private func listen(to room: Room) async {
        var backoff = 1.0
        while !Task.isCancelled {
            status = .connecting
            do {
                let lines = try await Relay.subscribe(to: room.topic, since: defaults.string(forKey: "lastEventID"))
                status = .online
                backoff = 1
                if defaults.string(forKey: "greeted") != room.code {
                    _ = try await send(.hello, in: room)
                    defaults.set(room.code, forKey: "greeted")
                }
                for try await line in lines {
                    guard let event = try? JSONDecoder().decode(Relay.Event.self, from: Data(line.utf8)),
                          event.event == "message" else { continue }
                    defaults.set(event.id, forKey: "lastEventID")
                    await receive(event, in: room)
                }
            } catch {}
            if Task.isCancelled { return }
            status = .connecting
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }

    private func receive(_ event: Relay.Event, in room: Room) async {
        // Anything we can't decrypt (junk, wrong room) is ignored.
        guard let payload = try? await Relay.payload(of: event),
              let clip = try? room.open(payload),
              !isMine(clip) else { return } // our own echo – already handled when sending

        meet(clip)
        switch clip.kind {
        case .hello:
            _ = try? await send(.welcome, in: room)
        case .welcome:
            break
        case .clip:
            guard clip.date >= (latest?.date ?? .distantPast) else { return }
            latest = clip
            unread = true
        }
    }

    private func meet(_ clip: Clip) {
        if let index = members.firstIndex(where: { $0.id == clip.sender }) {
            if members[index].name != clip.name { members[index].name = clip.name }
        } else {
            members.append(Member(id: clip.sender, name: clip.name))
        }
    }

    private func send(_ kind: Clip.Kind, text: String = "", in room: Room) async throws -> Clip {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let clip = Clip(kind: kind, sender: deviceID, name: trimmed.isEmpty ? "Mac" : trimmed, text: text, date: .now)
        try await Relay.publish(room.seal(clip), to: room.topic)
        return clip
    }

    // MARK: Menu bar icon

    var icon: String {
        switch flash {
        case .sent, .copied: return "checkmark"
        case .failed: return "exclamationmark"
        case nil:
            if status != .online { return "square.on.square.dashed" }
            return unread ? "square.fill.on.square.fill" : "square.on.square"
        }
    }
}
