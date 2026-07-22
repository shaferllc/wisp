import AppKit
import Combine
import QuartzCore

/// Owns the transparent, click-through overlay window that draws the pointer
/// marker, its trail, the click pulse, and the spotlight dimming — and keeps
/// them glued to the pointer via global + local mouse monitors.
///
/// The window is invisible to screen recordings, screenshots, and screen
/// sharing because `sharingType = .none` excludes it from every capture path
/// (CGWindowList, ScreenCaptureKit, the screenshot UI).
///
/// One window spans the union of every screen rather than a small window that
/// chases the cursor: the trail leaves marks behind the pointer and the
/// spotlight dims everything around it, so both need a surface wider than the
/// marker itself. Moving a layer inside a static window is also cheaper than
/// moving the window on every mouse event.
@MainActor
final class OverlayController {
    private let settings: SettingsStore
    private let window: NSWindow
    private let overlayView = OverlayView()
    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var idleTimer: Timer?
    private var idleHidden = false

    init(settings: SettingsStore) {
        self.settings = settings

        window = NSWindow(contentRect: Self.desktopFrame(), styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true          // clicks pass straight through
        window.level = .screenSaver               // above full-screen apps and the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none                // the whole trick: never captured
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = overlayView

        applySettings()
        installMonitors()

        settings.objectWillChange
            .receive(on: RunLoop.main)            // wait until the new value has landed
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        // Plugging in or rearranging a display changes the desktop union.
        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.resizeToDesktop() }
            .store(in: &cancellables)
    }

    // MARK: - Geometry

    /// The union of every screen, in Cocoa global coordinates.
    private static func desktopFrame() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { $0.isEmpty ? $1.frame : $0.union($1.frame) }
    }

    private func resizeToDesktop() {
        window.setFrame(Self.desktopFrame(), display: true)
        overlayView.updateScale(window.backingScaleFactor)
        applySettings()
        followPointer()
    }

    /// Global screen coordinates → the overlay view's own coordinate space.
    private func viewPoint(_ global: NSPoint) -> CGPoint {
        let origin = window.frame.origin
        return CGPoint(x: global.x - origin.x, y: global.y - origin.y)
    }

    // MARK: - Settings → window

    private func applySettings() {
        overlayView.updateScale(window.backingScaleFactor)
        overlayView.configure(
            style: settings.ringStyle,
            diameter: CGFloat(settings.diameter),
            thickness: CGFloat(settings.thickness),
            color: settings.ringColor.nsColor,
            markerOpacity: Float(settings.opacity),
            markerVisible: settings.ringEnabled,
            trailLength: settings.trailEnabled ? Int(settings.trailLength) : 0,
            spotlight: settings.spotlightEnabled
                ? OverlayView.Spotlight(radius: CGFloat(settings.spotlightRadius),
                                        feather: CGFloat(settings.spotlightFeather),
                                        dimming: Float(settings.spotlightDimming))
                : nil)

        if settings.ringEnabled || settings.spotlightEnabled {
            window.orderFrontRegardless()
            overlayView.move(to: viewPoint(NSEvent.mouseLocation))
        } else {
            window.orderOut(nil)
        }

        // A settings change counts as activity: un-fade and restart the clock.
        wake()
        scheduleIdleTimer()
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
        guard settings.ringEnabled || settings.spotlightEnabled else { return }
        // NSEvent.mouseLocation is in global screen coordinates, which spans
        // every attached display — so the marker follows across screens.
        overlayView.move(to: viewPoint(NSEvent.mouseLocation))
        wake()
        scheduleIdleTimer()
    }

    private func clickPulse() {
        guard settings.ringEnabled, settings.pulseOnClick else { return }
        followPointer()
        overlayView.pulse()
    }

    // MARK: - Idle auto-hide

    /// Fades the marker out after a quiet spell so it stops being visual noise
    /// while you talk, and brings it straight back on the next movement. The
    /// spotlight is deliberately left alone — it is a deliberate mode, not an
    /// ambient hint.
    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard settings.idleHideEnabled, settings.ringEnabled else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: settings.idleTimeout,
                                         repeats: false) { _ in
            MainActor.assumeIsolated { Self.shared?.fadeForIdle() }
        }
    }

    private func fadeForIdle() {
        guard settings.idleHideEnabled, settings.ringEnabled else { return }
        idleHidden = true
        overlayView.setMarkerFaded(true)
    }

    private func wake() {
        guard idleHidden else { return }
        idleHidden = false
        overlayView.setMarkerFaded(false)
    }
}

