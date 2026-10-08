import SwiftUI
import MSCCore

@main
struct MusicSpeedChangerApp: App {
    @StateObject private var engine = AudioEngine()
    @StateObject private var tracks = TrackList()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup("Music Speed Changer") {
            ContentView()
                .environmentObject(engine)
                .environmentObject(tracks)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 720)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    if settings.settings.autoCheckUpdates {
                        UpdateChecker.checkIfNewer()
                    }
                }
                .onDisappear {
                    settings.persistLastEffects(engine: engine)
                }
        }
        .defaultSize(width: 1280, height: 860)
        .defaultPosition(.center)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    init() {
        self.settings = AppSettings.load()
    }

    func persist() { settings.save() }

    func persistLastEffects(engine: AudioEngine) {
        settings.lastTempoPercent = engine.tempoPercent
        settings.lastPitchSemitones = engine.pitchSemitones
        settings.lastVolumePercent = engine.volumePercent
        settings.lastEqGains = engine.eqGains
        settings.lastEqEnabled = engine.eqEnabled
        if settings.rememberFileList {
            settings.fileListPaths = tracksPathCache
        }
        settings.save()
    }

    /// Set by the track list so we can remember it on save.
    var tracksPathCache: [String] = []
}

@MainActor
final class TrackList: ObservableObject {
    @Published var tracks: [TrackItem] = []
    @Published var selectedID: TrackItem.ID?

    init() {
        let s = AppSettings.load()
        if s.rememberFileList {
            tracks = s.fileListPaths.compactMap { p in
                FileManager.default.fileExists(atPath: p) ? TrackItem(url: URL(fileURLWithPath: p)) : nil
            }
        }
    }

    var paths: [String] { tracks.map { $0.url.path } }

    func add(urls: [URL]) {
        for url in urls where !tracks.contains(where: { $0.url == url }) {
            tracks.append(TrackItem(url: url))
        }
    }

    func removeSelected() {
        guard let id = selectedID, let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks.remove(at: idx)
        selectedID = nil
    }

    func clear() { tracks.removeAll(); selectedID = nil }

    func step(_ direction: Int) -> TrackItem? {
        guard !tracks.isEmpty else { return nil }
        let idx = selectedID.flatMap { id in tracks.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(idx + direction, 0), tracks.count - 1)
        selectedID = tracks[next].id
        return tracks[next]
    }
}
