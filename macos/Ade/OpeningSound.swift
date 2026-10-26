import AVFoundation

/// Local, original eight-second sound signature. No network, microphone or system volume changes.
@MainActor final class OpeningSound {
  private var player: AVAudioPlayer?
  func play(at time: Double, enabled: Bool) {
    if player == nil,
      let url = Bundle.main.url(
        forResource: "ade-opening", withExtension: "wav", subdirectory: "Resources/Sound")
    {
      player = try? AVAudioPlayer(contentsOf: url)
      player?.prepareToPlay()
    }
    player?.volume = enabled ? 0.55 : 0
    player?.currentTime = time
    player?.play()
  }
  func setEnabled(_ enabled: Bool) { player?.setVolume(enabled ? 0.55 : 0, fadeDuration: 0.15) }
  func pause() { player?.pause() }
  func stop() {
    player?.stop()
    player = nil
  }
}
