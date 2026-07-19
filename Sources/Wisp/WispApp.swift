import AppKit
import Carbon.HIToolbox
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
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var settingsWindow: SettingsWindowController!

    private let toggleItem = NSMenuItem()
    private let pulseItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore.load()
        settingsWindow = SettingsWindowController(store: settings)

        overlay = OverlayController(settings: settings)
        OverlayController.shared = overlay

        buildStatusItem()

        // ⌥⌘W toggles the ring from anywhere. Carbon delivers the callback on
        // the main thread.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_W),
                        modifiers: UInt32(cmdKey | optionKey)) {
            MainActor.assumeIsolated {
                retainedDelegate?.toggleRing(nil)
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
        toggleItem.keyEquivalent = "w"
        toggleItem.keyEquivalentModifierMask = [.command, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        pulseItem.title = "Highlight on Click"
        pulseItem.action = #selector(togglePulse(_:))
        pulseItem.target = self
        menu.addItem(pulseItem)

        menu.addItem(.separator())

        let settingsMenuItem = NSMenuItem(title: "Settings…",
                                          action: #selector(openSettings(_:)),
                                          keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Wisp",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = settings.ringEnabled ? "Hide Ring" : "Show Ring"
        pulseItem.state = settings.pulseOnClick ? .on : .off
    }

    // MARK: - Actions

    @objc func toggleRing(_ sender: Any?) {
        settings.ringEnabled.toggle()
    }

    @objc func togglePulse(_ sender: Any?) {
        settings.pulseOnClick.toggle()
    }

    @objc func openSettings(_ sender: Any?) {
        settingsWindow.show()
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
