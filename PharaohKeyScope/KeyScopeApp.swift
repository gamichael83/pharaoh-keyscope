import SwiftUI

@main
struct KeyScopeApp: App {
    @State private var model = KeyScopeModel()
    private let capture = SystemAudioCapture()
    @State private var analyzer = AudioAnalyzer()

    var body: some Scene {
        Window("Pharaoh KeyScope", id: "main") {
            MainView()
                .environment(model)
                .task { await startPipeline() }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("KeyScope", systemImage: "music.note") {
            MenuBarView()
                .environment(model)
        }
    }

    /// Wires capture -> analysis -> model, then starts listening to
    /// whatever is playing through the Mac's speakers.
    private func startPipeline() async {
        await MainActor.run {
            analyzer.model = model
            capture.model = model
            // Reset rebuilds the entire analyzer — a clean slate, same as
            // relaunching the app, without quitting. The old pipeline is
            // torn down and a fresh one starts on live audio.
            model.onResetAnalysis = { [weak self] in
                guard let self else { return }
                Task { @MainActor in self.rebuildAnalyzer() }
            }
        }
        capture.onSamples = { [analyzer] samples, rate in
            analyzer.receive(samples: samples, sampleRate: rate)
        }
        do {
            try await capture.start()
            await MainActor.run {
                model.isCapturing = true
                model.statusMessage = "Listening to system audio — play anything."
            }
        } catch {
            await MainActor.run {
                model.isCapturing = false
                model.statusMessage = "Couldn't start capture: \(error.localizedDescription)"
                let msg = error.localizedDescription.lowercased()
                model.permissionDenied = msg.contains("tcc") || msg.contains("declin")
                    || msg.contains("not authorized") || msg.contains("denied")
            }
        }
    }

    /// Tears down the analysis pipeline and starts a fresh one. Called on
    /// Reset — guarantees detection restarts, no stale state survives.
    @MainActor
    private func rebuildAnalyzer() {
        let fresh = AudioAnalyzer()
        fresh.model = model
        analyzer = fresh
        capture.onSamples = { [fresh] samples, rate in
            fresh.receive(samples: samples, sampleRate: rate)
        }
    }
}
