import SwiftUI
import SwiftData
import AVFoundation

struct AudioWaveform: View {
    let samples: [Double]
    var body: some View {
        Canvas { context, size in
            let values = AudioFiles.compactWaveform(samples)
            guard !values.isEmpty else {
                var line = Path(); line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(line, with: .color(.secondary.opacity(0.3)), lineWidth: 2)
                return
            }
            let step = size.width / CGFloat(values.count)
            for (index, value) in values.enumerated() {
                let height = max(2, CGFloat(value) * size.height)
                let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                  width: max(1, step - 2), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(ScrapbookStyle.accent))
            }
        }
        .frame(height: 72).accessibilityHidden(true)
    }
}

struct AudioCard: View {
    let entry: AudioEntry
    var body: some View {
        MemoryPaper(color: Color(red: 0.87, green: 0.93, blue: 0.87)) {
            VStack(alignment: .leading, spacing: 16) {
                Label("audio.memory", systemImage: "waveform")
                AudioWaveform(samples: entry.waveform)
                Text(Duration.seconds(entry.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.headline.monospacedDigit())
            }
        }
    }
}

struct AudioEditor: View {
    let bookID: UUID
    let voteID: UUID?
    let submissionID: UUID
    var onSaved: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var recording = AudioRecording()
    @State private var playback = AudioPlayback()
    @State private var saving = false
    @State private var discard = false
    @State private var rerecord = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: recording.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 44)).foregroundStyle(recording.isRecording ? .red : ScrapbookStyle.accent)
                        .accessibilityHidden(true)
                    Text(recording.isRecording ? "audio.recording" : recording.ready ? "audio.review" : "audio.prompt")
                        .font(.title3.bold()).multilineTextAlignment(.center)
                    Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.largeTitle.monospacedDigit())
                    AudioWaveform(samples: recording.waveform)
                    if recording.requestingPermission { ProgressView("audio.permission") }
                    if recording.isRecording {
                        Button("audio.stopRecording") { recording.stop() }.buttonStyle(.borderedProminent).tint(.red)
                    } else if recording.ready, let url = recording.url {
                        Button(playback.playing ? "audio.stopPlayback" : "audio.play") {
                            if playback.playing { playback.stop() } else { playback.play(url) }
                        }.buttonStyle(.borderedProminent)
                        Button("audio.rerecord") { rerecord = true }
                    } else {
                        Button("audio.start") { Task { await recording.start() } }
                            .buttonStyle(.borderedProminent).disabled(recording.requestingPermission)
                    }
                    if recording.permissionDenied {
                        Text("audio.denied")
                        Button("audio.settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    if recording.interrupted { Text("audio.interrupted").font(.callout) }
                    if recording.failed || playback.failed { Text("audio.error.help").font(.callout) }
                    Text("audio.limit").font(.footnote).foregroundStyle(.secondary)
                    if saving { ProgressView("audio.saving") }
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity).disabled(saving)
            }
            .navigationTitle("audio.add").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        if recording.url != nil { discard = true } else { dismiss() }
                    }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("note.save") { Task { await save() } }
                        .disabled(!recording.ready || recording.isRecording || saving)
                }
            }
            .confirmationDialog("draft.discard.title", isPresented: $discard, titleVisibility: .visible) {
                Button("draft.discard", role: .destructive) { dismiss() }
                Button("draft.keep", role: .cancel) { }
            }
            .confirmationDialog("audio.rerecord.confirm", isPresented: $rerecord, titleVisibility: .visible) {
                Button("audio.rerecord", role: .destructive) { playback.stop(); Task { await recording.start() } }
                Button("common.cancel", role: .cancel) { }
            }
            .alert("save.error.title", isPresented: $failed) {
                Button("common.ok", role: .cancel) { }
            } message: { Text("save.error.description") }
        }
        .interactiveDismissDisabled(recording.url != nil || saving || recording.requestingPermission)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                if recording.isRecording { recording.stop(interrupted: true) }
                playback.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
                if recording.isRecording { recording.stop(interrupted: true) }
                playback.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                if recording.isRecording { recording.stop(interrupted: true) }
                playback.stop()
            }
        }
        .onDisappear { playback.stop(); recording.close() }
    }

    private func save() async {
        guard recording.ready, !recording.isRecording, !saving, let url = recording.url else { return }
        saving = true; playback.stop()
        do {
            let id = try await AudioStore.add(url, waveform: recording.waveform, bookID: bookID,
                                             voteID: voteID, submissionID: submissionID, in: context.container)
            onSaved(id); dismiss()
        } catch { saving = false; failed = true }
    }
}

struct AudioDetail: View {
    let entry: AudioEntry
    @State private var playback = AudioPlayback()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 20) {
            AudioCard(entry: entry)
            Button(playback.playing ? "audio.stopPlayback" : "audio.play") {
                if playback.playing { playback.stop() }
                else { playback.play(AudioFiles.root.appendingPathComponent(entry.audioKey)) }
            }.buttonStyle(.borderedProminent)
            if playback.failed { Text("audio.playError") }
        }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playback.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { playback.stop() }
        }
    }
}
