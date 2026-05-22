#if DEBUG

  import SwiftUI

  struct DeveloperView: View {
    @State private var tool: Tool = .overlay

    enum Tool: String, CaseIterable, Identifiable {
      case overlay = "Overlay"

      var id: Self { self }
    }

    var body: some View {
      VStack(spacing: 0) {
        Picker("Tool", selection: $tool) {
          ForEach(Tool.allCases) { tool in
            Text(tool.rawValue).tag(tool)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.vertical, 12)

        Divider()

        Group {
          switch tool {
          case .overlay:
            OverlayPlayground()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private struct OverlayPlayground: View {
    @State private var model: OverlayState
    @State private var animateLevels = true
    @State private var loudness: Loudness = .normal
    @State private var backgroundIsDark = true

    init() {
      let model = OverlayState()
      model.hotkeyLabel = "F5"
      _model = State(initialValue: model)
    }

    enum Loudness: String, CaseIterable, Identifiable {
      case quiet = "Quiet"
      case normal = "Normal"
      case loud = "Loud"

      var id: Self { self }

      var peakRMS: Float {
        switch self {
        case .quiet: 0.03
        case .normal: 0.10
        case .loud: 0.35
        }
      }
    }

    private struct AnimationInputs: Equatable {
      var animate: Bool
      var loudness: Loudness
    }

    var body: some View {
      @Bindable var model = model
      VStack(spacing: 24) {
        preview

        Form {
          Section("Phase") {
            Picker("Phase", selection: $model.phase) {
              Text("Idle").tag(OverlayState.Phase.idle)
              Text("Hint").tag(OverlayState.Phase.hint)
              Text("Listening").tag(OverlayState.Phase.listening)
              Text("Transcribing").tag(OverlayState.Phase.transcribing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
          }

          Section("Hint") {
            TextField("Hotkey label", text: $model.hotkeyLabel)
          }

          Section("Waveform") {
            Toggle("Animate fake levels", isOn: $animateLevels)
            Picker("Loudness", selection: $loudness) {
              ForEach(Loudness.allCases) { value in
                Text(value.rawValue).tag(value)
              }
            }
            .pickerStyle(.segmented)
          }

          Section("Preview") {
            Toggle("Dark backdrop", isOn: $backgroundIsDark)
          }
        }
        .formStyle(.grouped)
      }
      .task(id: AnimationInputs(animate: animateLevels, loudness: loudness)) {
        guard animateLevels else {
          model.barIntensities = []
          return
        }
        var normalizer = WaveformNormalizer()
        let start = Date()
        while !Task.isCancelled {
          let elapsed = Date().timeIntervalSince(start)
          let rms = Self.fakeRMSWindow(elapsed: elapsed, peak: loudness.peakRMS)
          model.barIntensities = normalizer.intensities(forRecent: rms)
          try? await Task.sleep(for: .milliseconds(33))
        }
      }
    }

    private static func fakeRMSWindow(elapsed: TimeInterval, peak: Float) -> [Float] {
      let floor = peak * 0.15
      return (0..<WaveformView.barCount).map { index in
        let phase = elapsed * 4 + Double(index) * 0.42
        let envelope = sin(.pi * Double(index) / Double(WaveformView.barCount - 1))
        let unit = (sin(phase) + 1) / 2 * envelope
        return floor + Float(unit) * (peak - floor)
      }
    }

    private var preview: some View {
      OverlayView(model: model)
        .frame(
          width: OverlayMetrics.hostSize.width,
          height: OverlayMetrics.hostSize.height
        )
        .padding(.horizontal, 80)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(backgroundIsDark ? Color.black : Color.white)
        .padding(.top, 16)
        .padding(.horizontal, 20)
    }
  }

#endif
