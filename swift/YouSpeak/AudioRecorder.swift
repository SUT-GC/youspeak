import AVFoundation
import Foundation

final class AudioRecorder {
    private var engine  = AVAudioEngine()
    private var buffer  = Data()
    private let bufLock = NSLock()

    // Written on main actor (start/stop), read on AVAudioEngine tap thread.
    // nonisolated(unsafe) silences the Swift concurrency warning; safety is
    // guaranteed because stop() calls removeTap() BEFORE setting this to false,
    // so once it is false no more tap callbacks can fire.
    nonisolated(unsafe) private(set) var isRecording = false

    static let sampleRate: Double = 16000

    /// Returns `true` on success.
    @discardableResult
    func start() -> Bool {
        engine      = AVAudioEngine()
        buffer      = Data()
        isRecording = true

        let input       = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate:   Self.sampleRate,
                                         channels:     1,
                                         interleaved:  true)!
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[AudioRecorder] Failed to create AVAudioConverter")
            isRecording = false
            return false
        }

        input.installTap(onBus: 0, bufferSize: 3200, format: inputFormat) { [weak self] buf, _ in
            guard let self, self.isRecording else { return }

            let frameCount = AVAudioFrameCount(
                Double(buf.frameLength) * Self.sampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0,
                  let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount)
            else { return }

            var error: NSError?
            var consumed = false
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buf
            }
            guard error == nil, converted.frameLength > 0,
                  let chData = converted.int16ChannelData
            else { return }

            let bytes = Data(bytes: chData[0],
                             count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
            self.bufLock.withLock { self.buffer.append(bytes) }
        }

        do {
            try engine.start()
            return true
        } catch {
            print("[AudioRecorder] Engine start failed: \(error)")
            engine.inputNode.removeTap(onBus: 0)
            isRecording = false
            return false
        }
    }

    func stop() -> Data {
        // Remove the tap FIRST so no new callbacks can observe isRecording == false.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return bufLock.withLock {
            defer { buffer = Data() }
            return buffer
        }
    }
}
