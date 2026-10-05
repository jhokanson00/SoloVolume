import AppKit
import CoreAudio
import ServiceManagement

@MainActor
final class VolumeModel: ObservableObject {
    @Published var volume: Double {
        didSet { UserDefaults.standard.set(volume, forKey: "volume"); applyLevel() }
    }
    @Published var muted: Bool {
        didSet { UserDefaults.standard.set(muted, forKey: "muted"); applyLevel() }
    }
    @Published var selectedUID: String? {
        didSet { UserDefaults.standard.set(selectedUID, forKey: "deviceUID"); reconcile() }
    }
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var status = "Starting…"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                status = "Login item: \(error.localizedDescription)"
            }
        }
    }

    @Published var volumeKeysEnabled: Bool {
        didSet { UserDefaults.standard.set(volumeKeysEnabled, forKey: "volumeKeys"); updateVolumeKeys(prompt: true) }
    }
    @Published private(set) var volumeKeysNeedPermission = false

    let engine = VolumeEngine()
    private let keys = VolumeKeyInterceptor()
    private let hud = VolumeHUD()
    private var permissionTimer: Timer?
    private var diagnosticsTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        volume = defaults.object(forKey: "volume") as? Double ?? 0.5
        muted = defaults.bool(forKey: "muted")
        selectedUID = defaults.string(forKey: "deviceUID")
        volumeKeysEnabled = defaults.object(forKey: "volumeKeys") as? Bool ?? true

        refreshDevices()
        if selectedUID == nil {
            selectedUID = devices.first { $0.name.localizedCaseInsensitiveContains("Scarlett") }?.id
        }
        applyLevel()
        reconcile()

        var addr = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(systemObject, &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshDevices()
                self?.reconcile()
            }
        }

        keys.shouldHandle = { [weak self] in
            // Only take over the keys while sound is actually going to our device.
            MainActor.assumeIsolated {
                guard let uid = self?.engine.runningDeviceUID else { return false }
                return defaultOutputDeviceUID() == uid
            }
        }
        keys.onKey = { [weak self] key, fine in
            MainActor.assumeIsolated { self?.handleKey(key, fine: fine) }
        }
        // Show the system Accessibility prompt only on first launch; after that the menu's
        // "Open Settings" button covers it, so relaunches don't nag.
        updateVolumeKeys(prompt: !defaults.bool(forKey: "promptedAccessibility"))
        defaults.set(true, forKey: "promptedAccessibility")

        if ProcessInfo.processInfo.environment["SOLOVOLUME_DIAG"] != nil { startDiagnostics() }
    }

    private func handleKey(_ key: VolumeKey, fine: Bool) {
        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .up:
            muted = false
            volume = min(1, ((volume + step) / step).rounded() * step)
        case .down:
            volume = max(0, ((volume - step) / step).rounded() * step)
        case .mute:
            muted.toggle()
        }
        hud.show(level: volume, muted: muted, iconName: iconName)
    }

    /// Start or stop the key tap. Without Accessibility permission, keep checking until it's granted.
    private func updateVolumeKeys(prompt: Bool) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        guard volumeKeysEnabled else {
            keys.stop()
            volumeKeysNeedPermission = false
            return
        }
        if VolumeKeyInterceptor.hasPermission(prompt: prompt) && keys.start() {
            volumeKeysNeedPermission = false
            return
        }
        volumeKeysNeedPermission = true
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard VolumeKeyInterceptor.hasPermission(prompt: false) else { return }
                self?.updateVolumeKeys(prompt: false)
            }
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    var iconName: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var selectedName: String {
        devices.first { $0.id == selectedUID }?.name ?? "No device"
    }

    func quit() {
        engine.stop()
        exit(0)
    }

    private func applyLevel() {
        engine.level = muted ? 0 : Float(volume)
    }

    private func refreshDevices() {
        devices = outputDevices()
    }

    /// Make the engine match the selected device: start, restart, or stop as needed.
    private func reconcile() {
        guard let uid = selectedUID, devices.contains(where: { $0.id == uid }) else {
            engine.stop()
            status = selectedUID == nil ? "Choose an output device" : "\(selectedName) is disconnected"
            return
        }
        guard engine.runningDeviceUID != uid else { return }
        do {
            try engine.start(deviceUID: uid)
            status = "Controlling \(selectedName)"
        } catch {
            status = error.localizedDescription
        }
    }

    private func startDiagnostics() {
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [engine] _ in
            let peaks = (0..<engine.inputPeakCount.pointee).map { String(format: "%.4f", engine.inputPeaks[$0]) }
            FileHandle.standardError.write("input peaks: \(peaks) level: \(engine.level)\n".data(using: .utf8)!)
        }
    }
}
