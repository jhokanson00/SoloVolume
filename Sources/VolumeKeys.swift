import AppKit
import ApplicationServices

enum VolumeKey {
    case up, down, mute
}

/// Intercepts the keyboard's volume keys with a CGEvent tap (needs Accessibility permission).
/// When `shouldHandle` returns false the keys pass through to macOS as usual
/// (e.g. when AirPods are the output); otherwise they're swallowed and sent to `onKey`.
final class VolumeKeyInterceptor {
    var shouldHandle: () -> Bool = { false }
    var onKey: (VolumeKey, _ fineStep: Bool) -> Void = { _, _ in }
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static func hasPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns false if the tap couldn't be created (usually missing Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << NX_SYSDEFINED)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<VolumeKeyInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let isKeyDown = (nsEvent.data1 & 0xFF00) >> 8 == 0xA
        let key: VolumeKey
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP: key = .up
        case NX_KEYTYPE_SOUND_DOWN: key = .down
        case NX_KEYTYPE_MUTE: key = .mute
        default: return Unmanaged.passUnretained(event)
        }
        guard shouldHandle() else { return Unmanaged.passUnretained(event) }
        // Shift+Option gives quarter steps, like macOS. Key-ups are swallowed too, but only
        // key-downs (including auto-repeats) change the volume.
        if isKeyDown { onKey(key, nsEvent.modifierFlags.contains([.shift, .option])) }
        return nil
    }
}

/// A small translucent level indicator, shown briefly when the volume keys are used.
@MainActor
final class VolumeHUD {
    private var panel: NSPanel?
    private var icon = NSImageView()
    private var bar = NSLevelIndicator()
    private var hideWork: DispatchWorkItem?

    func show(level: Double, muted: Bool, iconName: String) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .regular))
        bar.doubleValue = muted ? 0 : level * 16

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + f.height * 0.14))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel?.animator().alphaValue = 0 },
                                                 completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 200, height: 140)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18

        icon.frame = NSRect(x: 0, y: 52, width: size.width, height: 64)
        icon.contentTintColor = .labelColor
        bar.frame = NSRect(x: 24, y: 24, width: size.width - 48, height: 12)
        bar.levelIndicatorStyle = .continuousCapacity
        bar.minValue = 0
        bar.maxValue = 16
        bar.fillColor = .labelColor

        background.addSubview(icon)
        background.addSubview(bar)
        panel.contentView = background
        return panel
    }
}
