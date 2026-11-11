import CoreAudio

private func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

private func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
    var address = address
    guard AudioObjectHasProperty(object, &address) else { return false }
    var settable: DarwinBoolean = false
    return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
}

func defaultOutputDevice() -> AudioDeviceID? {
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
    guard status == noErr, device != kAudioObjectUnknown else { return nil }
    return device
}

func deviceName(_ device: AudioDeviceID) -> String {
    var address = propertyAddress(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else {
        return "Unknown device"
    }
    return name.takeRetainedValue() as String
}

/// Returns an empty array for devices that aren't aggregate / Multi-Output devices.
private func subDevices(of device: AudioDeviceID) -> [AudioDeviceID] {
    var address = propertyAddress(kAudioAggregateDevicePropertyActiveSubDeviceList, scope: kAudioObjectPropertyScopeGlobal)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &devices) == noErr else { return [] }
    return devices
}

/// Some devices expose a main volume, others only per-channel (left/right) volumes.
private func volumeElements(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
    if isSettable(device, propertyAddress(kAudioDevicePropertyVolumeScalar)) {
        return [kAudioObjectPropertyElementMain]
    }
    let channels: [AudioObjectPropertyElement] = [1, 2]
    return channels.filter { isSettable(device, propertyAddress(kAudioDevicePropertyVolumeScalar, element: $0)) }
}

struct OutputTarget {
    let device: AudioDeviceID
    let volumeElements: [AudioObjectPropertyElement]
    let canMute: Bool
}

func outputTargets() -> [OutputTarget] {
    guard let output = defaultOutputDevice() else { return [] }
    return subDevices(of: output).compactMap { device in
        let elements = volumeElements(device)
        guard !elements.isEmpty else { return nil }
        return OutputTarget(device: device, volumeElements: elements, canMute: isSettable(device, propertyAddress(kAudioDevicePropertyMute)))
    }
}

func readVolume(_ target: OutputTarget) -> Float? {
    let values: [Float32] = target.volumeElements.compactMap { element in
        var address = propertyAddress(kAudioDevicePropertyVolumeScalar, element: element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(target.device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Float(values.count)
}

func writeVolume(_ target: OutputTarget, _ volume: Float) {
    for element in target.volumeElements {
        var address = propertyAddress(kAudioDevicePropertyVolumeScalar, element: element)
        var value = Float32(volume)
        let status = AudioObjectSetPropertyData(target.device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if status != noErr { log("set volume failed on device \(target.device) element \(element): \(status)") }
    }
}

func writeMute(_ target: OutputTarget, _ muted: Bool) {
    guard target.canMute else { return }
    var address = propertyAddress(kAudioDevicePropertyMute)
    var value: UInt32 = muted ? 1 : 0
    AudioObjectSetPropertyData(target.device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
}
