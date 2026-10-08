import Foundation
import Accelerate
import AVFoundation

/// Peak envelope of a decoded audio file, for waveform rendering.
public struct WaveformData: Sendable {
    public var peaks: [Float]   // max abs sample per bucket, count == bucketCount
    public var bucketCount: Int
    public var duration: Double

    /// bucketCount from settings; default mirrors the Windows WaveformPeaks (1400).
    public static func fromFile(_ url: URL, bucketCount: Int = 1400) -> WaveformData? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let total = Int(file.length)
        let buckets = max(64, bucketCount)
        var out = [Float](repeating: 0, count: buckets)
        let chunkFrames = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(chunkFrames))
        else { return nil }

        // Never read past EOF: requesting frames beyond the end throws
        // instead of returning a short buffer on some files.
        var frameIndex = 0
        while frameIndex < total {
            let want = min(chunkFrames, total - frameIndex)
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(want)) }
            catch { return nil }
            let read = Int(buffer.frameLength)
            if read == 0 { break }
            if let channel = buffer.floatChannelData?[0] {
                for i in 0..<read {
                    let bucket = min((frameIndex + i) * buckets / max(total, 1), buckets - 1)
                    let v = abs(channel[i])
                    if v > out[bucket] { out[bucket] = v }
                }
            }
            frameIndex += read
        }

        let duration = Double(file.length) / format.sampleRate
        return WaveformData(peaks: out, bucketCount: buckets, duration: duration)
    }
}
