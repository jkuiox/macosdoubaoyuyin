import AVFoundation

class AudioEngine {
    var onAudioBuffer: ((Data) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    private var engine: AVAudioEngine?
    private let sampleRate: Double = 16000
    private let bufferDuration: Double = 0.2 // 200ms chunks for optimal performance

    func start() {
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz, 16-bit, mono PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else { return }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * bufferDuration)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Calculate audio level from input buffer
            let level = self.calculateLevel(buffer: buffer)
            self.onAudioLevel?(level)

            // Convert to 16kHz 16-bit mono
            let targetFrameCount = AVAudioFrameCount(self.sampleRate * self.bufferDuration)
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: targetFrameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            if let channelData = convertedBuffer.int16ChannelData {
                let data = Data(
                    bytes: channelData[0],
                    count: Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                )
                self.onAudioBuffer?(data)
            }
        }

        do {
            try engine.start()
        } catch {
            print("AudioEngine start failed: \(error)")
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(max(frames, 1)))
        // Convert to 0-1 range with some amplification
        return min(1.0, rms * 5.0)
    }
}
