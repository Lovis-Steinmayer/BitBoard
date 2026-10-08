//
//  Onboarding.swift
//  BitBridge
//
//  Two calm pages on first launch:
//  1. what it does + name, permission, login item
//  2. press both shortcuts once – completes by itself
//

import SwiftUI
import ServiceManagement

enum Onboarding {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let controller = NSHostingController(rootView: OnboardingView(done: { close() }))
            controller.sizingOptions = [] // fixed size – live resizing during the page animation loops AppKit's layout
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(OnboardingView.size)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    ClipSync.shared.isPracticing = false
                    Onboarding.window = nil // next time starts fresh on page 1
                }
            }
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
    }
}

struct OnboardingView: View {
    static let size = NSSize(width: 400, height: 620)

    let done: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if page == 0 {
                    WelcomePage(next: { go(to: 1) })
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
                } else {
                    PracticePage(back: { go(to: 0) }, done: done)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()

            PageDots(count: 2, current: page)
                .padding(.top, 18)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func go(to page: Int) {
        withAnimation(.smooth(duration: 0.35)) { self.page = page }
    }
}

// MARK: - Page 1

private struct WelcomePage: View {
    let next: () -> Void

    @State private var trusted = Keyboard.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Bindable private var sync = ClipSync.shared

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.bottom, 10)

            Text("BitBridge")
                .font(.system(size: 26, weight: .bold))
            Text("Eine Zwischenablage für zwei Macs.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(spacing: 14) {
                FeatureRow(symbol: "arrow.left.arrow.right", title: "Kopieren hier, einfügen dort",
                           detail: "Teile Text mit einem Kurzbefehl")
                FeatureRow(symbol: "lock.fill", title: "Ende-zu-Ende verschlüsselt",
                           detail: "AES-256-GCM · nur ihr könnt mitlesen")
            }
            .padding(.vertical, 28)

            VStack(spacing: 0) {
                SettingRow(title: "Dein Name", detail: "Sieht dein Partner bei deinen Clips") {
                    TextField("Name", text: $sync.name)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                Divider().padding(.leading, 14)
                SettingRow(title: "Bedienungshilfen", detail: "Nötig, damit die Kurzbefehle kopieren und einfügen") {
                    if trusted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    } else {
                        Button("Erlauben") { Keyboard.requestAccess() }
                    }
                }
                Divider().padding(.leading, 14)
                SettingRow(title: "Bei Anmeldung öffnen", detail: nil) {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))

            Spacer(minLength: 24)

            Button(action: next) {
                Text("Weiter").frame(maxWidth: .infinity)
            }
            .disabled(!trusted)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxHeight: .infinity)
        .onChange(of: launchAtLogin) { _, on in
            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
        .task {
            // The permission is granted in System Settings – reflect it live.
            while !Task.isCancelled {
                trusted = Keyboard.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - Page 2

private struct PracticePage: View {
    let back: () -> Void
    let done: () -> Void

    private let sync = ClipSync.shared
    private var finished: Bool { sync.practiced.count == 2 }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: finished ? "checkmark.circle.fill" : "keyboard")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(finished ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .contentTransition(.symbolEffect(.replace))
                .padding(.bottom, 16)

            Text(finished ? "Startklar" : "Probier’s aus")
                .font(.system(size: 26, weight: .bold))
                .contentTransition(.opacity)
            Text(finished ? "Du kennst die Kurzbefehle." : "Drück beide Kurzbefehle einmal.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .contentTransition(.opacity)

            VStack(spacing: 10) {
                PracticeRow(letter: "C", title: "Teilen", done: sync.practiced.contains(.share))
                PracticeRow(letter: "V", title: "Einfügen", done: sync.practiced.contains(.paste))
            }
            .padding(.top, 28)

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                Button(action: back) {
                    Text("Zurück").padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                Button(action: done) {
                    Text("Fertig").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!finished)
            }
            .controlSize(.large)
        }
        .frame(maxHeight: .infinity)
        .animation(.smooth, value: sync.practiced)
        .onAppear { sync.isPracticing = true }
        .onDisappear { sync.isPracticing = false }
        .onChange(of: finished) { _, finished in
            guard finished else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                done()
            }
        }
    }
}

private struct PracticeRow: View {
    let letter: String
    let title: String
    let done: Bool

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                KeyCap(symbol: "⌃", word: "control")
                KeyCap(symbol: "⌥", word: "option")
                KeyCap(symbol: letter, word: nil)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 4)
            Spacer(minLength: 0)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.quaternary))
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(12)
        .background(.quaternary.opacity(done ? 0.3 : 0.5), in: .rect(cornerRadius: 10))
    }
}

/// Looks like a Mac key: symbol top right, word bottom left.
private struct KeyCap: View {
    let symbol: String
    let word: String?

    var body: some View {
        ZStack {
            if let word {
                Text(symbol)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Text(word)
                    .font(.system(size: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                Text(symbol).font(.system(size: 15, weight: .medium))
            }
        }
        .padding(5)
        .frame(width: word == nil ? 36 : 44, height: 36)
        .background(.background, in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}

// MARK: - Shared

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SettingRow<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}
