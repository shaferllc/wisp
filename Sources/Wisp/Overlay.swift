import AppKit
import Combine

/// Owns the transparent, click-through overlay window that draws the ring and
/// keeps it glued to the pointer via global + local mouse monitors.
///
/// The window is invisible to screen recordings, screenshots, and screen
/// sharing because `sharingType = .none` excludes it from every capture path
/// (CGWindowList, ScreenCaptureKit, the screenshot UI).
@MainActor
final class OverlayController {
    private let settings: SettingsStore
    private let window: NSWindow
    private let ringView = RingView()
    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore) {
        self.settings = settings

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true          // clicks pass straight through
        window.level = .screenSaver               // above full-screen apps and the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none                // the whole trick: never captured
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = ringView

        applySettings()
        installMonitors()

        settings.objectWillChange
            .receive(on: RunLoop.main)            // wait until the new value has landed
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
    }

    // MARK: - Settings → window

    /// Extra room around the ring so the glow never clips at the window edge.
    private var glowMargin: CGFloat { CGFloat(settings.thickness) * 2 + 30 }

    private func applySettings() {
        let side = CGFloat(settings.diameter) + glowMargin * 2
        let loc = NSEvent.mouseLocation
        window.setFrame(NSRect(x: loc.x - side / 2, y: loc.y - side / 2,
                               width: side, height: side), display: true)
        ringView.configure(diameter: CGFloat(settings.diameter),
                           thickness: CGFloat(settings.thickness),
                           color: settings.ringColor.nsColor)
        window.alphaValue = CGFloat(settings.opacity)
        if settings.ringEnabled {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: - Pointer tracking

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                            .rightMouseDragged, .otherMouseDragged]
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        // Global monitors cover every other app; no Accessibility permission is
        // required for mouse events (only keyboard monitoring needs it).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { _ in
            MainActor.assumeIsolated { Self.shared?.followPointer() }
        }) { globalMonitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: downs, handler: { _ in
            MainActor.assumeIsolated { Self.shared?.clickPulse() }
        }) { globalMonitors.append(m) }

        // A local monitor covers events delivered to Wisp itself (e.g. while
        // the Settings window or menu is frontmost).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: moves.union(downs)) { event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    Self.shared?.clickPulse()
                } else {
                    Self.shared?.followPointer()
                }
            }
            return event
        }
    }

    /// Monitor callbacks arrive on the main thread but as nonisolated
    /// closures; routing through a static avoids capturing non-Sendable self.
    static var shared: OverlayController?

    private func followPointer() {
        guard settings.ringEnabled else { return }
        // NSEvent.mouseLocation is in global screen coordinates, which spans
        // every attached display — so the ring follows across screens for free.
        let loc = NSEvent.mouseLocation
        let f = window.frame
        window.setFrameOrigin(NSPoint(x: loc.x - f.width / 2, y: loc.y - f.height / 2))
    }

    private func clickPulse() {
        guard settings.ringEnabled, settings.pulseOnClick else { return }
        followPointer()
        ringView.pulse()
    }
}

/// Layer-backed view drawing a soft glowing ring, plus an expanding pulse
/// ring flashed on click.
final class RingView: NSView {
    private let ringLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private var diameter: CGFloat = 64
    private var thickness: CGFloat = 5
    private var color: NSColor = RingColor.wispBlue.nsColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for shape in [pulseLayer, ringLayer] {
            shape.fillColor = nil
            layer?.addSublayer(shape)
        }
        pulseLayer.opacity = 0
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(diameter: CGFloat, thickness: CGFloat, color: NSColor) {
        self.diameter = diameter
        self.thickness = thickness
        self.color = color
        rebuild()
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let b = bounds
        let radius = max(1, (diameter - thickness) / 2)
        let circle = CGPath(ellipseIn: CGRect(x: b.midX - radius, y: b.midY - radius,
                                              width: radius * 2, height: radius * 2),
                            transform: nil)
        for shape in [ringLayer, pulseLayer] {
            shape.frame = b
            shape.path = circle
            shape.strokeColor = color.cgColor
        }
        ringLayer.lineWidth = thickness
        ringLayer.shadowColor = color.cgColor
        ringLayer.shadowOpacity = 0.9
        ringLayer.shadowRadius = thickness * 1.4 + 5
        ringLayer.shadowOffset = .zero
        pulseLayer.lineWidth = max(2, thickness * 0.8)
        CATransaction.commit()
    }

    func pulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.65
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.removeAnimation(forKey: "pulse")
        pulseLayer.add(group, forKey: "pulse")
    }
}
