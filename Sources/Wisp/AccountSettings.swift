import AppKit
import SwiftUI

/// Optional registration with shafer.llc. Nothing in Wisp depends on it.
struct AccountSettings: View {
    private let license = LicenseModel.shared
    @State private var pastedKey = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: license.status == .registered ? "checkmark.seal.fill" : "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(license.status == .registered ? Color.green : Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) { statusText }
                    Spacer()
                    control
                }
            } footer: {
                Text("Registering is free and optional — every Wisp feature works without it. It links this Mac to your shafer.llc account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if license.status != .registered {
                Section("Have a key?") {
                    HStack {
                        TextField("Key", text: $pastedKey, prompt: Text("XXXXX-XXXXX-XXXXX-XXXXX"))
                            .font(.body.monospaced())
                            .onSubmit(activate)
                        Button("Activate", action: activate)
                            .disabled(pastedKey.trimmingCharacters(in: .whitespaces).isEmpty
                                      || license.status == .checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusText: some View {
        switch license.status {
        case .registered:
            Text("Registered")
            Text("Key ending \(license.key.map { String($0.suffix(5)) } ?? "")")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        case .checking:
            Text("Checking with shafer.llc…")
        case .unregistered:
            Text("Not registered")
            Text("Sign in on shafer.llc and Wisp picks up the key automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Not registered")
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var control: some View {
        switch license.status {
        case .registered:
            Menu("Manage") {
                Button("Open My Account on shafer.llc") { NSWorkspace.shared.open(license.accountURL) }
                Button("Unregister This Mac") { license.unregister() }
            }
            .fixedSize()
        case .checking:
            ProgressView().controlSize(.small)
        case .unregistered, .failed:
            Button("Register…") { license.register() }
        }
    }

    private func activate() {
        let key = pastedKey
        Task {
            await license.activate(key)
            if license.status == .registered { pastedKey = "" }
        }
    }
}
