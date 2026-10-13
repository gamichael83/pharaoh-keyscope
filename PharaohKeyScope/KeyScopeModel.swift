import AppKit
import Foundation
import SwiftUI

/// Shared, observable state for the whole app. Published on @MainActor;
/// the audio pipeline pushes updates here from background queues.
@Observable
@MainActor
final class KeyScopeModel {
    /// e.g. "C Major"
    var keyName: String = "—"
    /// Camelot wheel code, e.g. "8B" — matches your DJ library tags.
    var camelot: String = "—"
    /// 0…1, how decisively the detected key won.
    var confidence: Double = 0
    /// Smoothed BPM estimate, 0 until enough audio has been heard.
    var bpm: Double = 0
    /// Live 12-band chroma, normalized 0…1. Drives the note visualizer.
    var chroma: [Double] = Array(repeating: 0, count: 12)
    /// Pitch classes of the detected scale (for highlighting).
    var scalePitchClasses: Set<Int> = []
    /// Pitch class of the detected tonic, 0 = C.
    var tonicPitchClass: Int = -1
    /// The 3 strongest pitch classes right now, e.g. ["C", "E", "G"].
    var topNotes: [String] = []

    var isCapturing: Bool = false
    var statusMessage: String = "Starting…"

    /// Set when capture failed on a permission/TCC denial.
    var permissionDenied: Bool = false

    /// Result of the built-in pitch self-test, e.g. "PASS — 440 Hz → A".
    var selfTestResult: String = ""
    var selfTestRunning: Bool = false

    /// Synthesizes a 440 Hz tone and runs it through the real detector.
    /// Needs no other audio — in fact, silence from the speakers is best.
    func runPitchSelfTest() {
        guard !selfTestRunning else { return }
        selfTestRunning = true
        selfTestResult = "Testing…"
        Task.detached(priority: .userInitiated) {
            let (note, passed) = AudioAnalyzer.pitchSelfTest()
            let text = passed
                ? "PASS — 440 Hz → \(note)"
                : "FAIL — 440 Hz → \(note) (expected A)"
            await MainActor.run {
                self.selfTestResult = text
                self.selfTestRunning = false
            }
        }
    }

    /// Clears this app's ScreenCapture TCC entry, then quits so the next
    /// launch gets a clean permission prompt. For when macOS gets stuck
    /// denying capture even though the toggle is on.
    func resetCapturePermission() {
        statusMessage = "Resetting capture permission…"
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            proc.arguments = ["reset", "ScreenCapture",
                              Bundle.main.bundleIdentifier ?? "com.pharaohluxury.keyscope"]
            try? proc.run()
            proc.waitUntilExit()
            await MainActor.run {
                self.statusMessage = "Permission reset — reopen the app and allow when asked."
                self.permissionDenied = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
