import SwiftUI

/// In-app build number. Increment with every functional build pushed to
/// GitHub, and include it in the commit message (e.g. "Build 8: ...") so
/// the GitHub run list and the app itself stay in order.
let keyScopeBuildNumber = 16

/// The full-size window: key + Camelot readout, BPM, live note visualizer,
/// scale piano strip, and capture status.
struct MainView: View {
    @Environment(KeyScopeModel.self) private var model

    private let gold = Color(red: 0.85, green: 0.68, blue: 0.25)

    var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack {
                Image(systemName: "music.note").foregroundStyle(gold)
                Text("PHARAOH KEY SCOPE")
                    .font(.headline)
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(model.isCapturing ? .green : .red)
                    .help(model.isCapturing ? "Capturing system audio" : "Not capturing")
            }

            // Key + tempo cards
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("KEY").font(.caption).foregroundStyle(.secondary)
                    Text(model.camelot)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(gold)
                        .monospacedDigit()
                    Text(model.keyName).font(.title3)
                    confidenceBar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("TEMPO").font(.caption).foregroundStyle(.secondary)
                    Text(model.bpm > 0 ? String(format: "%.0f", model.bpm) : "—")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM").font(.title3).foregroundStyle(.secondary)
                    Text(model.topNotes.isEmpty ? " " : model.topNotes.joined(separator: "   "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            // Live notes
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE NOTES").font(.caption).foregroundStyle(.secondary)
                NoteVisualizerView()
            }

            // Scale strip
            VStack(alignment: .leading, spacing: 8) {
                Text("SCALE").font(.caption).foregroundStyle(.secondary)
                PianoStripView()
            }

            // Status
            HStack {
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.permissionDenied {
                    Button("Reset Permission") {
                        model.resetCapturePermission()
                    }
                    .font(.footnote)
                    .help("Clears the stuck Screen Recording entry, then quits — reopen and allow when asked")
                }
                if !model.selfTestResult.isEmpty {
                    Text(model.selfTestResult)
                        .font(.footnote)
                        .foregroundStyle(model.selfTestResult.hasPrefix("PASS") ? .green : .red)
                }
                Button(model.selfTestRunning ? "Testing…" : "Verify Pitch") {
                    model.runPitchSelfTest()
                }
                .font(.footnote)
                .disabled(model.selfTestRunning)
                .help("Runs a synthetic 440 Hz tone through the detector to verify pitch mapping")
                Button("Reset") {
                    model.resetAnalysis()
                }
                .font(.footnote)
                .help("Clears the key/BPM history and restarts listening fresh")
                Text("Build \(keyScopeBuildNumber)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .help("In-app build number — matches the GitHub commit message")
            }
        }
        .padding(20)
        .frame(width: 560)
        .preferredColorScheme(.dark)
    }

    private var confidenceBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 3).fill(gold)
                    .frame(width: geo.size.width * model.confidence)
            }
        }
        .frame(height: 6)
    }
}
