import Foundation
import Speech
import AVFoundation

/// SPEC.md §4 — on-device transcription only, ever. If on-device recognition
/// isn't available, voice is disabled for the session rather than silently
/// falling back to a server (§ security invariants #4).
@MainActor
final class VoiceRecognizer: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case unavailable(reason: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var onFinish: ((String) -> Void)?

    init() {
        recognizer = SFSpeechRecognizer(locale: .current)
    }

    private var isAvailable: Bool {
        guard let recognizer else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    func start(onFinish: @escaping (String) -> Void) {
        guard isAvailable else {
            showUnavailable("Voice isn't available on this device.")
            return
        }
        self.onFinish = onFinish
        transcript = ""

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }
                guard authStatus == .authorized else {
                    self.showUnavailable("Enable Speech Recognition access in Settings.")
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.showUnavailable("Enable microphone access in Settings.")
                            return
                        }
                        self.beginListening()
                    }
                }
            }
        }
    }

    /// `.unavailable` used to be a dead end — `toggleMic()` ignores taps
    /// while in that state, so a transient failure (a bad recognition
    /// result, not just "no permission") left the mic button permanently
    /// stuck until the view reloaded. Auto-clearing back to `.idle` after
    /// showing the reason makes every `.unavailable` case retryable.
    private func showUnavailable(_ reason: String) {
        state = .unavailable(reason: reason)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, case .unavailable = self.state else { return }
            self.state = .idle
        }
    }

    /// Manual stop (tapping the mic again while listening) — same exit path
    /// as silence detection.
    func stopManually() {
        finish()
    }

    private func beginListening() {
        guard let recognizer else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            showUnavailable("Couldn't start the microphone.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            showUnavailable("Couldn't start the microphone.")
            return
        }

        state = .listening
        resetSilenceTimer()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                // `self.state == .listening` also filters out the spurious
                // "canceled" callback that firing task?.cancel() from inside
                // finish()/fail() below triggers — without this guard, a
                // normal completion could immediately be followed by this
                // same closure re-firing and showing a bogus error.
                guard let self, self.state == .listening else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }
                if error != nil {
                    // Most commonly: the on-device speech model for this
                    // language isn't downloaded (Settings > General >
                    // Keyboard > Enable Dictation), which fails the instant
                    // real speech needs transcribing rather than up front —
                    // §4's on-device-only rule means there's no server
                    // fallback to try instead. Previously this silently
                    // called finish() with an empty transcript, which just
                    // made the "Listening..." UI vanish with no explanation.
                    self.fail(reason: "Couldn't transcribe that. Check that Dictation is on in Settings \u{2192} General \u{2192} Keyboard, then try again.")
                }
            }
        }
    }

    /// SPEC.md §4 — end-of-speech is ~1.2s of silence, not a fixed recording length.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func finish() {
        guard state == .listening else { return }
        teardownAudio()
        state = .idle
        let finalTranscript = transcript
        onFinish?(finalTranscript)
    }

    /// Same teardown as finish(), but for when there's no usable transcript
    /// to hand back — shows why instead of just going quiet.
    private func fail(reason: String) {
        guard state == .listening else { return }
        teardownAudio()
        showUnavailable(reason)
    }

    private func teardownAudio() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
