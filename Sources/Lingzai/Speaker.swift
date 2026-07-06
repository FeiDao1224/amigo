import AVFoundation

/// 系统 TTS（免费、离线、零依赖）。后续可替换为开源本地语音模型。
final class Speaker {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "…" else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.5
        u.pitchMultiplier = 1.1
        synth.speak(u)
    }
}
