import XCTest

@testable import Wisp

final class LicenseTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testAcceptsKeyWhenStateMatches() {
        let key = LicenseModel.activationKey(
            from: url("wisp://activate?key=ABCDE-12345-FGHIJ-67890&state=s1"), expectedState: "s1")
        XCTAssertEqual(key, "ABCDE-12345-FGHIJ-67890")
    }

    func testRejectsForeignOrStaleHandoffs() {
        let link = url("wisp://activate?key=ABCDE&state=s1")
        // A page linking to wisp:// with a state we never issued.
        XCTAssertNil(LicenseModel.activationKey(from: link, expectedState: "other"))
        // No handoff in progress (or it expired).
        XCTAssertNil(LicenseModel.activationKey(from: link, expectedState: nil))
        // Missing state or key, wrong host or scheme (another app's handoff).
        XCTAssertNil(LicenseModel.activationKey(from: url("wisp://activate?key=ABCDE"), expectedState: "s1"))
        XCTAssertNil(LicenseModel.activationKey(from: url("wisp://activate?key=&state=s1"), expectedState: "s1"))
        XCTAssertNil(LicenseModel.activationKey(from: url("wisp://other?key=ABCDE&state=s1"), expectedState: "s1"))
        XCTAssertNil(LicenseModel.activationKey(from: url("ledge://activate?key=ABCDE&state=s1"), expectedState: "s1"))
    }

    func testDeviceHashIsStableAndNotTheRawID() throws {
        let hash = try XCTUnwrap(LicenseModel.deviceHash())
        XCTAssertEqual(hash, LicenseModel.deviceHash())
        XCTAssertEqual(hash.count, 64)
        XCTAssertFalse(hash.contains("-"))
    }
}
