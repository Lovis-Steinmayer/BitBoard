//
//  BitBridgeApp.swift
//  BitBridge
//
//  Created by Lovis Steinmayer on 08.10.26.
//

import SwiftUI
import ServiceManagement

@main
struct BitBridgeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let sync: ClipSync

    init() {
        #if DEBUG
        // Fresh start for testing: open BitBridge.app --args --reset
        if CommandLine.arguments.contains("--reset") {
            try? SMAppService.mainApp.unregister()
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        }
        #endif
        sync = ClipSync.shared
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(sync: sync)
        } label: {
            Image(systemName: sync.icon)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ClipSync.shared // registers the hotkeys right away
        if !UserDefaults.standard.bool(forKey: "onboarded") { Onboarding.show() }
    }
}
