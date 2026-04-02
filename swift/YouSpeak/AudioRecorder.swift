import AVFoundation
import Foundation

final class AudioRecorder {
    private var engine    = AVAudioEngine()
    private var buffer    = Data()
    private let bufLock   = NSLock()
    private(set) var isRecording = false

    static let sampleRate: Double = 16000

    func start() {
        engine    = AVAudioEngine()
        buffer    = Data()
        isRecording = true

        let input  = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: Self.sampleRate,
                                   channels: 1,
                                   interleaved: true)!

        // 如果输入格式与目标不同，需要转换
        let inputFormat = input.outputFormat(forBus: 0)
        let converter  = AVAudioConverter(from: inputFormat, to: format)!

        input.installTap(onBus: 0, bufferSize: 3200, format: inputFormat) { [weak self] buf, _ in
            guard let self, self.isRecording else { return }
            let frameCount = AVAudioFrameCount(
                Double(buf.frameLength) * Self.sampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0,
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            var filled = false
            converter.convert(to: converted, error: &error) { _, status in
                status.pointee = .haveData
                return filled ? nil : { filled = true; return buf }()
            }
            guard error == nil, converted.frameLength > 0,
                  let chData = converted.int16ChannelData
            else { return }

            let bytes = Data(bytes: chData[0],
                             count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
            self.bufLock.lock()
            self.buffer.append(bytes)
            self.bufLock.unlock()
        }

        try? engine.start()
    }

    func stop() -> Data {
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        bufLock.lock()
        defer { bufLock.unlock() }
        return buffer
    }
}
