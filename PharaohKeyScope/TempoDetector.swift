import Foundation

/// Beat tracker: log-domain spectral flux → autocorrelation over a ~22 s
/// window, with three stabilizers —
///   1. a tempo-preference weight (log-Gaussian around 120 BPM, σ = 1.5
///      octaves) so the detector doesn't jump between half/double-time
///      octaves without punishing legitimately slow songs,
///   2. parabolic interpolation of the winning lag for sub-1 % accuracy,
///   3. a sticky display that only moves after a new tempo proves itself.
///
/// The first reading is attempted after ~11 s of audio (256 frames); the
/// full 512-frame window gives the cleanest autocorrelation for soft beats.
final class TempoDetector {
    private var previousLogMags: [Float] = []
    private var envelope: [Float] = []
    private let windowSize = 512
    private let minFramesForEstimate = 256
    private var estimates: [Double] = []
    private var framesSinceEstimate = 0

    private var displayed: Double?
    private var candidate: Double?
    private var candidateHits = 0
    private let hitsToSwitch = 3

    private(set) var last: Double?

    /// Clears all accumulated state so tempo detection restarts fresh.
    func reset() {
        previousLogMags = []
        envelope = []
        estimates = []
        framesSinceEstimate = 0
        displayed = nil
        candidate = nil
        candidateHits = 0
        last = nil
    }

    func process(magnitudes: [Float], hopSeconds: Double) -> Double? {
        // Log-domain flux: onsets stand out regardless of overall loudness.
        let logMags = magnitudes.map { log(1 + $0) }
        var flux: Float = 0
        if previousLogMags.count == logMags.count {
            for i in 0..<logMags.count {
                let d = logMags[i] - previousLogMags[i]
                if d > 0 { flux += d }
            }
        }
        previousLogMags = logMags
        envelope.append(flux)
        if envelope.count > windowSize { envelope.removeFirst() }

        framesSinceEstimate += 1
        guard envelope.count >= minFramesForEstimate, framesSinceEstimate >= 12 else {
            last = displayed
            return displayed
        }
        framesSinceEstimate = 0

        guard let bpm = autocorrelate(hopSeconds: hopSeconds) else {
            last = displayed
            return displayed
        }

        // Nudge octaves toward what we're already showing.
        var adj = bpm
        if let d = displayed {
            if adj > d * 1.45 { adj /= 2 }
            else if adj < d * 0.55 { adj *= 2 }
        }
        estimates.append(adj)
        if estimates.count > 9 { estimates.removeFirst() }
        guard let med = median(estimates) else { last = displayed; return displayed }

        let tol: (Double) -> Double = { max(1.0, $0 * 0.015) }
        if let d = displayed, abs(med - d) <= tol(d) {
            displayed = d * 0.6 + med * 0.4
            candidate = nil
            candidateHits = 0
        } else if let c = candidate, abs(med - c) <= tol(c) {
            candidateHits += 1
            candidate = c * 0.7 + med * 0.3
            if candidateHits >= hitsToSwitch {
                displayed = candidate
                candidate = nil
                candidateHits = 0
            }
        } else {
            candidate = med
            candidateHits = 1
        }
        last = displayed
        return displayed
    }

    /// Unbiased normalized autocorrelation with a tempo-preference weight and
    /// parabolic interpolation around the winning lag.
    private func autocorrelate(hopSeconds: Double) -> Double? {
        let n = envelope.count
        let mean = envelope.reduce(0, +) / Float(n)
        let zeroed = envelope.map { $0 - mean }
        var variance: Float = 0
        for v in zeroed { variance += v * v }
        variance /= Float(n)
        guard variance > 1e-12 else { return nil }

        let minLag = max(2, Int((60.0 / 200.0) / hopSeconds))
        let maxLag = min(n / 2, Int((60.0 / 50.0) / hopSeconds))
        guard maxLag > minLag else { return nil }

        // Log-Gaussian preference centered on 120 BPM, σ = 1.5 octaves.
        // Gentle nudge against half/double-time octave jumps without
        // punishing legitimately slow (or fast) songs.
        func preference(_ lag: Int) -> Double {
            let bpm = 60.0 / (Double(lag) * hopSeconds)
            let octaves = log2(bpm / 120.0) / 1.5
            return exp(-0.5 * octaves * octaves)
        }

        var raw = [Float](repeating: 0, count: maxLag - minLag + 1)
        var bestLag = minLag
        var bestScore = -Float.infinity
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in 0..<(n - lag) { s += zeroed[i] * zeroed[i + lag] }
            let r = s / (Float(n - lag) * variance)
            raw[lag - minLag] = r
            let score = r * Float(preference(lag))
            if score > bestScore { bestScore = score; bestLag = lag }
        }

        // Octave correction: if the half-tempo lag also has a strong peak,
        // prefer the slower (fundamental) beat. Subdivisions (eighth-note
        // strums, hi-hats) often outscore the true tactus in ballads.
        if bestLag * 2 <= maxLag {
            let fast = raw[bestLag - minLag]
            let slow = raw[bestLag * 2 - minLag]
            if slow > fast * 0.6 {
                bestLag *= 2
                bestScore = slow * Float(preference(bestLag))
            }
        }

        guard bestScore > 0.10 else { return nil }

        // Parabolic interpolation on the raw curve for sub-lag precision.
        var refined = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let r0 = raw[bestLag - minLag - 1]
            let r1 = raw[bestLag - minLag]
            let r2 = raw[bestLag - minLag + 1]
            let den = Double(r0 - 2 * r1 + r2)
            if abs(den) > 1e-6 {
                let delta = 0.5 * Double(r0 - r2) / den
                if abs(delta) <= 1 { refined = Double(bestLag) + delta }
            }
        }
        return 60.0 / (refined * hopSeconds)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}
