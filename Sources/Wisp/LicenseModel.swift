import AppKit
import CryptoKit
import Foundation
import IOKit
import Observation

/// Optional registration with shafer.llc. Nothing in Wisp is gated on it;
/// registering links this Mac to the user's account there.
///
/// `register()` opens shafer.llc/account/activate in the browser. After sign-in
/// the site redirects to wisp://activate?key=…&state=…, which arrives in
/// `handle(_:)`. The key is checked with POST /api/licenses/verify, kept in the
/// keychain, and re-checked on the server-set `recheck_after` cadence.
@Observable
@MainActor
final class LicenseModel {
    static let shared = LicenseModel()

    enum Status: Equatable {
        case unregistered
        case checking
        case registered
        case failed(String)
    }

    private(set) var status: Status = .unregistered
    private(set) var key: String?

    nonisolated static let product = "wisp"
    nonisolated static let site = URL(string: "https://shafer.llc")!
    private static let keychainAccount = "shafer-license-key"
    /// How long a browser handoff stays open. The key normally comes back in
    /// seconds, but waiting on the sign-in email can take a few minutes.
    private static let stateLifetime: TimeInterval = 15 * 60

    private let defaults: UserDefaults
    private var recheckTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = Keychain.load(Self.keychainAccount)
        status = key == nil ? .unregistered : .registered
    }

    var accountURL: URL { Self.site.appendingPathComponent("account") }

    // MARK: Browser handoff

    func register() {
        let state = UUID().uuidString
        // Persisted, so relaunching mid-handoff doesn't strand the key the
        // site sends back.
        defaults.set(state, forKey: "licenseState")
        defaults.set(Date().timeIntervalSince1970, forKey: "licenseStateAt")
        var c = URLComponents(url: Self.site.appendingPathComponent("account/activate"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "product", value: Self.product),
                        URLQueryItem(name: "state", value: state)]
        NSWorkspace.shared.open(c.url!)
    }

    /// Handles wisp://activate?key=…&state=… from the browser.
    func handle(_ url: URL) {
        let fresh = Date().timeIntervalSince1970 - defaults.double(forKey: "licenseStateAt") < Self.stateLifetime
        let expected = fresh ? defaults.string(forKey: "licenseState") : nil
        guard let key = Self.activationKey(from: url, expectedState: expected) else {
            if url.host == "activate" {
                status = .failed("That sign-in link has expired. Click Register to try again.")
            }
            return
        }
        defaults.removeObject(forKey: "licenseState")
        Task { await activate(key) }
    }

    /// The key from wisp://activate?key=…&state=…, but only when `state` is the
    /// handoff we started, so a web page can't push a key into Wisp by
    /// linking to wisp://activate.
    nonisolated static func activationKey(from url: URL, expectedState: String?) -> String? {
        guard url.scheme == "wisp", url.host == "activate",
              let expectedState,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "state" })?.value == expectedState,
              let key = items.first(where: { $0.name == "key" })?.value,
              !key.isEmpty else { return nil }
        return key
    }

    // MARK: Verification

    /// Checks a key with shafer.llc and keeps it only if valid. Also backs the
    /// paste-a-key field.
    func activate(_ raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return }
        status = .checking
        do {
            let result = try await Self.verify(key)
            guard result.valid else {
                status = .failed("shafer.llc didn't recognize that key.")
                return
            }
            Keychain.save(key, account: Self.keychainAccount)
            self.key = key
            status = .registered
            scheduleNextCheck(after: result.recheckAfter)
        } catch {
            status = .failed("Couldn't reach shafer.llc. Check your connection and try again.")
        }
    }

    func unregister() {
        Keychain.delete(Self.keychainAccount)
        key = nil
        status = .unregistered
    }

    /// Re-verify the stored key whenever the server's recheck interval passes.
    /// Being offline or a server error keeps the registration; only an explicit
    /// "not valid" (say, the key was regenerated on the account page) clears it.
    func startRechecking() {
        recheckIfDue()
        recheckTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheckIfDue() }
        }
    }

    private func recheckIfDue() {
        guard let key, Date().timeIntervalSince1970 >= defaults.double(forKey: "licenseNextCheck") else { return }
        Task {
            guard let result = try? await Self.verify(key) else { return }
            if result.valid {
                scheduleNextCheck(after: result.recheckAfter)
            } else {
                unregister()
                status = .failed("This Mac's registration is no longer valid. Register again to relink it.")
            }
        }
    }

    private func scheduleNextCheck(after seconds: Int) {
        defaults.set(Date().timeIntervalSince1970 + Double(seconds), forKey: "licenseNextCheck")
    }

    struct VerifyResult: Decodable, Sendable {
        let valid: Bool
        let recheckAfter: Int
        enum CodingKeys: String, CodingKey { case valid, recheckAfter = "recheck_after" }
    }

    nonisolated static func verify(_ key: String) async throws -> VerifyResult {
        var request = URLRequest(url: site.appendingPathComponent("api/licenses/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body = ["key": key, "product": product, "device_name": Host.current().localizedName ?? "Mac"]
        if let device = deviceHash() { body["device"] = device }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(VerifyResult.self, from: data)
    }

    /// A one-way hash of the Mac's hardware UUID: stable per Mac, never the raw ID.
    nonisolated static func deviceHash() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        else { return nil }
        return SHA256.hash(data: Data("wisp:\(uuid)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
