import AppKit
import Carbon.HIToolbox
import XCTest

@testable import Wisp

final class KeyComboTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let original = KeyCombo(keyCode: UInt32(kVK_ANSI_K),
                                modifiers: UInt32(cmdKey | shiftKey))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), original)
    }

    func testDefaultsAreValid() {
        XCTAssertTrue(KeyCombo.toggleRing.isValid)
        XCTAssertTrue(KeyCombo.toggleSpotlight.isValid)
        XCTAssertNotEqual(KeyCombo.toggleRing, KeyCombo.toggleSpotlight)
    }

    func testBareKeyIsInvalid() {
        // No modifier at all would swallow the plain key system-wide.
        XCTAssertFalse(KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: 0).isValid)
    }

    func testShiftAloneIsInvalid() {
        // Shift+W is just "W" as far as typing is concerned.
        XCTAssertFalse(KeyCombo(keyCode: UInt32(kVK_ANSI_W),
                                modifiers: UInt32(shiftKey)).isValid)
    }

    func testSingleRealModifierIsValid() {
        for modifier in [cmdKey, optionKey, controlKey] {
            XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_ANSI_W),
                                   modifiers: UInt32(modifier)).isValid,
                          "modifier \(modifier) should be enough")
        }
    }

    func testDisplayUsesStandardGlyphOrder() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_W),
                             modifiers: UInt32(cmdKey | optionKey | shiftKey | controlKey))
        XCTAssertEqual(combo.display, "⌃⌥⇧⌘W")
    }

    func testDefaultRingComboDisplay() {
        XCTAssertEqual(KeyCombo.toggleRing.display, "⌥⌘W")
        XCTAssertEqual(KeyCombo.toggleSpotlight.display, "⌥⌘S")
    }

    func testNamedKeysHaveSymbols() {
        XCTAssertEqual(KeyCombo.keyName(UInt32(kVK_Space)), "Space")
        XCTAssertEqual(KeyCombo.keyName(UInt32(kVK_Escape)), "⎋")
        XCTAssertEqual(KeyCombo.keyName(UInt32(kVK_LeftArrow)), "←")
        XCTAssertEqual(KeyCombo.keyName(UInt32(kVK_F5)), "F5")
    }

    func testKeyNameNeverReturnsEmpty() {
        // Whatever the layout, every code must render as *something* so a
        // recorded shortcut is never displayed as a blank field.
        for code in UInt32(0)...UInt32(126) {
            XCTAssertFalse(KeyCombo.keyName(code).isEmpty, "code \(code) rendered empty")
        }
    }

    func testCarbonModifiersRoundTripThroughEventFlags() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_W),
                             modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        XCTAssertEqual(KeyCombo.carbonModifiers(from: combo.eventModifiers), combo.modifiers)
    }

    func testCarbonModifiersIgnoreIrrelevantFlags() {
        // Caps lock and the numeric-keypad flag are not part of a shortcut.
        let flags: NSEvent.ModifierFlags = [.command, .capsLock, .numericPad, .function]
        XCTAssertEqual(KeyCombo.carbonModifiers(from: flags), UInt32(cmdKey))
    }
}

final class RingStyleTests: XCTestCase {
    func testAllStylesRoundTripThroughJSON() throws {
        for style in RingStyle.allCases {
            let data = try JSONEncoder().encode(style)
            XCTAssertEqual(try JSONDecoder().decode(RingStyle.self, from: data), style)
        }
    }

    func testLabelsArePresentAndDistinct() {
        let labels = RingStyle.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, RingStyle.allCases.count)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }
}
