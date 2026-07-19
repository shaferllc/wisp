import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: store.ringColor.nsColor) },
            set: { store.ringColor = RingColor.from(NSColor($0)) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show ring", isOn: $store.ringEnabled)
                Toggle("Pulse on click", isOn: $store.pulseOnClick)
            } footer: {
                Text("Toggle the ring anywhere with ⌥⌘W.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Color") {
                HStack(spacing: 10) {
                    ForEach(RingColor.presets, id: \.name) { preset in
                        Button {
                            store.ringColor = preset.color
                        } label: {
                            Circle()
                                .fill(Color(nsColor: preset.color.nsColor))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(
                                        store.ringColor == preset.color
                                            ? Color.primary.opacity(0.8) : Color.clear,
                                        lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                    Spacer()
                    ColorPicker("Custom", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom color")
                }
            }

            Section("Ring") {
                LabeledContent("Size") {
                    Slider(value: $store.diameter, in: 30...160)
                }
                LabeledContent("Thickness") {
                    Slider(value: $store.thickness, in: 2...14)
                }
                LabeledContent("Opacity") {
                    Slider(value: $store.opacity, in: 0.2...1.0)
                }
            }

            Section {
                Text("The ring is visible only on your display — never in screenshots, screen recordings, or screen sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 380)
    }
}

/// Hosts the SwiftUI settings form in a plain titled window; created lazily
/// and reused, so closing it just hides it.
@MainActor
final class SettingsWindowController {
    private let store: SettingsStore
    private var window: NSWindow?

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero,
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Wisp Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            w.setContentSize(NSSize(width: 400, height: 380))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
