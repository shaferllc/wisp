import AppKit
import Carbon.HIToolbox
import XCTest

@testable import Wisp

/// Covers the settings added after 0.1: their defaults, their persistence, and
/// what happens to a file written by a Wisp that had never heard of them.
@MainActor
final class SettingsMigrationTests: XCTestCase {
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

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)
    }

    // MARK: - Defaults

    func testNewFeaturesDefaultToOff() {
        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.ringStyle, .ring)
        XCTAssertFalse(store.trailEnabled)
        XCTAssertFalse(store.idleHideEnabled)
        XCTAssertFalse(store.spotlightEnabled)
        XCTAssertFalse(store.keystrokesEnabled)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(store.ringHotKey, .toggleRing)
        XCTAssertEqual(store.spotlightHotKey, .toggleSpotlight)
    }

    /// The keystroke HUD is for the audience, so it is captured by default —
    /// the opposite of every other Wisp surface.
    func testKeystrokeHUDDefaultsToBeingShared() {
        XCTAssertTrue(SettingsStore.load(from: fileURL).keystrokesShared)
    }

    // MARK: - Round trip

    func testAllNewFieldsRoundTrip() {
        let store = SettingsStore.load(from: fileURL)
        store.ringStyle = .crosshair
        store.trailEnabled = true
        store.trailLength = 14
        store.idleHideEnabled = true
        store.idleTimeout = 12
        store.spotlightEnabled = true
        store.spotlightDimming = 0.7
        store.spotlightRadius = 220
        store.spotlightFeather = 40
        store.keystrokesEnabled = true
        store.keystrokesShared = false
        store.ringHotKey = KeyCombo(keyCode: UInt32(kVK_ANSI_R),
                                    modifiers: UInt32(controlKey | optionKey))
        store.spotlightHotKey = KeyCombo(keyCode: UInt32(kVK_F7),
                                         modifiers: UInt32(cmdKey))
        store.saveNow()

        let reloaded = SettingsStore.load(from: fileURL)
        XCTAssertEqual(reloaded.ringStyle, .crosshair)
        XCTAssertTrue(reloaded.trailEnabled)
        XCTAssertEqual(reloaded.trailLength, 14)
        XCTAssertTrue(reloaded.idleHideEnabled)
        XCTAssertEqual(reloaded.idleTimeout, 12)
        XCTAssertTrue(reloaded.spotlightEnabled)
        XCTAssertEqual(reloaded.spotlightDimming, 0.7)
        XCTAssertEqual(reloaded.spotlightRadius, 220)
        XCTAssertEqual(reloaded.spotlightFeather, 40)
        XCTAssertTrue(reloaded.keystrokesEnabled)
        XCTAssertFalse(reloaded.keystrokesShared)
        XCTAssertEqual(reloaded.ringHotKey, store.ringHotKey)
        XCTAssertEqual(reloaded.spotlightHotKey, store.spotlightHotKey)
    }

    /// The login item's truth is the system database, not this file, so it must
    /// not survive a save/load cycle.
    func testLaunchAtLoginIsNotPersisted() {
        let store = SettingsStore.load(from: fileURL)
        store.launchAtLogin = true
        store.saveNow()
        XCTAssertFalse(SettingsStore.load(from: fileURL).launchAtLogin)
    }

    // MARK: - Reading an older file

    func testFileFromOlderVersionKeepsItsValuesAndDefaultsTheRest() throws {
        // Exactly the key set Wisp 0.1 wrote.
        try write("""
        {"diameter": 90, "opacity": 0.5, "pulseOnClick": false,
         "ringColor": {"a": 1, "b": 0.2, "g": 0.6, "r": 1},
         "ringEnabled": false, "thickness": 8}
        """)

        let store = SettingsStore.load(from: fileURL)
        XCTAssertFalse(store.ringEnabled)
        XCTAssertFalse(store.pulseOnClick)
        XCTAssertEqual(store.diameter, 90)
        XCTAssertEqual(store.thickness, 8)
        XCTAssertEqual(store.opacity, 0.5)
        XCTAssertEqual(store.ringColor, .ember)

        XCTAssertEqual(store.ringStyle, .ring)
        XCTAssertFalse(store.trailEnabled)
        XCTAssertFalse(store.spotlightEnabled)
        XCTAssertEqual(store.ringHotKey, .toggleRing)
        XCTAssertEqual(store.spotlightHotKey, .toggleSpotlight)
    }

    func testUnknownRingStyleFallsBackWithoutLosingTheFile() throws {
        try write("""
        {"diameter": 100, "ringStyle": "hexagon"}
        """)
        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.ringStyle, .ring)
        XCTAssertEqual(store.diameter, 100, "the rest of the file should survive")
    }

    func testHotKeyWithoutARealModifierFallsBackToTheDefault() throws {
        // A bare or shift-only combo would hijack ordinary typing everywhere.
        try write("""
        {"ringHotKey": {"keyCode": 13, "modifiers": 0},
         "spotlightHotKey": {"keyCode": 1, "modifiers": 512}}
        """)
        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.ringHotKey, .toggleRing)
        XCTAssertEqual(store.spotlightHotKey, .toggleSpotlight)
    }

    func testMalformedHotKeyFallsBackToTheDefault() throws {
        try write("""
        {"ringHotKey": "cmd-w", "diameter": 70}
        """)
        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.ringHotKey, .toggleRing)
    }

    // MARK: - Clamping

    func testNewNumericFieldsAreClampedOnLoad() throws {
        try write("""
        {"trailLength": 9999, "idleTimeout": 0, "spotlightDimming": 5,
         "spotlightRadius": -20, "spotlightFeather": 9999}
        """)
        let d = SettingsDefaults.self
        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.trailLength, d.trailLengthRange.upperBound)
        XCTAssertEqual(store.idleTimeout, d.idleTimeoutRange.lowerBound)
        XCTAssertEqual(store.spotlightDimming, d.dimmingRange.upperBound)
        XCTAssertEqual(store.spotlightRadius, d.spotlightRadiusRange.lowerBound)
        XCTAssertEqual(store.spotlightFeather, d.spotlightFeatherRange.upperBound)
    }

    /// The trail pool is sized with `Int(trailLength)`, so a fractional value
    /// from a hand-edited file must not survive.
    func testTrailLengthLoadsAsAWholeNumber() throws {
        try write(#"{"trailLength": 7.6}"#)
        let store = SettingsStore.load(from: fileURL)
        XCTAssertEqual(store.trailLength, store.trailLength.rounded())
    }

    func testEveryDefaultSitsInsideItsOwnRange() {
        let d = SettingsDefaults.self
        XCTAssertTrue(d.diameterRange.contains(d.diameter))
        XCTAssertTrue(d.thicknessRange.contains(d.thickness))
        XCTAssertTrue(d.opacityRange.contains(d.opacity))
        XCTAssertTrue(d.trailLengthRange.contains(d.trailLength))
        XCTAssertTrue(d.idleTimeoutRange.contains(d.idleTimeout))
        XCTAssertTrue(d.dimmingRange.contains(d.spotlightDimming))
        XCTAssertTrue(d.spotlightRadiusRange.contains(d.spotlightRadius))
        XCTAssertTrue(d.spotlightFeatherRange.contains(d.spotlightFeather))
    }
}
