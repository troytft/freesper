import Foundation

/// Microphones differ in output level by roughly 5× — a built-in laptop mic
/// against a headset — so a fixed RMS-to-height mapping leaves quiet mics
/// looking dead. This turns a window of raw RMS samples into ready-to-draw
/// bar intensities (0…1), adapting its full-bar reference to the microphone
/// so every mic fills the overlay equally.
struct WaveformNormalizer {
  private let noiseFloor: Float = 0.008

  /// Lower bound on the full-bar reference: keeps ambient noise from filling
  /// the bars while nobody speaks. Must stay above `noiseFloor`.
  private let minReference: Float = 0.03

  /// Reference seed — between a quiet built-in mic and a loud headset.
  private let initialReference: Float = 0.05

  /// Per-tick easing of the reference toward the recent peak. Kept gradual so
  /// the reference tracks the microphone, not individual syllables — a
  /// reference that snapped to every syllable would rescale all bars at once
  /// and make the waveform pump. Attack (rising) outpaces release (falling).
  private let attack: Float = 0.10
  private let release: Float = 0.027

  private var reference: Float

  init() {
    reference = initialReference
  }

  mutating func reset() {
    reference = initialReference
  }

  mutating func intensities(forRecent rmsWindow: [Float]) -> [Float] {
    easeReference(towardPeak: rmsWindow.max() ?? 0)

    let span = reference - noiseFloor
    return rmsWindow.map { rms in
      let signal = max(0, rms - noiseFloor)
      let filled = min(1, signal / span)
      return sqrt(filled)
    }
  }

  private mutating func easeReference(towardPeak peak: Float) {
    let rate = peak > reference ? attack : release
    let eased = reference + (peak - reference) * rate
    reference = max(minReference, eased)
  }
}
