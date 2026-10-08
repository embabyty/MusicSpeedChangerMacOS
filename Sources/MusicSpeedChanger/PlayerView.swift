import SwiftUI
import MSCCore

/// Now Playing tab: waveform, time readout, glass transport, tempo/pitch/loop cards.
struct PlayerView: View {
    @EnvironmentObject var engine: AudioEngine
    @EnvironmentObject var settings: SettingsStore

    let onStep: (Int) -> Void
    let onOpen: () -> Void
    let onExport: () -> Void
    let onToggleFiles: () -> Void
    let exporting: Bool

    @State private var seekDragging = false
    @State private var seekValue: Double = 0
    /// Waveform zoom level 0…10, mirroring the iOS app (5 = natural scale).
    @State private var zoomLevel = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    WaveformView(data: engine.waveform, duration: engine.duration,
                                 position: engine.position,
                                 loopA: engine.loopA, loopB: engine.loopB,
                                 loopEnabled: engine.loopEnabled,
                                 zoomLevel: zoomLevel) { seconds in
                        if settings.settings.clickToSeek, engine.isLoaded {
                            engine.seek(to: seconds)
                        }
                    }
                    .frame(minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Menu {
                        ForEach(0...10, id: \.self) { level in
                            Button {
                                zoomLevel = level
                            } label: {
                                if level == zoomLevel {
                                    Label("Level \(level)", systemImage: "checkmark")
                                } else {
                                    Text("Level \(level)")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .menuStyle(.borderlessButton)
                    .disabled(!engine.isLoaded)
                    .help("Waveform zoom level")
                    .padding(10)
                }

                timeRow

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    if settings.settings.showTempoPanel { tempoCard }
                    if settings.settings.showPitchPanel { pitchCard }
                    if settings.settings.showLoopPanel { loopCard }
                }
            }
            .padding()
            .padding(.bottom, 64) // clearance so content slides under the floating bar
        }
        .navigationTitle(engine.fileName ?? "Now Playing")
        .modifier(LibraryToolbar(exporting: exporting, onOpen: onOpen,
                                 onExport: onExport, onToggleFiles: onToggleFiles))
        .onChange(of: engine.reverseEnabled) { _, _ in
            // Restart so the direction change takes effect immediately.
            // Loop state is preserved: a valid loop keeps looping, backwards.
            if engine.isPlaying { engine.play() }
        }
        .overlay(alignment: .bottom) {
            floatingTransport
                .padding(.bottom, 14)
        }
    }

    private var timeRow: some View {
        HStack {
            Text(TrackItem.formatClock(seekDragging ? seekValue : engine.position))
                .frame(width: 70, alignment: .leading)
                .monospacedDigit()
            Slider(value: Binding(
                get: { seekDragging ? seekValue : engine.position },
                set: { seekValue = $0; seekDragging = true }),
                   in: 0...max(engine.duration, 0.001)) { _ in
                seekDragging = false
                engine.seek(to: seekValue)
            }
            .disabled(!engine.isLoaded)
            Text(TrackItem.formatClock(engine.duration))
                .frame(width: 70, alignment: .trailing)
                .monospacedDigit()
            Text(engine.effectiveDurationText)
                .foregroundStyle(.secondary)
                .frame(minWidth: 140, alignment: .leading)
        }
    }

    /// Floating glass control bar, Apple Music style: hovers over the content
    /// instead of sitting in the layout flow.
    private var floatingTransport: some View {
        HStack(spacing: 16) {
            HStack(spacing: 22) {
                Button {
                    onStep(-1)
                } label: {
                    Image(systemName: "backward.fill")
                }
                .help("Previous file")
                Button {
                    engine.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Stop")
                Button {
                    if engine.isPlaying { engine.pause() } else { engine.play() }
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(engine.isPlaying ? "Pause" : "Play")
                Button {
                    onStep(1)
                } label: {
                    Image(systemName: "forward.fill")
                }
                .help("Next file")
                Button {
                    engine.reverseEnabled.toggle()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .foregroundStyle(engine.reverseEnabled ? .red : .primary)
                .help("Play backwards from the current position")
                .onChange(of: engine.reverseEnabled) { _, on in
                    if on { engine.loopEnabled = false }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 16))
            Divider().frame(height: 20)
            HStack {
                Image(systemName: "speaker.wave.2")
                Slider(value: $engine.volumePercent, in: 0...100).frame(width: 120)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .disabled(!engine.isLoaded)
        .opacity(engine.isLoaded ? 1 : 0.35)
    }

    private var tempoCard: some View {
        Card("Tempo (speed, keeps pitch)") {
            HStack {
                Slider(value: $engine.tempoPercent, in: 50...200, step: settings.settings.tempoSliderStep)
                Text(String(format: "%.0f%%", engine.tempoPercent))
                    .frame(width: 64, alignment: .trailing).fontWeight(.semibold)
                    .monospacedDigit()
            }
            .disabled(!engine.isLoaded)
            HStack {
                ForEach([50, 75, 100, 125, 150], id: \.self) { p in
                    Button(p == 100 ? "1x" : p == 50 ? "0.5x" : p == 75 ? "0.75x" : p == 125 ? "1.25x" : "1.5x") {
                        engine.tempoPercent = Double(p)
                    }
                }
            }
            .buttonStyle(.glass)
            .disabled(!engine.isLoaded)
            Button("Reset tempo") { engine.tempoPercent = 100 }
                .buttonStyle(.glass)
        }
    }

    private var pitchCard: some View {
        Card("Pitch (key, keeps tempo)") {
            HStack {
                Slider(value: $engine.pitchSemitones, in: -12...12, step: settings.settings.pitchSliderStep)
                Text(String(format: "%+.1f st", engine.pitchSemitones))
                    .frame(width: 64, alignment: .trailing).fontWeight(.semibold)
                    .monospacedDigit()
            }
            .disabled(!engine.isLoaded)
            HStack {
                ForEach([-5, -2, 0, 2, 5], id: \.self) { p in
                    Button("\(p > 0 ? "+" : "")\(p)") { engine.pitchSemitones = Double(p) }
                }
            }
            .buttonStyle(.glass)
            .disabled(!engine.isLoaded)
            Button("Reset pitch") { engine.pitchSemitones = 0 }
                .buttonStyle(.glass)
        }
    }

    private var loopCard: some View {
        Card("AB Loop (practice sections)") {
            HStack {
                Button("Set A") { engine.setLoopA() }.disabled(!engine.isLoaded)
                Button("Set B") { engine.setLoopB() }.disabled(!engine.isLoaded)
                Button("Clear") { engine.clearLoop() }.disabled(!engine.isLoaded)
            }
            .buttonStyle(.glass)
            Group {
                if let a = engine.loopA, let b = engine.loopB, b > a {
                    Text("A \(TrackItem.formatClock(a))   B \(TrackItem.formatClock(b))")
                } else {
                    Text("No loop set")
                }
            }
            .foregroundStyle(.yellow)
            .monospacedDigit()
            Toggle("Loop A–B", isOn: Binding(
                get: { engine.loopEnabled },
                set: { engine.loopEnabled = $0; engine.loopToggled() }))
            .disabled(!engine.loopIsValid)
        }
    }
}

/// Frosted card container used by the Now Playing tab.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
