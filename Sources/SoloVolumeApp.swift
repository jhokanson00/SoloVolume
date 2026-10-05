import SwiftUI

@main
struct SoloVolumeApp: App {
    @StateObject private var model = VolumeModel()

    init() {
        // Start the updater at launch so its daily check runs even if the menu is never opened.
        _ = Updates.updater
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.iconName)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var model: VolumeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selectedName).font(.headline)
                Spacer()
                Text(model.muted ? "Muted" : "\(Int((model.volume * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    model.muted.toggle()
                } label: {
                    Image(systemName: model.iconName).frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(model.muted ? "Unmute" : "Mute")

                Slider(value: $model.volume, in: 0...1)
                    .disabled(model.muted)
            }

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Picker("Device", selection: $model.selectedUID) {
                ForEach(model.devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }

            Toggle("Use keyboard volume keys", isOn: $model.volumeKeysEnabled)
            if model.volumeKeysNeedPermission {
                HStack(alignment: .firstTextBaseline) {
                    Text("Needs Accessibility permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") { model.openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }

            Toggle("Launch at login", isOn: $model.launchAtLogin)

            HStack {
                Button("Check for Updates…") { Updates.checkForUpdates() }
                Spacer()
                Button("Quit SoloVolume") { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
