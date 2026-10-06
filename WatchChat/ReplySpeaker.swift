// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 canonliuliang

import AVFoundation
import Combine
import Foundation

@MainActor
final class ReplySpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var messageID: UUID?
    @Published private(set) var paused = false
    @Published private(set) var error: String?
    @Published private(set) var errorMessageID: UUID?
    private let synthesizer = AVSpeechSynthesizer()
    private var activationID: UUID?
    private var utteranceID: ObjectIdentifier?
    #if DEBUG
    private var playbackEvents: [String] = []
    #endif

    override init() {
        super.init(); synthesizer.delegate = self
    }

    func toggle(_ message: ChatMessage, rate: Double) {
        error = nil; errorMessageID = nil
        #if targetEnvironment(simulator)
        // The watchOS 27.0 simulator aborts in MTMacinTalkAUSPAudioUnit while
        // loading system speech. This fatal runtime error cannot be caught.
        errorMessageID = message.id
        error = "当前模拟器无法使用系统语音，请在手表上试听。"
        return
        #else
        if messageID == message.id {
            if paused { if synthesizer.continueSpeaking() { paused = false } }
            else { if synthesizer.pauseSpeaking(at: .immediate) { paused = true } }
            return
        }
        stop()
        let text = SpokenReply.text(from: message.text)
        guard !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        let token = UUID(); activationID = token
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            session.activate(options: []) { [weak self] success, _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.activationID == token else {
                        if success, self.activationID == nil {
                            try? session.setActive(false, options: .notifyOthersOnDeactivation)
                        }
                        return
                    }
                    guard success else { self.errorMessageID = message.id; self.error = "暂时无法播放，请检查音频输出。"; return }
                    let utterance = AVSpeechUtterance(string: text)
                    let hasChinese = text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
                    guard let voice = AVSpeechSynthesisVoice(language: hasChinese ? "zh-CN" : "en-US") else {
                        self.errorMessageID = message.id
                        self.error = "系统语音尚未准备好，请稍后重试。"
                        try? session.setActive(false, options: .notifyOthersOnDeactivation)
                        return
                    }
                    utterance.voice = voice
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(min(1.4, max(0.7, rate)))
                    self.messageID = message.id; self.paused = false
                    self.utteranceID = ObjectIdentifier(utterance)
                    self.synthesizer.speak(utterance)
                }
            }
        } catch { errorMessageID = message.id; self.error = "暂时无法启用朗读，请稍后重试。" }
        #endif
    }

    func stop() {
        activationID = nil
        utteranceID = nil; errorMessageID = nil; error = nil
        synthesizer.stopSpeaking(at: .immediate)
        messageID = nil; paused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.paused = false
            #if DEBUG
            self.recordPlayback("started")
            #endif
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.paused = true
            #if DEBUG
            self.recordPlayback("paused")
            #endif
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.paused = false
            #if DEBUG
            self.recordPlayback("continued")
            #endif
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            #if DEBUG
            self.recordPlayback("finished")
            #endif
            self.messageID = nil; self.paused = false; self.utteranceID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == identifier else { return }
            self.messageID = nil; self.paused = false; self.utteranceID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    #if DEBUG
    private func recordPlayback(_ event: String) {
        playbackEvents.append(event)
        let report: [String: Any] = ["events": playbackEvents, "isSpeaking": synthesizer.isSpeaking,
                                   "isPaused": synthesizer.isPaused, "textLogged": false]
        let url = URL.applicationSupportDirectory.appendingPathComponent("WristChat/speech-acceptance.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif
}
