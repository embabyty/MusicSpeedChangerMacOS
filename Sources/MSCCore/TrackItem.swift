import Foundation
import AVFoundation

/// One entry in the sidebar queue.
public final class TrackItem: Identifiable, ObservableObject {
    public let id = UUID()
    public let url: URL
    public var name: String { url.lastPathComponent }
    @Published public var durationText: String

    public init(url: URL) {
        self.url = url
        if let file = try? AVAudioFile(forReading: url) {
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            durationText = TrackItem.formatDuration(seconds)
        } else {
            durationText = "?"
        }
    }

    private static func duration(of url: URL) async -> String {
        if let file = try? AVAudioFile(forReading: url) {
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            return formatDuration(seconds)
        }
        return "?"
    }

    public static func formatDuration(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let m = Int(s) / 60
        let r = Int(s) % 60
        return String(format: "%d:%02d", m, r)
    }

    /// "0:00.0" style with one decimal, like the Windows transport readout.
    public static func formatClock(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let m = Int(s) / 60
        let r = s - Double(m * 60)
        return String(format: "%d:%04.1f", m, r)
    }
}
