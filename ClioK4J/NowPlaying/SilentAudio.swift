import Foundation
import AVFoundation

/// Moteur audio silencieux : garde la session audio active pour que l'iPhone
/// nous considère comme une source "lecture en cours" et que CarPlay nous liste.
/// Rien n'est audible, mais iOS n'arrête pas l'app en arrière-plan tant qu'elle joue.
final class SilentAudio {
    static let shared = SilentAudio()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?

    private init() {}

    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default,
                options: [.mixWithOthers, .allowAirPlay, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            NSLog("SilentAudio: session impossible: \(error)")
            return
        }

        // Buffer de silence 1 seconde, bouclé.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frames = AVAudioFrameCount(format.sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        if let data = buf.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                memset(data[ch], 0, Int(frames) * MemoryLayout<Float>.size)
            }
        }
        self.buffer = buf

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { NSLog("SilentAudio: engine: \(error)"); return }
        player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    var isRunning: Bool { engine.isRunning }
}
