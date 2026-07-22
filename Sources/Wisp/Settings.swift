import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// A ring color stored as sRGB components so it round-trips through JSON.
struct RingColor: Codable, Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    static func from(_ color: NSColor) -> RingColor {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.white.usingColorSpace(.sRGB)!
        return RingColor(r: c.redComponent, g: c.greenComponent,
                         b: c.blueComponent, a: c.alphaComponent)
    }

    // Presets
    static let wispBlue = RingColor(r: 0.36, g: 0.78, b: 1.00, a: 1.0)
    static let ember    = RingColor(r: 1.00, g: 0.60, b: 0.20, a: 1.0)
    static let aurora   = RingColor(r: 0.30, g: 0.95, b: 0.58, a: 1.0)
    static let orchid   = RingColor(r: 0.95, g: 0.35, b: 0.80, a: 1.0)
    static let lantern  = RingColor(r: 1.00, g: 0.88, b: 0.35, a: 1.0)

    static let presets: [(name: String, color: RingColor)] = [
        ("Wisp Blue", .wispBlue),
        ("Ember", .ember),
        ("Aurora", .aurora),
        ("Orchid", .orchid),
        ("Lantern", .lantern),
    ]
}

/// How the pointer marker is drawn.
enum RingStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case ring
    case doubleRing
    case dot
    case crosshair

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring:       return "Ring"
        case .doubleRing: return "Double Ring"
        case .dot:        return "Dot"
        case .crosshair:  return "Crosshair"
        }
    }
}

/// A global hot key, stored as a virtual key code plus a Carbon modifier mask
/// so it round-trips through JSON and feeds `RegisterEventHotKey` directly.
struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let toggleRing = KeyCombo(keyCode: UInt32(kVK_ANSI_W),
                                     modifiers: UInt32(cmdKey | optionKey))
    static let toggleSpotlight = KeyCombo(keyCode: UInt32(kVK_ANSI_S),
                                          modifiers: UInt32(cmdKey | optionKey))

    /// A combo needs at least one modifier beyond shift, or registering it
    /// would swallow ordinary typing system-wide.
    var isValid: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    /// e.g. "⌥⌘W" — macOS orders the glyphs ⌃⌥⇧⌘.
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var f = NSEvent.ModifierFlags()
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey)  != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey)   != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey)     != 0 { f.insert(.command) }
        return f
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    /// Virtual key codes with no printable character.
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←",
        kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyName(_ code: UInt32) -> String {
        if let named = namedKeys[Int(code)] { return named }
        return layoutCharacter(for: code)?.uppercased() ?? "Key \(code)"
    }

    /// Translates an unmodified key code through the active keyboard layout, so
    /// an AZERTY layout labels the same key "A" where QWERTY says "Q".
    private static func layoutCharacter(for code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()),
                                  UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Defaults and the ranges both the UI and the loader honour, kept in one place
/// so a slider bound can never drift from the clamp applied on load.
enum SettingsDefaults {
    static let ringEnabled = true
    static let pulseOnClick = true
    static let diameter: Double = 64
    static let thickness: Double = 5
    static let opacity: Double = 0.85
    static let ringColor = RingColor.wispBlue
    static let ringStyle = RingStyle.ring

    static let trailEnabled = false
    static let trailLength: Double = 8

    static let idleHideEnabled = false
    static let idleTimeout: Double = 5

    static let spotlightEnabled = false
    static let spotlightDimming: Double = 0.55
    static let spotlightRadius: Double = 140
    static let spotlightFeather: Double = 70

    static let keystrokesEnabled = false
    static let keystrokesShared = true

    static let ringHotKey = KeyCombo.toggleRing
    static let spotlightHotKey = KeyCombo.toggleSpotlight

    static let diameterRange: ClosedRange<Double> = 24...200
    static let thicknessRange: ClosedRange<Double> = 1...20
    static let opacityRange: ClosedRange<Double> = 0.1...1.0
    static let trailLengthRange: ClosedRange<Double> = 2...24
    static let idleTimeoutRange: ClosedRange<Double> = 1...60
    static let dimmingRange: ClosedRange<Double> = 0.1...0.95
    static let spotlightRadiusRange: ClosedRange<Double> = 40...500
    static let spotlightFeatherRange: ClosedRange<Double> = 0...250
}

