import AppKit
import ApplicationServices
import Combine

/// An opt-in heads-up display of the keys you press, for demos and screencasts.
///
/// This is the one Wisp feature that needs a permission: reading keystrokes
/// from other apps requires an `NSEvent` global keyboard monitor, and macOS
/// gates those behind Accessibility. Nothing here runs — and no prompt appears —
/// until the user turns the feature on.
///
/// Note the deliberate inversion of Wisp's usual trick: the ring is for you, so
/// it is hidden from capture, but a keystroke HUD is for your audience, so by
/// default it is *visible* in recordings and screen shares.
@MainActor
final class KeystrokeHUD {
    private let settings: SettingsStore
    private var window: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    private var chords: [String] = []
    private var clearTimer: Timer?
    /// macOS posts no notification when Accessibility is granted, so while the
    /// feature is on but untrusted we re-check on a slow timer.
    private var trustTimer: Timer?

    /// Set when the user enables the feature, so the system prompt appears once
    /// per toggle rather than on every trust poll.
    private var hasPrompted = false

    private static let maxChords = 6
    private static let clearAfter: TimeInterval = 2.5

    init(settings: SettingsStore) {
        self.settings = settings
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)
        apply()
    }

    /// True once the user has granted Accessibility to this app.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Opens the system prompt that deep-links to Privacy & Security. The
    /// option key is spelled out because the imported `kAXTrustedCheckOption…`
    /// global is a mutable `var`, which Swift 6 rejects across isolation.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Wiring

    private func apply() {
        guard settings.keystrokesEnabled else {
            hasPrompted = false
            teardown()
            return
        }
        window?.sharingType = settings.keystrokesShared ? .readOnly : .none

        guard Self.isTrusted else {
            // Ask once, then poll — the user has to leave the app to grant it.
            if !hasPrompted {
                hasPrompted = true
                Self.requestTrust()
            }
            startTrustPolling()
            return
        }
        trustTimer?.invalidate()
        trustTimer = nil
        installMonitorIfNeeded()
    }

    private func startTrustPolling() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let hud = KeystrokeHUD.shared else { return }
                guard hud.settings.keystrokesEnabled else {
                    hud.trustTimer?.invalidate()
                    hud.trustTimer = nil
                    return
                }
                if KeystrokeHUD.isTrusted { hud.apply() }
            }
        }
    }

    /// Monitor callbacks are nonisolated closures; routing through a static
    /// avoids capturing non-Sendable self, matching `OverlayController`.
    static var shared: KeystrokeHUD?

    private func installMonitorIfNeeded() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { KeystrokeHUD.shared?.record(event) }
        }) { monitors.append(m) }
        // Keys typed into Wisp's own Settings window would otherwise be missed.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { KeystrokeHUD.shared?.record(event) }
            return event
        }) { monitors.append(m) }
    }

    private func teardown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        trustTimer?.invalidate()
        trustTimer = nil
        clearTimer?.invalidate()
        clearTimer = nil
        chords.removeAll()
        window?.orderOut(nil)
    }

    // MARK: - Recording

    private func record(_ event: NSEvent) {
        let combo = KeyCombo(keyCode: UInt32(event.keyCode),
                             modifiers: KeyCombo.carbonModifiers(from: event.modifierFlags))
        chords.append(combo.display)
        if chords.count > Self.maxChords { chords.removeFirst(chords.count - Self.maxChords) }
        show()

        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: Self.clearAfter, repeats: false) { _ in
            MainActor.assumeIsolated { KeystrokeHUD.shared?.clear() }
        }
    }

    private func clear() {
        chords.removeAll()
        window?.orderOut(nil)
    }

    // MARK: - Window

    private func show() {
        let panel = window ?? makeWindow()
        label.stringValue = chords.joined(separator: "  ")
        label.sizeToFit()

        let padding = NSSize(width: 28, height: 16)
        let size = NSSize(width: label.frame.width + padding.width * 2,
                          height: label.frame.height + padding.height * 2)
        label.setFrameOrigin(NSPoint(x: padding.width, y: padding.height))

        // Follow the display the pointer is on, so the HUD lands on the screen
        // being presented rather than always on the main one.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(x: visible.midX - size.width / 2,
                              y: visible.minY + 60,
                              width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.sharingType = settings.keystrokesShared ? .readOnly : .none

        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 14
        backdrop.layer?.masksToBounds = true
        backdrop.autoresizingMask = [.width, .height]

        label.font = .monospacedSystemFont(ofSize: 26, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        backdrop.addSubview(label)

        panel.contentView = backdrop
        window = panel
        return panel
    }
}
