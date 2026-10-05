import CoreAudio
import Foundation

struct AudioError: LocalizedError {
    let message: String
    let status: OSStatus
    init(_ message: String, _ status: OSStatus = 0) { self.message = message; self.status = status }
    var errorDescription: String? { status == 0 ? message : "\(message) (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw AudioError(what, status) }
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

func readArray<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                  _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, of: T.Type) -> [T] {
    var addr = address(selector, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<T>.stride
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buffer) == noErr else { return [] }
    return Array(UnsafeBufferPointer(start: buffer, count: count))
}

func outputChannelCount(_ id: AudioDeviceID) -> Int {
    var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func processObject(for pid: pid_t) -> AudioObjectID {
    var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pid = pid
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(systemObject, &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
    return object
}

struct OutputDevice: Identifiable, Hashable {
    let id: String   // device UID
    let name: String
}

func outputDevices() -> [OutputDevice] {
    readArray(systemObject, kAudioHardwarePropertyDevices, of: AudioDeviceID.self).compactMap { id in
        guard outputChannelCount(id) > 0,
              let uid = readString(id, kAudioDevicePropertyDeviceUID),
              let name = readString(id, kAudioObjectPropertyName) else { return nil }
        return OutputDevice(id: uid, name: name)
    }
}

func defaultOutputDeviceUID() -> String? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &id) == noErr else { return nil }
    return readString(id, kAudioDevicePropertyDeviceUID)
}

func deviceID(forUID uid: String) -> AudioDeviceID? {
    readArray(systemObject, kAudioHardwarePropertyDevices, of: AudioDeviceID.self)
        .first { readString($0, kAudioDevicePropertyDeviceUID) == uid }
}
