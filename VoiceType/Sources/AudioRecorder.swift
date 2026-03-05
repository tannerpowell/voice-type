import AVFoundation
import CoreAudio

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Int16] = []
    private let sampleRate: Double = 16000
    private let channels: UInt32 = 1

    /// Lists available input devices. Returns array of (deviceID, name).
    static func availableInputDevices() -> [(AudioDeviceID, String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &devices
        )
        guard status == noErr else { return [] }

        var result: [(AudioDeviceID, String)] = []
        for deviceID in devices {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr else {
                continue
            }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }

            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPointer) == noErr else {
                continue
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
                  let name = nameRef?.takeUnretainedValue() else {
                continue
            }

            result.append((deviceID, name as String))
        }

        return result
    }

    /// Find device ID by name substring (case-insensitive).
    static func findDevice(matching query: String) -> AudioDeviceID? {
        let devices = availableInputDevices()
        let lowered = query.lowercased()
        return devices.first { $0.1.lowercased().contains(lowered) }?.0
    }

    private var persistentEngine: AVAudioEngine?
    private var configuredDeviceID: AudioDeviceID?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var isCapturing = false

    /// Set up the engine once for a given device. Reused across recordings.
    private func ensureEngine(deviceID: AudioDeviceID?) throws -> AVAudioEngine {
        // Reuse if device hasn't changed
        if let engine = persistentEngine, configuredDeviceID == deviceID {
            return engine
        }

        // Tear down old engine
        if let old = persistentEngine {
            old.inputNode.removeTap(onBus: 0)
            old.stop()
            old.reset()
        }

        let engine = AVAudioEngine()

        if let deviceID {
            let inputNode = engine.inputNode
            guard let audioUnit = inputNode.audioUnit else {
                throw NSError(domain: "AudioRecorder", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "No audio unit on input node"])
            }
            var devID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                throw NSError(domain: "AudioRecorder", code: Int(status),
                              userInfo: [NSLocalizedDescriptionKey: "Failed to set input device (OSStatus \(status))"])
            }
        }

        let fmt = engine.inputNode.outputFormat(forBus: 0)
        guard let tgtFmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            throw NSError(domain: "AudioRecorder", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create target audio format"])
        }

        guard let conv = AVAudioConverter(from: fmt, to: tgtFmt) else {
            throw NSError(domain: "AudioRecorder", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        self.inputFormat = fmt
        self.targetFormat = tgtFmt
        self.converter = conv
        self.persistentEngine = engine
        self.configuredDeviceID = deviceID

        return engine
    }

    func startRecording(deviceID: AudioDeviceID? = nil) throws {
        // Stop any in-progress capture
        if isCapturing, let engine = persistentEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isCapturing = false
        }

        audioBuffer = []
        let engine = try ensureEngine(deviceID: deviceID)

        guard let inputFormat, let targetFormat, let converter else {
            throw NSError(domain: "AudioRecorder", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Engine not configured"])
        }

        let sr = self.sampleRate
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * sr / inputFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
                return
            }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil, let channelData = convertedBuffer.int16ChannelData {
                let count = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
                self.audioBuffer.append(contentsOf: samples)
            }
        }

        try engine.start()
        isCapturing = true
        self.audioEngine = engine
    }

    /// Stop recording and return WAV data.
    func stopRecording() -> Data? {
        guard let engine = persistentEngine else { return nil }
        if isCapturing {
            engine.inputNode.removeTap(onBus: 0)
        }
        if engine.isRunning {
            engine.stop()
        }
        converter?.reset()
        isCapturing = false

        guard !audioBuffer.isEmpty else { return nil }
        return createWAV(samples: audioBuffer, sampleRate: UInt32(sampleRate), channels: UInt16(channels))
    }

    private func createWAV(samples: [Int16], sampleRate: UInt32, channels: UInt16) -> Data {
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = UInt32(samples.count * Int(bytesPerSample))
        let blockAlign = channels * bytesPerSample

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(uint32: 36 + dataSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(uint32: 16)            // chunk size
        data.append(uint16: 1)             // PCM format
        data.append(uint16: channels)
        data.append(uint32: sampleRate)
        data.append(uint32: sampleRate * UInt32(blockAlign)) // byte rate
        data.append(uint16: blockAlign)
        data.append(uint16: bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(uint32: dataSize)

        for sample in samples {
            var s = sample
            data.append(Data(bytes: &s, count: 2))
        }

        return data
    }
}

// MARK: - Data helpers for WAV encoding

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