/// Layer-backed view drawing the pointer marker, its fading trail, the click
/// pulse, and the spotlight dimming. Everything is a `CALayer`, so following
/// the pointer is a position assignment rather than a redraw.
final class OverlayView: NSView {
    struct Spotlight {
        var radius: CGFloat
        var feather: CGFloat
        var dimming: Float
    }

    /// Marker, trail, and pulse ride together so idle-fade and the opacity
    /// setting apply to the group in one place — and so the spotlight, which
    /// sits outside the group, is unaffected by both.
    private let markerGroup = CALayer()
    private let markLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private var trailLayers: [CAShapeLayer] = []
    private var nextTrailIndex = 0

    private let dimLayer = CALayer()
    private let dimMask = CAGradientLayer()

    private var style: RingStyle = .ring
    private var diameter: CGFloat = 64
    private var thickness: CGFloat = 5
    private var color: NSColor = RingColor.wispBlue.nsColor
    private var markerOpacity: Float = 0.85
    private var markerVisible = true
    private var spotlight: Spotlight?

    private var point: CGPoint = .zero
    private var lastTrailPoint: CGPoint = .zero
    private var lastTrailTime: CFTimeInterval = 0

    /// Extra room around the marker so the glow never clips at the layer edge.
    private var markSide: CGFloat { diameter + thickness * 4 + 60 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(markerGroup)

        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.mask = dimMask
        dimLayer.isHidden = true
        dimMask.type = .radial

        markerGroup.addSublayer(pulseLayer)
        markerGroup.addSublayer(markLayer)
        for shape in [markLayer, pulseLayer] {
            shape.fillColor = nil
        }
        pulseLayer.opacity = 0
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func updateScale(_ scale: CGFloat) {
        let s = max(1, scale)
        for l in [layer, markerGroup, markLayer, pulseLayer, dimLayer, dimMask].compactMap({ $0 }) {
            l.contentsScale = s
        }
        for l in trailLayers { l.contentsScale = s }
    }

    func configure(style: RingStyle, diameter: CGFloat, thickness: CGFloat,
                   color: NSColor, markerOpacity: Float, markerVisible: Bool,
                   trailLength: Int, spotlight: Spotlight?) {
        self.style = style
        self.diameter = diameter
        self.thickness = thickness
        self.color = color
        self.markerOpacity = markerOpacity
        self.markerVisible = markerVisible
        self.spotlight = spotlight
        resizeTrailPool(to: trailLength)
        rebuild()
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    // MARK: - Building

    private func resizeTrailPool(to count: Int) {
        // A fixed pool that gets reused; allocating a layer per mouse event
        // would mean dozens of allocations a second.
        while trailLayers.count > count {
            trailLayers.removeLast().removeFromSuperlayer()
        }
        while trailLayers.count < count {
            let ghost = CAShapeLayer()
            ghost.fillColor = nil
            ghost.opacity = 0
            ghost.contentsScale = layer?.contentsScale ?? 2
            markerGroup.insertSublayer(ghost, below: markLayer)
            trailLayers.append(ghost)
        }
        nextTrailIndex = 0
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        markerGroup.frame = bounds
        markerGroup.opacity = markerVisible ? markerOpacity : 0
        markerGroup.isHidden = !markerVisible

        let side = markSide
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        let (markPath, filled) = Self.path(for: style, diameter: diameter,
                                           thickness: thickness, in: box)

        markLayer.bounds = box
        markLayer.path = markPath
        markLayer.lineWidth = thickness
        markLayer.lineCap = .round
        markLayer.strokeColor = filled ? nil : color.cgColor
        markLayer.fillColor = filled ? color.cgColor : nil
        markLayer.shadowColor = color.cgColor
        markLayer.shadowOpacity = 0.9
        markLayer.shadowRadius = thickness * 1.4 + 5
        markLayer.shadowOffset = .zero
        markLayer.position = point

        // The pulse and trail always read as rings, whatever the marker style —
        // an expanding crosshair or a swarm of dots reads as noise.
        let circle = Self.ringPath(diameter: diameter, thickness: thickness, in: box)
        pulseLayer.bounds = box
        pulseLayer.path = circle
        pulseLayer.lineWidth = max(2, thickness * 0.8)
        pulseLayer.strokeColor = color.cgColor
        pulseLayer.position = point

        for ghost in trailLayers {
            ghost.bounds = box
            ghost.path = circle
            ghost.lineWidth = max(1, thickness * 0.6)
            ghost.strokeColor = color.cgColor
        }

        rebuildSpotlight()
    }

    private func rebuildSpotlight() {
        guard let spotlight else {
            dimLayer.isHidden = true
            return
        }
        dimLayer.isHidden = false
        dimLayer.frame = bounds
        dimLayer.opacity = spotlight.dimming
        dimMask.frame = bounds
        // A radial gradient mask gives the hole a soft edge for free: clear
        // through the clear radius, ramping to opaque across the feather.
        dimMask.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.cgColor]
        let outer = max(1, spotlight.radius + spotlight.feather)
        dimMask.locations = [0, NSNumber(value: Double(spotlight.radius / outer)), 1]
        positionSpotlight()
    }

    private func positionSpotlight() {
        guard let spotlight, bounds.width > 0, bounds.height > 0 else { return }
        let outer = max(1, spotlight.radius + spotlight.feather)
        // Gradient start/end points are in the layer's unit coordinate space,
        // y-up to match the unflipped view.
        let cx = point.x / bounds.width
        let cy = point.y / bounds.height
        dimMask.startPoint = CGPoint(x: cx, y: cy)
        dimMask.endPoint = CGPoint(x: cx + outer / bounds.width,
                                   y: cy + outer / bounds.height)
    }

    // MARK: - Paths

    private static func ringPath(diameter: CGFloat, thickness: CGFloat, in box: CGRect) -> CGPath {
        let radius = max(1, (diameter - thickness) / 2)
        return CGPath(ellipseIn: CGRect(x: box.midX - radius, y: box.midY - radius,
                                        width: radius * 2, height: radius * 2),
                      transform: nil)
    }

    /// Returns the marker path and whether it should be filled rather than
    /// stroked.
    private static func path(for style: RingStyle, diameter: CGFloat,
                             thickness: CGFloat, in box: CGRect) -> (CGPath, Bool) {
        switch style {
        case .ring:
            return (ringPath(diameter: diameter, thickness: thickness, in: box), false)

        case .doubleRing:
            let path = CGMutablePath()
            path.addPath(ringPath(diameter: diameter, thickness: thickness, in: box))
            path.addPath(ringPath(diameter: diameter * 0.55, thickness: thickness, in: box))
            return (path, false)

        case .dot:
            let radius = max(1, diameter * 0.3)
            return (CGPath(ellipseIn: CGRect(x: box.midX - radius, y: box.midY - radius,
                                             width: radius * 2, height: radius * 2),
                           transform: nil), true)

        case .crosshair:
            let path = CGMutablePath()
            let outer = max(2, diameter / 2)
            let gap = max(1, diameter * 0.16)   // leave the pointer itself visible
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                path.move(to: CGPoint(x: box.midX + gap * dx, y: box.midY + gap * dy))
                path.addLine(to: CGPoint(x: box.midX + outer * dx, y: box.midY + outer * dy))
            }
            path.addPath(ringPath(diameter: diameter * 0.34, thickness: thickness, in: box))
            return (path, false)
        }
    }

