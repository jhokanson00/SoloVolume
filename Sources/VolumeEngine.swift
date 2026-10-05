import CoreAudio
import Foundation

/// Software volume for an output device that has no hardware volume control.
///
/// A Core Audio process tap captures everything other apps send to the device and
/// mutes the original. A private aggregate device (the real device + the tap) runs an
/// IOProc that copies the tapped audio back out to the device with gain applied.
final class VolumeEngine: @unchecked Sendable {
    /// Shared with the real-time IO thread: [targetGain, currentGain].
    /// Aligned Float reads/writes are atomic on Apple silicon, so no lock is needed.
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 2)
    /// Peak level per input buffer of the last IO cycle, for diagnostics only.
    let inputPeaks = UnsafeMutablePointer<Float>.allocate(capacity: 8)
    let inputPeakCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private(set) var runningDeviceUID: String?

    init() {
        gain[0] = 1; gain[1] = 1
        inputPeakCount.pointee = 0
    }

    deinit {
        stop()
        gain.deallocate(); inputPeaks.deallocate(); inputPeakCount.deallocate()
    }

    /// Volume level, 0...1. The IO callback applies a cubic taper to it.
    var level: Float {
        get { gain[0] }
        set { gain[0] = max(0, min(1, newValue)) }
    }

    func start(deviceUID: String) throws {
        stop()
        do {
            try createTap(deviceUID: deviceUID)
            try createAggregate(deviceUID: deviceUID)
            try startIO()
            runningDeviceUID = deviceUID
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        runningDeviceUID = nil
    }

    // MARK: - Setup

    private func createTap(deviceUID: String) throws {
        // Our own output must be excluded from the tap, or it would feed back into itself.
        let me = processObject(for: getpid())
        guard me != kAudioObjectUnknown else {
            throw AudioError("Couldn't find this app's Core Audio process object")
        }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [me])
        description.name = "SoloVolume tap"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .muted
        // Only take audio that's headed to this device; other outputs are left alone.
        description.deviceUID = deviceUID
        description.stream = 0
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Couldn't create the audio tap")
    }

    private func createAggregate(deviceUID: String) throws {
        guard let tapUID = readString(tapID, kAudioTapPropertyUID) else {
            throw AudioError("Couldn't read the tap's UID")
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoloVolume",
            kAudioAggregateDeviceUIDKey: "com.jacobhokanson.SoloVolume.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID),
                  "Couldn't create the aggregate device")
    }

    private func startIO() throws {
        let gain = self.gain
        let peaks = inputPeaks
        let peakCount = inputPeakCount

        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, inInput, _, outOutput, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            let outputs = UnsafeMutableAudioBufferListPointer(outOutput)

            for out in outputs {
                if let data = out.mData { memset(data, 0, Int(out.mDataByteSize)) }
            }

            peakCount.pointee = min(inputs.count, 8)
            for i in 0..<peakCount.pointee {
                var peak: Float = 0
                if let data = inputs[i].mData?.assumingMemoryBound(to: Float.self) {
                    for s in 0..<Int(inputs[i].mDataByteSize) / 4 { peak = max(peak, abs(data[s])) }
                }
                peaks[i] = peak
            }

            // The tap is the last input stream in the aggregate (after the device's own inputs).
            guard let tapBuffer = inputs.last, let src = tapBuffer.mData?.assumingMemoryBound(to: Float.self),
                  let out = outputs.first, let dst = out.mData?.assumingMemoryBound(to: Float.self) else { return }

            let inChannels = max(1, Int(tapBuffer.mNumberChannels))
            let outChannels = max(1, Int(out.mNumberChannels))
            let frames = min(Int(tapBuffer.mDataByteSize) / (4 * inChannels), Int(out.mDataByteSize) / (4 * outChannels))
            guard frames > 0 else { return }

            // Ramp across the buffer so slider moves don't click.
            let start = gain[1], end = gain[0]
            let step = (end - start) / Float(frames)
            var g = start
            for f in 0..<frames {
                g += step
                let g2 = g * g * g   // perceptual (roughly logarithmic) taper
                for c in 0..<outChannels {
                    dst[f * outChannels + c] = src[f * inChannels + min(c, inChannels - 1)] * g2
                }
            }
            gain[1] = end
        }, "Couldn't create the IO callback")

        disableDeviceInputs()
        try check(AudioDeviceStart(aggregateID, ioProcID), "Couldn't start audio")
    }

    /// Turn off every input stream except the tap (the last one), so the interface's
    /// microphone inputs are never opened and the mic indicator stays off.
    private func disableDeviceInputs() {
        guard let ioProcID else { return }
        var addr = address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &addr, 0, nil, &size) == noErr else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(ioProcID, to: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, raw) == noErr else { return }

        let count = Int(usage.pointee.mNumberStreams)
        let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!
        let flags = (raw + flagsOffset).assumingMemoryBound(to: UInt32.self)
        for i in 0..<max(0, count - 1) { flags[i] = 0 }
        AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, size, raw)
    }
}
