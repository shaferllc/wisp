import AppKit
import XCTest

@testable import Wisp

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WispTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = tempDir.appendingPathComponent("Wisp", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMissingFileYieldsDefaults() {
        let store = SettingsStore.load(from: fileURL)
        XCTAssertTrue(store.ringEnabled)
        XCTAssertTrue(store.pulseOnClick)
        XCTAssertEqual(store.diameter, 64)
        XCTAssertEqual(store.thickness, 5)
        XCTAssertEqual(store.opacity, 0.85)
        XCTAssertEqual(store.ringColor, .wispBlue)
    }

    func testCorruptFileYieldsDefaults() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        let store = SettingsStore.load(from: fileURL)
        XCTAssertTrue(store.ringEnabled)
        XCTAssertEqual(store.ringColor, .wispBlue)
    }

    func testSaveLoadRoundTrip() {
        let store = SettingsStore.load(from: fileURL)
        store.ringEnabled = false
        store.pulseOnClick = false
        store.diameter = 90
        store.thickness = 8
        store.opacity = 0.5
        store.ringColor = .ember
        store.saveNow()

        let reloaded = SettingsStore.load(from: fileURL)
        XCTAssertFalse(reloaded.ringEnabled)
        XCTAssertFalse(reloaded.pulseOnClick)
        XCTAssertEqual(reloaded.diameter, 90)
        XCTAssertEqual(reloaded.thickness, 8)
        XCTAssertEqual(reloaded.opacity, 0.5)
        XCTAssertEqual(reloaded.ringColor, .ember)
    }

    func testSaveCreatesIntermediateDirectories() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let store = SettingsStore.load(from: fileURL)
        store.saveNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testOutOfRangeValuesAreClampedOnLoad() throws {
        let json = """
        {"ringEnabled": true, "pulseOnClick": true,
         "diameter": 9999, "thickness": 0.1, "opacity": -3,
         "ringColor": {"r": 0.5, "g": 0.5, "b": 0.5, "a": 1}}
        """
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)

        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.diameter, 200)
        XCTAssertEqual(store.thickness, 1)
        XCTAssertEqual(store.opacity, 0.1)
    }

    func testDebouncedSaveCoalescesAndWrites() {
        let store = SettingsStore.load(from: fileURL)
        store.diameter = 120
        store.thickness = 10

        // The debounce flushes on the next main-queue pass.
        let flushed = expectation(description: "debounced save ran")
        DispatchQueue.main.async { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let reloaded = SettingsStore.load(from: fileURL)
        XCTAssertEqual(reloaded.diameter, 120)
        XCTAssertEqual(reloaded.thickness, 10)
    }
}

final class RingColorTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let original = RingColor(r: 0.25, g: 0.5, b: 0.75, a: 1.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RingColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFromNSColorConvertsToSRGB() {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        let ring = RingColor.from(color)
        XCTAssertEqual(ring.r, 0.2, accuracy: 0.001)
        XCTAssertEqual(ring.g, 0.4, accuracy: 0.001)
        XCTAssertEqual(ring.b, 0.6, accuracy: 0.001)
        XCTAssertEqual(ring.a, 1.0, accuracy: 0.001)
    }

    func testFromCatalogColorDoesNotCrash() {
        // Catalog colors (e.g. labelColor) need the sRGB conversion path.
        let ring = RingColor.from(.labelColor)
        XCTAssertGreaterThanOrEqual(ring.a, 0)
        XCTAssertLessThanOrEqual(ring.a, 1)
    }

    func testNSColorRoundTrip() {
        let original = RingColor.orchid
        let back = RingColor.from(original.nsColor)
        XCTAssertEqual(back.r, original.r, accuracy: 0.001)
        XCTAssertEqual(back.g, original.g, accuracy: 0.001)
        XCTAssertEqual(back.b, original.b, accuracy: 0.001)
    }

    func testPresetsAreDistinct() {
        let colors = RingColor.presets.map(\.color)
        XCTAssertEqual(colors.count, 5)
        for (i, a) in colors.enumerated() {
            for b in colors[(i + 1)...] {
                XCTAssertNotEqual(a, b)
            }
        }
    }
}
