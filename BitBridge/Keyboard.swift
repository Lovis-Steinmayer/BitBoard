//
//  Keyboard.swift
//  BitBridge
//
//  Global hotkeys (Carbon – no permission needed) and synthetic ⌘C / ⌘V
//  (CGEvent – needs Accessibility permission).
//

import AppKit
import Carbon.HIToolbox
import os

let log = Logger(subsystem: "com.squash.BitBridge", category: "app")

final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &spec, nil, nil)
        log.info("hotkey handler installed: \(status, privacy: .public)")
    }

    func register(key: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4242_7264), id: id) // "BBrd"
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        log.info("hotkey \(id, privacy: .public) registered: \(status, privacy: .public)")
        if let ref { refs.append(ref) }
    }

    fileprivate func fire(_ id: UInt32) {
        log.info("hotkey \(id, privacy: .public) pressed")
        actions[id]?()
    }
}

private nonisolated func hotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let id = hotKeyID.id
    MainActor.assumeIsolated { HotKeys.shared.fire(id) } // Carbon delivers on the main thread
    return noErr
}

enum Keyboard {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Copies the current selection and returns the clipboard text.
    /// Without a selection (or without permission) this is simply whatever is on the clipboard.
    static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        if isTrusted {
            await waitForModifierRelease()
            let before = pasteboard.changeCount
            press(CGKeyCode(kVK_ANSI_C))
            for _ in 0..<30 where pasteboard.changeCount == before {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        return pasteboard.string(forType: .string)
    }

    /// Puts text on the clipboard and pastes it into the frontmost app.
    /// Returns false if it could only be placed on the clipboard.
    static func paste(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard isTrusted else { return false }
        await waitForModifierRelease()
        press(CGKeyCode(kVK_ANSI_V))
        return true
    }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }

    /// The hotkey's ⌃⌥ is usually still held – wait for it, or the target app sees ⌃⌥⌘C.
    private static func waitForModifierRelease() async {
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for _ in 0..<100 where !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
