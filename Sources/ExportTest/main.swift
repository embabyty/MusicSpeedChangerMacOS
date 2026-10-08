import Foundation
import AVFoundation
import MSCCore
import Darwin

setvbuf(stdout, nil, 2, 0) // _IONBF

// Headless check: synthesize a sine, run it through AudioEngine's offline
// export (time pitch + EQ + limiter) and confirm a non-trivial WAV is produced.

let inputURL = URL(fileURLWithPath: "/tmp/msc_input.wav")
let outputURL = URL(fileURLWithPath: "/tmp/msc_output.wav")

let sampleRate = 44100.0
let seconds = 3.0
let frames = Int(sampleRate * seconds)
let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                        channels: 2, interleaved: false)!
let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames))!
buffer.frameLength = AVAudioFrameCount(frames)
for c in 0..<2 {
    let ch = buffer.floatChannelData![c]
    for i in 0..<frames {
        let phase = 2 * Double.pi * 220 * Double(i) / sampleRate
        ch[i] = Float(0.5 * sin(phase))
    }
}
do {
    let inFile = try AVAudioFile(forWriting: inputURL, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ])
    try inFile.write(from: buffer)
}
print("wrote input")

let engine = await MainActor.run { AudioEngine() }
try await MainActor.run { try engine.load(url: inputURL) }
print("loaded duration:", await MainActor.run { engine.duration })
await MainActor.run {
    engine.tempoPercent = 80
    engine.pitchSemitones = 2
    engine.eqGains = Array(repeating: 3, count: 31)
}
try await engine.exportWav(to: outputURL, tempoPercent: 80, pitchSemitones: 2,
                           loopOnly: false, loopRepeat: 1) { p in
    print(String(format: "progress %.0f%%", p * 100), terminator: "\r")
}
if let out = try? AVAudioFile(forReading: outputURL) {
    print("\nExported frames:", out.length, "duration:", Double(out.length) / out.processingFormat.sampleRate)
} else {
    print("\nFailed to read output!")
    exit(1)
}
print("OK")
