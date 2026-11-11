import Foundation

enum MediaKey {
    case volumeUp, volumeDown, mute
}

final class VolumeController {
    private(set) var volume: Float = 0.5
    private(set) var muted = false
    private(set) var outputName = "Output"
    private(set) var targets: [OutputTarget] = []
    var onChange: (() -> Void)?

    /// Device state is only re-read at the start of a key press burst, so holding a key never waits on Core Audio.
    private let burstGap: TimeInterval = 0.75
    private var lastKeyTime = Date.distantPast

    private let writeQueue = DispatchQueue(label: "MultiOutputVolume.writes", qos: .userInteractive)
    private let writeLock = NSLock()
    private var pendingWrite: (volume: Float, muted: Bool, targets: [OutputTarget])?
    private var isWriting = false
    private var lastWrittenMute: Bool?

    var isActive: Bool { !targets.isEmpty }

    func refresh() {
        targets = outputTargets()
        outputName = defaultOutputDevice().map(deviceName) ?? "Output"
        guard !muted else { return }
        let volumes = targets.compactMap(readVolume)
        if !volumes.isEmpty { volume = volumes.reduce(0, +) / Float(volumes.count) }
    }

    func currentOutputDescription() -> String {
        guard isActive else { return "\(outputName) (not handled)" }
        return "\(outputName): " + targets.map { deviceName($0.device) }.joined(separator: " + ")
    }

    /// Returns false when the key should be passed through to macOS.
    func handle(_ key: MediaKey, fineStep: Bool) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastKeyTime) > burstGap { refresh() }
        lastKeyTime = now
        guard isActive else { return false }

        let baseStep = Settings.shared.volumeStep.value
        let step = fineStep ? baseStep / 4 : baseStep
        switch key {
        case .volumeUp:
            muted = false
            volume = adjusted(by: 1, step: step)
        case .volumeDown:
            muted = false
            volume = adjusted(by: -1, step: step)
        case .mute:
            muted.toggle()
        }

        enqueueWrite()
        onChange?()
        return true
    }

    private func adjusted(by delta: Float, step: Float) -> Float {
        let steps = (volume / step).rounded()
        return max(0, min(1, (steps + delta) * step))
    }

    /// USB volume writes are slow; coalesce them so only the latest value is written.
    private func enqueueWrite() {
        writeLock.lock()
        pendingWrite = (volume, muted, targets)
        let shouldStart = !isWriting
        isWriting = true
        writeLock.unlock()
        guard shouldStart else { return }
        writeQueue.async { [weak self] in self?.drainWrites() }
    }

    private func drainWrites() {
        while true {
            writeLock.lock()
            guard let job = pendingWrite else {
                isWriting = false
                writeLock.unlock()
                return
            }
            pendingWrite = nil
            writeLock.unlock()

            let muteChanged = lastWrittenMute != job.muted
            for target in job.targets {
                if muteChanged { writeMute(target, job.muted) }
                writeVolume(target, job.muted ? 0 : job.volume)
            }
            lastWrittenMute = job.muted
        }
    }
}
