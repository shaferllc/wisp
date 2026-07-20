import AppKit
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

/// All user-tweakable state, persisted as JSON under
/// ~/Library/Application Support/Wisp/settings.json.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var ringEnabled: Bool = true { didSet { scheduleSave() } }
    @Published var pulseOnClick: Bool = true { didSet { scheduleSave() } }
    @Published var diameter: Double = 64 { didSet { scheduleSave() } }
    @Published var thickness: Double = 5 { didSet { scheduleSave() } }
    @Published var opacity: Double = 0.85 { didSet { scheduleSave() } }
    @Published var ringColor: RingColor = .wispBlue { didSet { scheduleSave() } }

    private struct Persisted: Codable {
        var ringEnabled: Bool
        var pulseOnClick: Bool
        var diameter: Double
        var thickness: Double
        var opacity: Double
        var ringColor: RingColor
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
            store.ringEnabled = p.ringEnabled
            store.pulseOnClick = p.pulseOnClick
            store.diameter = p.diameter.clamped(to: 24...200)
            store.thickness = p.thickness.clamped(to: 1...20)
            store.opacity = p.opacity.clamped(to: 0.1...1.0)
            store.ringColor = p.ringColor
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
        let p = Persisted(ringEnabled: ringEnabled, pulseOnClick: pulseOnClick,
                          diameter: diameter, thickness: thickness,
                          opacity: opacity, ringColor: ringColor)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(p) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
