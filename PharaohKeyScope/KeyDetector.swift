import Foundation

/// Result of key estimation for one analysis window.
struct KeyDetection {
    /// Pitch class of the tonic, 0 = C … 11 = B.
    let tonic: Int
    let isMinor: Bool
    /// 0…1 — how decisively this key won.
    let confidence: Double

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var name: String { "\(Self.noteNames[tonic]) \(isMinor ? "Minor" : "Major")" }

    /// Camelot wheel code — matches the tags in your DJ library.
    /// Fifths order: C=8B, G=9B, D=10B, A=11B, E=12B, B=1B, F#=2B,
    /// Db=3B, Ab=4B, Eb=5B, Bb=6B, F=7B (minor = same number + "A").
    var camelot: String {
        let majorByTonic = ["8B","3B","10B","5B","12B","7B","2B","9B","4B","11B","6B","1B"]
        let minorByTonic = ["5A","12A","7A","2A","9A","4A","11A","6A","1A","8A","3A","10A"]
        return isMinor ? minorByTonic[tonic] : majorByTonic[tonic]
    }

    /// Pitch classes of the detected scale (major / natural minor).
    var scalePitchClasses: Set<Int> {
        let intervals = isMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        return Set(intervals.map { ($0 + tonic) % 12 })
    }
}

/// Key estimation by correlating the chroma vector against the
/// Krumhansl–Schmuckler key profiles, with temporal smoothing so the
/// readout doesn't flicker between frames.
final class KeyDetector {
    // Krumhansl–Schmuckler probe-tone profiles.
    private static let majorProfile: [Double] =
        [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] =
        [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private var smoothed = [Double](repeating: 0, count: 12)
    private let smoothing: Double = 0.10
    private var lastDetection: KeyDetection?

    /// Feed one normalized (0…1) chroma frame. Returns the current best guess,
    /// or the previous guess when there isn't enough energy yet.
    func update(chroma: [Double]) -> KeyDetection? {
        for i in 0..<12 {
            smoothed[i] = smoothing * chroma[i] + (1 - smoothing) * smoothed[i]
        }
        let total = smoothed.reduce(0, +)
        guard total > 1e-4 else { return lastDetection }
        let vector = smoothed.map { $0 / total }

        var best = -2.0, runnerUp = -2.0
        var bestTonic = 0, bestMinor = false
        for tonic in 0..<12 {
            for isMinor in [false, true] {
                let profile = isMinor ? Self.minorProfile : Self.majorProfile
                let r = pearson(vector, rotated(profile, tonic: tonic))
                if r > best {
                    runnerUp = best; best = r
                    bestTonic = tonic; bestMinor = isMinor
                } else if r > runnerUp {
                    runnerUp = r
                }
            }
        }
        let margin = best - runnerUp
        let confidence = min(1.0, max(0.0, (best - 0.5) * 1.6 + margin * 2.0))
        let detection = KeyDetection(tonic: bestTonic, isMinor: bestMinor,
                                     confidence: confidence)
        lastDetection = detection
        return detection
    }

    /// Rotate a key profile so index 0 is the given tonic.
    private func rotated(_ profile: [Double], tonic: Int) -> [Double] {
        (0..<12).map { profile[($0 - tonic + 12) % 12] }
    }

    private func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<x.count {
            let a = x[i] - mx, b = y[i] - my
            num += a * b; dx += a * a; dy += b * b
        }
        let den = sqrt(dx * dy)
        return den > 1e-9 ? num / den : 0
    }
}
