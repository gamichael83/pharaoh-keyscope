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
}