/// All user-tweakable state, persisted as JSON under
/// ~/Library/Application Support/Wisp/settings.json.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var ringEnabled = SettingsDefaults.ringEnabled { didSet { scheduleSave() } }
    @Published var pulseOnClick = SettingsDefaults.pulseOnClick { didSet { scheduleSave() } }
    @Published var diameter = SettingsDefaults.diameter { didSet { scheduleSave() } }
    @Published var thickness = SettingsDefaults.thickness { didSet { scheduleSave() } }
    @Published var opacity = SettingsDefaults.opacity { didSet { scheduleSave() } }
    @Published var ringColor = SettingsDefaults.ringColor { didSet { scheduleSave() } }
    @Published var ringStyle = SettingsDefaults.ringStyle { didSet { scheduleSave() } }

    @Published var trailEnabled = SettingsDefaults.trailEnabled { didSet { scheduleSave() } }
    @Published var trailLength = SettingsDefaults.trailLength { didSet { scheduleSave() } }

    @Published var idleHideEnabled = SettingsDefaults.idleHideEnabled { didSet { scheduleSave() } }
    @Published var idleTimeout = SettingsDefaults.idleTimeout { didSet { scheduleSave() } }

    @Published var spotlightEnabled = SettingsDefaults.spotlightEnabled { didSet { scheduleSave() } }
    @Published var spotlightDimming = SettingsDefaults.spotlightDimming { didSet { scheduleSave() } }
    @Published var spotlightRadius = SettingsDefaults.spotlightRadius { didSet { scheduleSave() } }
    @Published var spotlightFeather = SettingsDefaults.spotlightFeather { didSet { scheduleSave() } }

    /// Keystroke display is the one feature that needs Accessibility, so it is
    /// opt-in and off by default — everything else stays permission-free.
    @Published var keystrokesEnabled = SettingsDefaults.keystrokesEnabled { didSet { scheduleSave() } }
    /// Unlike the ring, the keystroke HUD is usually *for* the audience, so it
    /// defaults to being visible in recordings and screen shares.
    @Published var keystrokesShared = SettingsDefaults.keystrokesShared { didSet { scheduleSave() } }

    @Published var ringHotKey = SettingsDefaults.ringHotKey { didSet { scheduleSave() } }
    @Published var spotlightHotKey = SettingsDefaults.spotlightHotKey { didSet { scheduleSave() } }

    /// Not persisted here — the login item's real state lives in the system
    /// database, so this mirrors `SMAppService` instead of the JSON file.
    @Published var launchAtLogin = false

    private struct Persisted: Codable {
        var ringEnabled: Bool
        var pulseOnClick: Bool
        var diameter: Double
        var thickness: Double
        var opacity: Double
        var ringColor: RingColor
        var ringStyle: RingStyle
        var trailEnabled: Bool
        var trailLength: Double
        var idleHideEnabled: Bool
        var idleTimeout: Double
        var spotlightEnabled: Bool
        var spotlightDimming: Double
        var spotlightRadius: Double
        var spotlightFeather: Double
        var keystrokesEnabled: Bool
        var keystrokesShared: Bool
        var ringHotKey: KeyCombo
        var spotlightHotKey: KeyCombo

        @MainActor
        init(from store: SettingsStore) {
            ringEnabled = store.ringEnabled
            pulseOnClick = store.pulseOnClick
            diameter = store.diameter
            thickness = store.thickness
            opacity = store.opacity
            ringColor = store.ringColor
            ringStyle = store.ringStyle
            trailEnabled = store.trailEnabled
            trailLength = store.trailLength
            idleHideEnabled = store.idleHideEnabled
            idleTimeout = store.idleTimeout
            spotlightEnabled = store.spotlightEnabled
            spotlightDimming = store.spotlightDimming
            spotlightRadius = store.spotlightRadius
            spotlightFeather = store.spotlightFeather
            keystrokesEnabled = store.keystrokesEnabled
            keystrokesShared = store.keystrokesShared
            ringHotKey = store.ringHotKey
            spotlightHotKey = store.spotlightHotKey
        }

        /// Every key is optional on the way in: a file written by an older Wisp
        /// is missing the newer ones, and an unrecognised `ringStyle` should
        /// fall back rather than discard the whole file.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = SettingsDefaults.self
            ringEnabled = try c.decodeIfPresent(Bool.self, forKey: .ringEnabled) ?? d.ringEnabled
            pulseOnClick = try c.decodeIfPresent(Bool.self, forKey: .pulseOnClick) ?? d.pulseOnClick
            diameter = try c.decodeIfPresent(Double.self, forKey: .diameter) ?? d.diameter
            thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? d.thickness
            opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
            ringColor = try c.decodeIfPresent(RingColor.self, forKey: .ringColor) ?? d.ringColor
            ringStyle = (try? c.decodeIfPresent(RingStyle.self, forKey: .ringStyle)) ?? d.ringStyle
            trailEnabled = try c.decodeIfPresent(Bool.self, forKey: .trailEnabled) ?? d.trailEnabled
            trailLength = try c.decodeIfPresent(Double.self, forKey: .trailLength) ?? d.trailLength
            idleHideEnabled = try c.decodeIfPresent(Bool.self, forKey: .idleHideEnabled) ?? d.idleHideEnabled
            idleTimeout = try c.decodeIfPresent(Double.self, forKey: .idleTimeout) ?? d.idleTimeout
            spotlightEnabled = try c.decodeIfPresent(Bool.self, forKey: .spotlightEnabled) ?? d.spotlightEnabled
            spotlightDimming = try c.decodeIfPresent(Double.self, forKey: .spotlightDimming) ?? d.spotlightDimming
            spotlightRadius = try c.decodeIfPresent(Double.self, forKey: .spotlightRadius) ?? d.spotlightRadius
            spotlightFeather = try c.decodeIfPresent(Double.self, forKey: .spotlightFeather) ?? d.spotlightFeather
            keystrokesEnabled = try c.decodeIfPresent(Bool.self, forKey: .keystrokesEnabled) ?? d.keystrokesEnabled
            keystrokesShared = try c.decodeIfPresent(Bool.self, forKey: .keystrokesShared) ?? d.keystrokesShared
            ringHotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .ringHotKey) ?? d.ringHotKey
            spotlightHotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .spotlightHotKey) ?? d.spotlightHotKey
        }
    }

    /// Where settings live; tests pass a temporary URL instead.
    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wisp", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private var fileURL = SettingsStore.defaultFileURL

    static func load(from url: URL = defaultFileURL) -> SettingsStore {
        let store = SettingsStore()
        store.fileURL = url
        if let data = try? Data(contentsOf: url),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            let d = SettingsDefaults.self
            store.ringEnabled = p.ringEnabled
            store.pulseOnClick = p.pulseOnClick
            store.diameter = p.diameter.clamped(to: d.diameterRange)
            store.thickness = p.thickness.clamped(to: d.thicknessRange)
            store.opacity = p.opacity.clamped(to: d.opacityRange)
            store.ringColor = p.ringColor
            store.ringStyle = p.ringStyle
            store.trailEnabled = p.trailEnabled
            store.trailLength = p.trailLength.clamped(to: d.trailLengthRange).rounded()
            store.idleHideEnabled = p.idleHideEnabled
            store.idleTimeout = p.idleTimeout.clamped(to: d.idleTimeoutRange)
            store.spotlightEnabled = p.spotlightEnabled
            store.spotlightDimming = p.spotlightDimming.clamped(to: d.dimmingRange)
            store.spotlightRadius = p.spotlightRadius.clamped(to: d.spotlightRadiusRange)
            store.spotlightFeather = p.spotlightFeather.clamped(to: d.spotlightFeatherRange)
            store.keystrokesEnabled = p.keystrokesEnabled
            store.keystrokesShared = p.keystrokesShared
            store.ringHotKey = p.ringHotKey.isValid ? p.ringHotKey : d.ringHotKey
            store.spotlightHotKey = p.spotlightHotKey.isValid ? p.spotlightHotKey : d.spotlightHotKey
        }
        store.saveScheduled = false // loading is not a user edit
        return store
    }

    private var saveScheduled = false

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.saveScheduled else { return }
            self.saveScheduled = false
            self.save()
        }
    }

    /// Writes immediately, cancelling any pending debounced save. The app
    /// only saves via the debounce; tests call this to flush deterministically.
    func saveNow() {
        saveScheduled = false
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Persisted(from: self)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
