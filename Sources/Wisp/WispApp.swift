import AppKit
import Carbon
import Combine
import SwiftUI

@main
@MainActor
struct WispApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only (LSUIElement in the plist too)
        let delegate = AppDelegate()
        retainedDelegate = delegate         // NSApplication.delegate is weak
        app.delegate = delegate
        app.run()
    }
}

@MainActor private var retainedDelegate: AppDelegate?

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings: SettingsStore!
    private var overlay: OverlayController!
    private var keystrokes: KeystrokeHUD!
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    private let toggleItem = NSMenuItem()
    private let spotlightItem = NSMenuItem()
    private let pulseItem = NSMenuItem()
    private let trailItem = NSMenuItem()
    private let idleItem = NSMenuItem()

    /// What the hot keys are currently bound to, so a settings change only
    /// re-registers when the combo actually changed.
    private var boundRingHotKey: KeyCombo?
    private var boundSpotlightHotKey: KeyCombo?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // shafer.llc hands registration keys back as wisp://activate?…
        // Registering before launch finishes also catches a URL that launched
        // the app.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        LicenseModel.shared.handle(url)
        // A menu-bar app has nothing on screen to show the result, so open
        // Settings on the Account tab, where "Checking…" turns into "Registered".
        UserDefaults.standard.set("account", forKey: "settingsTab")
        settingsWindow?.show()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore.load()
        settings.launchAtLogin = LoginItem.isEnabled
        settingsWindow = SettingsWindowController(store: settings)

        overlay = OverlayController(settings: settings)
        OverlayController.shared = overlay

        keystrokes = KeystrokeHUD(settings: settings)
        KeystrokeHUD.shared = keystrokes

        buildStatusItem()
        syncHotKeys()
        LicenseModel.shared.startRechecking()

        settings.objectWillChange
            .receive(on: RunLoop.main)   // wait until the new value has landed
            .sink { [weak self] _ in self?.syncHotKeys() }
            .store(in: &cancellables)
    }

    // MARK: - Hot keys

    private func syncHotKeys() {
        if boundRingHotKey != settings.ringHotKey {
            boundRingHotKey = settings.ringHotKey
            HotKeyCenter.shared.note(.toggleRing, combo: settings.ringHotKey)
            HotKeyCenter.shared.register(.toggleRing, combo: settings.ringHotKey) {
                retainedDelegate?.toggleRing(nil)
            }
        }
        if boundSpotlightHotKey != settings.spotlightHotKey {
            boundSpotlightHotKey = settings.spotlightHotKey
            HotKeyCenter.shared.note(.toggleSpotlight, combo: settings.spotlightHotKey)
            HotKeyCenter.shared.register(.toggleSpotlight, combo: settings.spotlightHotKey) {
                retainedDelegate?.toggleSpotlight(nil)
            }
        }
    }

    // MARK: - Status item and menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.statusImage()
        statusItem.button?.toolTip = "Wisp — cursor highlight"

        let menu = NSMenu()
        menu.delegate = self

        toggleItem.title = "Hide Ring"
        toggleItem.action = #selector(toggleRing(_:))
        toggleItem.target = self
        menu.addItem(toggleItem)

        spotlightItem.title = "Spotlight"
        spotlightItem.action = #selector(toggleSpotlight(_:))
        spotlightItem.target = self
        menu.addItem(spotlightItem)

        menu.addItem(.separator())

        pulseItem.title = "Highlight on Click"
        pulseItem.action = #selector(togglePulse(_:))
        pulseItem.target = self
        menu.addItem(pulseItem)

        trailItem.title = "Cursor Trail"
        trailItem.action = #selector(toggleTrail(_:))
        trailItem.target = self
        menu.addItem(trailItem)

        idleItem.title = "Fade When Idle"
        idleItem.action = #selector(toggleIdle(_:))
        idleItem.target = self
        menu.addItem(idleItem)

        menu.addItem(.separator())

        let settingsMenuItem = NSMenuItem(title: "Settings…",
                                          action: #selector(openSettings(_:)),
                                          keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: "Wisp Help", action: #selector(openHelp(_:)), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let supportItem = NSMenuItem(title: "Contact Support…", action: #selector(contactSupport(_:)), keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Wisp",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = settings.ringEnabled ? "Hide Ring" : "Show Ring"
        // Mirror the user's own shortcuts, which are rebindable.
        toggleItem.keyEquivalent = Self.menuKeyEquivalent(settings.ringHotKey)
        toggleItem.keyEquivalentModifierMask = settings.ringHotKey.eventModifiers
        spotlightItem.state = settings.spotlightEnabled ? .on : .off
        spotlightItem.keyEquivalent = Self.menuKeyEquivalent(settings.spotlightHotKey)
        spotlightItem.keyEquivalentModifierMask = settings.spotlightHotKey.eventModifiers
        pulseItem.state = settings.pulseOnClick ? .on : .off
        trailItem.state = settings.trailEnabled ? .on : .off
        idleItem.state = settings.idleHideEnabled ? .on : .off
    }

    /// Menu key equivalents are characters, not virtual key codes; anything
    /// without a plain character (arrows, function keys) simply shows no
    /// shortcut in the menu even though the global hot key still works.
    private static func menuKeyEquivalent(_ combo: KeyCombo) -> String {
        let name = KeyCombo.keyName(combo.keyCode)
        guard name.count == 1 else { return "" }
        return name.lowercased()
    }

    // MARK: - Actions

    @objc func toggleRing(_ sender: Any?) {
        settings.ringEnabled.toggle()
    }

    @objc func toggleSpotlight(_ sender: Any?) {
        settings.spotlightEnabled.toggle()
    }

    @objc func togglePulse(_ sender: Any?) {
        settings.pulseOnClick.toggle()
    }

    @objc func toggleTrail(_ sender: Any?) {
        settings.trailEnabled.toggle()
    }

    @objc func toggleIdle(_ sender: Any?) {
        settings.idleHideEnabled.toggle()
    }

    @objc func openSettings(_ sender: Any?) {
        settingsWindow.show()
    }

    @objc func openHelp(_ sender: Any?) {
        NSWorkspace.shared.open(LicenseModel.site.appendingPathComponent("wisp/help"))
    }

    /// shafer.llc/support with Wisp preselected and the version filled in, so
    /// the request says what it's about without the user typing it.
    @objc func contactSupport(_ sender: Any?) {
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var c = URLComponents(url: LicenseModel.site.appendingPathComponent("support"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "product", value: "wisp"),
                        URLQueryItem(name: "version", value: "\(app) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")]
        NSWorkspace.shared.open(c.url!)
    }

    /// A small template ring-with-dot mark for the menu bar.
    private static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            ring.lineWidth = 1.8
            NSColor.black.setStroke()
            ring.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.midX - 1.6, y: rect.midY - 1.6,
                                                  width: 3.2, height: 3.2))
            NSColor.black.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
