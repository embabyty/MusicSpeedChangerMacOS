import SwiftUI
import MSCCore

enum AppTab: Hashable {
    case player
    case equalizer
}

struct ContentView: View {
    @EnvironmentObject var engine: AudioEngine
    @EnvironmentObject var tracks: TrackList
    @EnvironmentObject var settings: SettingsStore

    @State private var tab: AppTab = .player
    @State private var showFiles = true
    @State private var exporting = false
    @State private var showSaveDialog = false
    @State private var saveLoopOnly = false
    @State private var saveRepeat = 1
    @State private var saveFileName = ""
    @State private var errorMessage: String?

    private var hasLoop: Bool { engine.loopIsValid }

    var body: some View {
        TabView(selection: $tab) {
            TabSection("Listen") {
                Tab("Now Playing", systemImage: "play.circle.fill", value: AppTab.player) {
                    PlayerView(onStep: stepTrack, onOpen: openPanel,
                               onExport: beginExport, onToggleFiles: toggleFiles,
                               exporting: exporting)
                }
                Tab("Equalizer", systemImage: "slider.horizontal.3", value: AppTab.equalizer) {
                    EqualizerView(onOpen: openPanel, onExport: beginExport,
                                  onToggleFiles: toggleFiles, exporting: exporting)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.automatic)
        .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        .inspector(isPresented: $showFiles) {
            FilesView(onSelect: loadTrack)
        }
        .animation(.easeInOut(duration: 0.25), value: showFiles)
        .optionalTint(settings.settings.useSystemAccent
                      ? nil : Color(hex: settings.settings.customAccentHex))
        .sheet(isPresented: $showSaveDialog) {
            SaveDialogSheet(fileName: $saveFileName, loopOnly: $saveLoopOnly,
                            loopRepeat: $saveRepeat, hasLoop: hasLoop) { startExport() }
                .frame(width: 460)
                .padding()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: tracks.tracks.map(\.url)) { _, new in
            settings.tracksPathCache = new.map(\.path)
        }
        .onAppear {
            applyStartupEffects()
            NSApp.activate(ignoringOtherApps: true)
            // Always have something loaded: resume the last file (or the
            // first remembered one) instead of idling with an empty engine.
            if !engine.isLoaded, let track = launchTrack() {
                loadTrack(track)
            }
        }
        .task {
            // Pin the window to a usable size on the primary display: the
            // layout needs ~1220pt for sidebar + content + inspector, and a
            // restored frame can come back smaller (clipping both side columns).
            for _ in 0..<50 {
                let placed = await MainActor.run { () -> Bool in
                    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                          let screen = NSScreen.screens.first
                    else { return false }
                    let minSize = NSSize(width: 1220, height: 800)
                    window.minSize = minSize
                    var frame = window.frame
                    if frame.width < minSize.width || frame.height < minSize.height {
                        let size = NSSize(width: max(frame.width, minSize.width),
                                          height: max(frame.height, minSize.height))
                        frame = NSRect(
                            x: screen.frame.midX - size.width / 2,
                            y: screen.frame.midY - size.height / 2,
                            width: size.width, height: size.height)
                        window.setFrame(frame, display: true)
                    } else {
                        window.setFrameOrigin(NSPoint(
                            x: screen.frame.midX - frame.width / 2,
                            y: screen.frame.midY - frame.height / 2))
                    }
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
                if placed { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func applyStartupEffects() {
        if settings.settings.rememberEffects {
            engine.tempoPercent = settings.settings.lastTempoPercent
            engine.pitchSemitones = settings.settings.lastPitchSemitones
            engine.volumePercent = settings.settings.lastVolumePercent
            if let gains = settings.settings.lastEqGains { engine.eqGains = gains }
            engine.eqEnabled = settings.settings.lastEqEnabled
        } else if settings.settings.applyDefaultsOnFileLoad {
            engine.tempoPercent = settings.settings.defaultTempoPercent
            engine.pitchSemitones = settings.settings.defaultPitchSemitones
        }
    }

    // MARK: Actions

    func loadTrack(_ track: TrackItem) {
        // Selecting the loaded row (or double-loading) is a no-op.
        if engine.isLoaded, engine.fileURL == track.url { return }
        do {
            try engine.load(url: track.url)
            tracks.selectedID = track.id
            settings.settings.lastFilePath = track.url.path
            settings.persist()
            if settings.settings.applyDefaultsOnFileLoad && !settings.settings.rememberEffects {
                engine.tempoPercent = settings.settings.defaultTempoPercent
                engine.pitchSemitones = settings.settings.defaultPitchSemitones
            }
            // Waveform peaks are decoded off the main thread (applies to this file).
            engine.waveform = nil
            let peaks = settings.settings.waveformPeaks
            let url = track.url
            Task {
                let data = await Task.detached(priority: .userInitiated) {
                    WaveformData.fromFile(url, bucketCount: peaks)
                }.value
                engine.waveform = data
            }
        } catch {
            errorMessage = "Could not load \(track.name):\n\(error.localizedDescription)"
        }
    }

    private func toggleFiles() { withAnimation { showFiles.toggle() } }

    /// Track to auto-load at launch: the last-played file when it is still
    /// in the list, otherwise the first remembered file.
    private func launchTrack() -> TrackItem? {
        let list = tracks.tracks
        guard !list.isEmpty else { return nil }
        if let last = settings.settings.lastFilePath,
           let match = list.first(where: { $0.url.path == last })
        {
            return match
        }
        return list.first
    }

    private func stepTrack(_ direction: Int) {
        guard let track = tracks.step(direction) else { return }
        loadTrack(track)
        engine.play()
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK {
            tracks.add(urls: panel.urls)
            if let first = panel.urls.first { loadTrack(TrackItem(url: first)) }
        }
    }

    private func beginExport() {
        guard engine.isLoaded else { return }
        let pitch = engine.pitchSemitones
        let suggested = engine.fileName.map { name in
            let base = (name as NSString).deletingPathExtension
            return "\(base)_\(Int(engine.tempoPercent))pct_\(pitch >= 0 ? "+" : "")\(String(format: "%.1f", pitch))st"
                + (engine.eqEnabled && !engine.eqIsFlat ? "_eq" : "")
        } ?? "track"
        saveFileName = SaveDialogSheet.sanitizeFileName(suggested)
        saveLoopOnly = hasLoop
        saveRepeat = 1
        showSaveDialog = true
    }

    private func startExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = saveFileName
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        exporting = true
        let wasPlaying = engine.isPlaying
        if wasPlaying { engine.pause() }

        Task {
            do {
                try await engine.exportWav(to: url, tempoPercent: engine.tempoPercent,
                                           pitchSemitones: engine.pitchSemitones,
                                           loopOnly: saveLoopOnly && hasLoop, loopRepeat: saveRepeat) { _ in }
            } catch {
                errorMessage = "Save failed:\n\(error.localizedDescription)"
            }
            exporting = false
            if wasPlaying { engine.play() }
        }
    }
}

// MARK: Shared window toolbar (Open / Export), shown on every tab.
struct LibraryToolbar: ViewModifier {
    @EnvironmentObject var engine: AudioEngine
    let exporting: Bool
    let onOpen: () -> Void
    let onExport: () -> Void
    let onToggleFiles: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open", systemImage: "folder", action: onOpen)
                    .help("Open audio file")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Export", systemImage: "square.and.arrow.down", action: onExport)
                    .disabled(!engine.isLoaded || exporting)
                    .help("Save edited audio")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Files", systemImage: "list.bullet", action: onToggleFiles)
                    .help("Show or hide the file list")
            }
        }
    }
}

// MARK: Save dialog sheet
struct SaveDialogSheet: View {
    @Binding var fileName: String
    @Binding var loopOnly: Bool
    @Binding var loopRepeat: Int
    let hasLoop: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save Edited Audio").font(.title2.weight(.semibold))
            HStack {
                Text("New Filename")
                TextField("filename", text: $fileName)
            }
            HStack {
                Text("Encoding")
                Text("WAV (wav)").foregroundStyle(.secondary)
            }
            Text("Loop Extraction").font(.headline).padding(.top, 8)
            Toggle("Save Loop Only", isOn: $loopOnly).disabled(!hasLoop)
            Stepper("Loop Repeat (iterations): \(loopRepeat)", value: $loopRepeat, in: 1...1000)
                .disabled(!hasLoop || !loopOnly)
            if !hasLoop {
                Text("Set an AB loop to enable loop extraction.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { dismiss(); onSave() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "track" : cleaned
    }
}
