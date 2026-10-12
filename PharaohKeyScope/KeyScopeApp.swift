import SwiftUI

@main
struct KeyScopeApp: App {
    @State private var model = KeyScopeModel()
    private let capture = SystemAudioCapture()
    private let analyzer = AudioAnalyzer()

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
            }
        }
    }
}