    // MARK: - Motion

    func move(to newPoint: CGPoint) {
        emitTrailGhost(from: point, to: newPoint)
        point = newPoint
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit animation on every mouse event
        markLayer.position = newPoint
        pulseLayer.position = newPoint
        positionSpotlight()
        CATransaction.commit()
    }

    /// Drops a fading ghost behind the pointer, throttled by both time and
    /// distance so a fast flick leaves a trail and a slow drift does not.
    private func emitTrailGhost(from old: CGPoint, to new: CGPoint) {
        guard markerVisible, !trailLayers.isEmpty else { return }
        let now = CACurrentMediaTime()
        guard now - lastTrailTime > 0.016 else { return }
        let dx = new.x - lastTrailPoint.x
        let dy = new.y - lastTrailPoint.y
        guard dx * dx + dy * dy > 64 else { return }   // at least 8pt of travel
        lastTrailTime = now
        lastTrailPoint = new

        let ghost = trailLayers[nextTrailIndex]
        nextTrailIndex = (nextTrailIndex + 1) % trailLayers.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghost.position = old
        ghost.opacity = 0
        CATransaction.commit()

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0.0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 0.95
        shrink.toValue = 0.45
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ghost.removeAnimation(forKey: "ghost")
        ghost.add(group, forKey: "ghost")
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

    /// Idle auto-hide: animate the whole marker group, leaving the spotlight up.
    func setMarkerFaded(_ faded: Bool) {
        guard markerVisible else { return }
        let target: Float = faded ? 0 : markerOpacity
        CATransaction.begin()
        CATransaction.setAnimationDuration(faded ? 0.6 : 0.15)
        markerGroup.opacity = target
        CATransaction.commit()
    }
}
