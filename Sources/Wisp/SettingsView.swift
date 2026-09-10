import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    /// In UserDefaults so the app can open straight to a pane — the Account tab
    /// after a registration handoff — by writing the key before showing.
    @AppStorage("settingsTab") private var tab = "ring"

    var body: some View {
        TabView(selection: $tab) {
            RingSettings(store: store)
                .tabItem { Label("Ring", systemImage: "circle.dashed") }
                .tag("ring")
            MotionSettings(store: store)
                .tabItem { Label("Motion", systemImage: "waveform.path.ecg") }
                .tag("motion")
            SpotlightSettings(store: store)
                .tabItem { Label("Spotlight", systemImage: "sun.max") }
                .tag("spotlight")
            KeyboardSettings(store: store)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag("keyboard")
            GeneralSettings(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            AccountSettings()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag("account")
        }
        .frame(width: 460, height: 430)
    }
}

// MARK: - Ring

private struct RingSettings: View {
    @ObservedObject var store: SettingsStore

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: store.ringColor.nsColor) },
            set: { store.ringColor = RingColor.from(NSColor($0)) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show ring", isOn: $store.ringEnabled)
                Picker("Style", selection: $store.ringStyle) {
                    ForEach(RingStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            } footer: {
                Text("Toggle the ring anywhere with \(store.ringHotKey.display).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Color") {
                HStack(spacing: 10) {
                    ForEach(RingColor.presets, id: \.name) { preset in
                        Button {
                            store.ringColor = preset.color
                        } label: {
                            Circle()
                                .fill(Color(nsColor: preset.color.nsColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(
                                        store.ringColor == preset.color
                                            ? Color.primary.opacity(0.8) : Color.clear,
                                        lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                    Spacer()
                    ColorPicker("Custom", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom color")
                }
            }

            Section("Size") {
                LabeledContent("Size") {
                    Slider(value: $store.diameter, in: SettingsDefaults.diameterRange)
                }
                LabeledContent("Thickness") {
                    Slider(value: $store.thickness, in: SettingsDefaults.thicknessRange)
                }
                LabeledContent("Opacity") {
                    Slider(value: $store.opacity, in: SettingsDefaults.opacityRange)
                }
            }

            Section {
                Text("The ring is visible only on your display — never in screenshots, screen recordings, or screen sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Motion

private struct MotionSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Click") {
                Toggle("Pulse on click", isOn: $store.pulseOnClick)
            }

            Section {
                Toggle("Leave a trail", isOn: $store.trailEnabled)
                LabeledContent("Length") {
                    Slider(value: $store.trailLength,
                           in: SettingsDefaults.trailLengthRange, step: 1)
                }
                .disabled(!store.trailEnabled)
            } header: {
                Text("Trail")
            } footer: {
                Text("Fading ghosts follow fast pointer movements, so the eye can catch up with a flick across the screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Fade out when the pointer is still", isOn: $store.idleHideEnabled)
                LabeledContent("After") {
                    HStack {
                        Slider(value: $store.idleTimeout,
                               in: SettingsDefaults.idleTimeoutRange, step: 1)
                        Text("\(Int(store.idleTimeout))s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .disabled(!store.idleHideEnabled)
            } header: {
                Text("Idle")
            } footer: {
                Text("The ring returns the moment you move. The spotlight is left alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Spotlight

private struct SpotlightSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Spotlight", isOn: $store.spotlightEnabled)
            } footer: {
                Text("Dims everything except a soft circle around the pointer. Toggle it anywhere with \(store.spotlightHotKey.display).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shape") {
                LabeledContent("Radius") {
                    Slider(value: $store.spotlightRadius,
                           in: SettingsDefaults.spotlightRadiusRange)
                }
                LabeledContent("Softness") {
                    Slider(value: $store.spotlightFeather,
                           in: SettingsDefaults.spotlightFeatherRange)
                }
                LabeledContent("Dimming") {
                    Slider(value: $store.spotlightDimming,
                           in: SettingsDefaults.dimmingRange)
                }
            }
            .disabled(!store.spotlightEnabled)

            Section {
                Text("Like the ring, the spotlight is invisible to capture — your audience keeps the undimmed screen while you keep the focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Keyboard

private struct KeyboardSettings: View {
    @ObservedObject var store: SettingsStore
    @State private var trusted = KeystrokeHUD.isTrusted

    var body: some View {
        Form {
            Section {
                LabeledContent("Toggle ring") {
                    HotKeyField(combo: $store.ringHotKey, binding: .toggleRing)
                }
                LabeledContent("Toggle spotlight") {
                    HotKeyField(combo: $store.spotlightHotKey, binding: .toggleSpotlight)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a shortcut and type a new one. ⎋ cancels, ⌫ restores the default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show the keys I press", isOn: $store.keystrokesEnabled)
                Toggle("Visible in recordings and screen sharing",
                       isOn: $store.keystrokesShared)
                    .disabled(!store.keystrokesEnabled)
            } header: {
                Text("Keystroke display")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unlike the ring, this one is for your audience — so it defaults to being captured. Turn the second switch off to keep it on your display only.")
                    if store.keystrokesEnabled && !trusted {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Needs Accessibility permission.")
                            Button("Open Settings…") {
                                NSWorkspace.shared.open(URL(string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text("Every other Wisp feature works without any permission. Reading keys from other apps is the sole exception, so it stays off until you ask for it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // No notification fires when Accessibility is granted, so re-check
        // while this pane is on screen.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = KeystrokeHUD.isTrusted
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var store: SettingsStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch Wisp at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.launchAtLogin = LoginItem.setEnabled($0) }
                ))
                .disabled(!LoginItem.isSupported)
            } footer: {
                Text(LoginItem.isSupported
                     ? "Wisp starts hidden in the menu bar."
                     : "Available once Wisp is running from an installed .app bundle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reset") {
                Button("Restore Defaults") { restoreDefaults() }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wisp \(version)").font(.caption)
                    Text("A cursor highlight only you can see.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func restoreDefaults() {
        let d = SettingsDefaults.self
        store.pulseOnClick = d.pulseOnClick
        store.diameter = d.diameter
        store.thickness = d.thickness
        store.opacity = d.opacity
        store.ringColor = d.ringColor
        store.ringStyle = d.ringStyle
        store.trailEnabled = d.trailEnabled
        store.trailLength = d.trailLength
        store.idleHideEnabled = d.idleHideEnabled
        store.idleTimeout = d.idleTimeout
        store.spotlightEnabled = d.spotlightEnabled
        store.spotlightDimming = d.spotlightDimming
        store.spotlightRadius = d.spotlightRadius
        store.spotlightFeather = d.spotlightFeather
        store.ringHotKey = d.ringHotKey
        store.spotlightHotKey = d.spotlightHotKey
        // ringEnabled and the keystroke switches are left alone: resetting the
        // look of the ring should not silently re-arm a permission-gated
        // feature or turn the ring back on mid-presentation.
    }
}

// MARK: - Hot key recorder

/// A click-to-record shortcut field. AppKit has no public control for this, and
/// SwiftUI's `KeyboardShortcut` only covers in-app menu keys — global hot keys
/// need the raw virtual key code, which means catching `keyDown` ourselves.
private struct HotKeyField: NSViewRepresentable {
    @Binding var combo: KeyCombo
    let binding: HotKeyCenter.Binding

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.binding = binding
        view.combo = combo
        view.onChange = { combo = $0 }
        return view
    }

    func updateNSView(_ view: HotKeyRecorderView, context: Context) {
        view.binding = binding
        if !view.isRecording { view.combo = combo }
    }
}

final class HotKeyRecorderView: NSView {
    var combo: KeyCombo = .toggleRing { didSet { needsDisplay = true } }
    var binding: HotKeyCenter.Binding = .toggleRing
    var onChange: ((KeyCombo) -> Void)?

    private(set) var isRecording = false { didSet { needsDisplay = true } }
    private var rejected = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        rejected = false
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            stopRecording()
            return
        case kVK_Delete:
            apply(binding == .toggleRing ? .toggleRing : .toggleSpotlight)
            return
        default:
            break
        }

        let candidate = KeyCombo(keyCode: UInt32(event.keyCode),
                                 modifiers: KeyCombo.carbonModifiers(from: event.modifierFlags))
        // Reject a bare key (it would swallow typing everywhere) or one another
        // app already owns, rather than storing a shortcut that never fires.
        guard candidate.isValid,
              HotKeyCenter.shared.isAvailable(candidate, excluding: binding) else {
            rejected = true
            needsDisplay = true
            NSSound.beep()
            return
        }
        apply(candidate)
    }

    /// Swallow the key events while recording so ⌘Q does not quit the app
    /// mid-capture.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    private func apply(_ new: KeyCombo) {
        combo = new
        onChange?(new)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        rejected = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                     : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (rejected ? NSColor.systemRed
                  : isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? (rejected ? "Unavailable" : "Type a shortcut…") : combo.display
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12,
                                     weight: isRecording ? .regular : .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: box.midX - size.width / 2,
                                            y: box.midY - size.height / 2),
                                withAttributes: attributes)
    }
}

/// Hosts the SwiftUI settings form in a plain titled window; created lazily
/// and reused, so closing it just hides it.
@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        // The login-item switch mirrors the system database, which the user can
        // change behind our back in System Settings.
        store.launchAtLogin = LoginItem.isEnabled

        if window == nil {
            let w = NSWindow(contentRect: .zero,
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Wisp Settings"
            w.isReleasedWhenClosed = false
            // As an accessory app, activation can be declined (macOS 14
            // cooperative activation) and the window would open behind the
            // frontmost app — follow the user to the active Space instead.
            w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            w.setContentSize(NSSize(width: 460, height: 430))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // If activation was declined, makeKeyAndOrderFront alone leaves the
        // window behind the active app — force it front anyway.
        window?.orderFrontRegardless()
    }
}
