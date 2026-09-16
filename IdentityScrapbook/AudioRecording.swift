import Foundation
import AVFoundation
import Observation

@MainActor @Observable
final class AudioRecording: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var requestingPermission = false
    var permissionDenied = false
    var duration = 0.0
    var waveform: [Double] = []
    var ready = false
    var failed = false
    var interrupted = false
    private(set) var url: URL?
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var closed = false

    func start() async {
        guard !isRecording, !requestingPermission, !closed else { return }
        requestingPermission = true
        permissionDenied = false
        let granted = await AVAudioApplication.requestRecordPermission()
        requestingPermission = false
        guard !closed else { return }
        guard granted else { permissionDenied = true; return }
        reset()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let folder = URL.temporaryDirectory.appendingPathComponent("audio-draft-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("recording.m4a")
            url = target
            let recording = try AVAudioRecorder(url: target, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            recorder = recording
            recording.delegate = self
            recording.isMeteringEnabled = true
            guard recording.prepareToRecord(), recording.record(forDuration: AudioFiles.maxDuration) else {
                throw AudioFiles.AudioError.invalidRecording
            }
            isRecording = true
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self, self.isRecording, let recorder = self.recorder else { return }
                    recorder.updateMeters()
                    self.duration = recorder.currentTime
                    self.waveform.append(pow(10, Double(recorder.averagePower(forChannel: 0)) / 20))
                }
            }
        } catch { failed = true; stop() }
    }

    func stop(interrupted: Bool = false) {
        guard recorder != nil else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        self.interrupted = self.interrupted || interrupted
        isRecording = false
        meterTask?.cancel(); meterTask = nil
        recorder?.stop()
        validate()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func validate() {
        guard let url else { return }
        do { duration = try AudioFiles.duration(of: url); ready = true }
        catch { ready = false; failed = true }
    }

    func reset() {
        recorder?.delegate = nil
        recorder?.stop(); recorder = nil
        meterTask?.cancel(); meterTask = nil
        if let url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        url = nil; ready = false; duration = 0; waveform = []; failed = false; interrupted = false; isRecording = false
    }

    func close() {
        closed = true
        reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let finishedURL = recorder.url
        Task { @MainActor [weak self] in
            guard let self, !self.closed, self.url == finishedURL else { return }
            self.isRecording = false
            self.meterTask?.cancel()
            self.validate()
            if !flag { self.interrupted = true }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let failedURL = recorder.url
        Task { @MainActor [weak self] in
            guard let self, self.url == failedURL, !self.closed else { return }
            self.failed = true
            self.stop(interrupted: true)
        }
    }
}

@MainActor @Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    var playing = false
    var failed = false
    private var player: AVAudioPlayer?
    func play(_ url: URL) {
        stop(); failed = false
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.delegate = self
            guard player.prepareToPlay(), player.play() else { throw AudioFiles.AudioError.invalidRecording }
            playing = true
        } catch { failed = true; stop() }
    }
    func stop() {
        player?.stop(); player = nil; playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stop(); if !flag { self?.failed = true } }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in self?.stop(); self?.failed = true }
    }
}
