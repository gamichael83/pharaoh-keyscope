import Foundation

/// Krumhansl–Schmuckler key profiles, rotated to each tonic, correlated
/// against a slowly-smoothed chroma vector. The displayed key is "sticky":
/// a challenger must win several consecutive evaluations before it replaces
/// what's on screen, so the readout doesn't flicker mid-song.
struct KeyDetection {
    let tonic: Int
    let isMinor: Bool
    let confidence: Double

    static let noteNames = ["C", "C#", "D", "D#", "E", "F",
                            "F#", "G", "G#", "A", "A#", "B"]

    var name: String { "\(Self.noteNames[tonic]) \(isMinor ? "Minor" : "Major")" }

    var camelot: String {
        let majorByTonic = ["8B", "3B", "10B", "5B", "12B", "7B",
                            "2B", "9B", "4B", "11B", "6B", "1B"]
        let minorByTonic = ["5A", "12A", "7A", "2A", "9A", "4A",
                            "11A", "6A", "1A", "8A", "3A", "10A"]
        return isMinor ? minorByTonic[tonic] : majorByTonic[tonic]
    }

    var scalePitchClasses: Set<Int> {
        let intervals = isMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        return Set(intervals.map { ($0 + tonic) % 12 })
    }

    var id: String { "\(tonic)-\(isMinor)" }
}

final class KeyDetector {
    // Krumhansl major/minor profiles (probe-tone ratings).
    private static let majorProfile: [Double] =
        [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] =
        [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Slow smoothing: ~1.4 s time constant at ~23 fps, so a drum fill or
    /// passing chord doesn't yank the key around.
    private let smoothing = 0.03
    private var smoothed = [Double](repeating: 0, count: 12)

    private var displayed: KeyDetection?
    private var challenger: KeyDetection?
    private var challengerWins = 0
    /// Consecutive wins a challenger needs before it takes the display.
    private let winsToSwitch = 8

    private(set) var last: KeyDetection?

    /// - Parameter chroma: unit-sum normalized 12-bin chroma for this frame.
    func update(chroma: [Double]) -> KeyDetection? {
        for i in 0..<12 {
            smoothed[i] = smoothing * chroma[i] + (1 - smoothing) * smoothed[i]
        }
        let total = smoothed.reduce(0, +)
        guard total > 1e-6 else { last = displayed; return displayed }
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
        let absolute = min(1.0, max(0.0, (best - 0.5) * 2.0))
        let marginC = min(1.0, max(0.0, margin * 6.0))
        let confidence = absolute * 0.5 + marginC * 0.5
        let current = KeyDetection(tonic: bestTonic, isMinor: bestMinor,
                                   confidence: confidence)

        if let d = displayed, d.id == current.id {
            challenger = nil
            challengerWins = 0
            last = current
            return current
        }
        if let c = challenger, c.id == current.id {
            challengerWins += 1
        } else {
            challenger = current
            challengerWins = 1
        }
        if challengerWins >= winsToSwitch {
            displayed = current
            challenger = nil
            challengerWins = 0
        }
        last = displayed
        return displayed
    }

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
        let den = (dx * dy).squareRoot()
        return den > 1e-9 ? num / den : 0
    }
}
