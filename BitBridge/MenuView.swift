//
//  MenuView.swift
//  BitBridge
//

import SwiftUI
import ServiceManagement

struct MenuView: View {
    let sync: ClipSync

    @State private var trusted = Keyboard.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let room = sync.room {
                if let clip = sync.latest {
                    ClipCard(clip: clip, from: sync.isMine(clip) ? "Du" : clip.name, unread: sync.unread, action: sync.copyLatest)
                } else if let names = sync.memberNames {
                    JoinedCard(names: names, plural: sync.members.count > 1)
                } else {
                    CodeCard(code: room.code)
                }
                if !trusted { permissionHint }
                shortcuts
            } else {
                PairingView(sync: sync)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { trusted = Keyboard.isTrusted }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BitBridge").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            moreMenu
        }
    }

    private var statusText: String {
        switch sync.status {
        case .unpaired: "Nicht verbunden"
        case .connecting: "Verbinde …"
        case .online: sync.memberNames.map { "Verbunden mit \($0)" } ?? "Verbunden"
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .unpaired: .secondary
        case .connecting: .orange
        case .online: .green
        }
    }

    private var moreMenu: some View {
        Menu {
            if let room = sync.room {
                Button("Code kopieren") { copy(room.code) }
                Button("Verbindung trennen", role: .destructive, action: sync.leave)
                Divider()
            }
            Toggle("Bei Anmeldung öffnen", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
            ))
            Button("Einstellungen …") { Onboarding.show() }
                .keyboardShortcut(",")
            Divider()
            Button("BitBridge beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Paired

    private var shortcuts: some View {
        HStack(spacing: 16) {
            KeyHint(keys: "⌃⌥C", label: "Teilen")
            KeyHint(keys: "⌃⌥V", label: "Einfügen")
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionHint: some View {
        Button { Keyboard.requestAccess() } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("Bedienungshilfen erlauben")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Cards

private struct ClipCard: View {
    let clip: Clip
    let from: String
    let unread: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(clip.text)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    if unread { Circle().fill(.tint).frame(width: 6, height: 6) }
                    Text("\(from) · \(clip.date, format: .relative(presentation: .named))")
                    Spacer()
                    if hovering { Text("Kopieren") }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary.opacity(hovering ? 0.9 : 0.5), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CodeCard: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 10) {
            Text("Teile diesen Code mit deinem Partner")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(code)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            Button(copied ? "Kopiert" : "Kopieren") {
                copy(code)
                copied = true
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Warte auf Partner …")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

private struct JoinedCard: View {
    let names: String
    let plural: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.green)
                .padding(.bottom, 2)
            Text("\(names) \(plural ? "sind" : "ist") dabei")
                .font(.system(size: 13, weight: .semibold))
            Text("Markiere Text und teile ihn mit ⌃⌥C")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: .rect(cornerRadius: 4))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pairing

private struct PairingView: View {
    let sync: ClipSync

    @State private var input = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Button(action: sync.createRoom) {
                Text("Neuen Code erstellen").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("oder").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("Code eingeben", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($focused)
                    .onSubmit(join)
                    .onChange(of: input) { invalid = false }
                if !input.isEmpty {
                    Button(action: join) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 30)
            .background(.quaternary.opacity(0.5), in: .capsule)
            .overlay {
                Capsule().strokeBorder(invalid ? Color.red.opacity(0.7) : .clear)
            }
        }
        .onAppear { focused = false }
    }

    private func join() {
        invalid = !sync.join(input)
        if !invalid { input = "" }
    }
}
