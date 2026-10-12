import Foundation

/// Tempo estimation from the spectral-flux onset envelope via autocorrelation.
/// Runs on the analysis queue; call from one thread only.
final class TempoDetector {
    private var previousMagnitudes: [Float] = []
    private var envelope: [Float] = []
    /// ~11 s of onset history at 2048-hop / 48 kHz.
    private let windowSize = 512
    /// Recent BPM picks, for median smoothing + octave correction.
    private var estimates: [Double] = []
    private var framesSinceEstimate = 0

    /// Feed one power-spectrum frame. Returns a smoothed BPM about twice a
    /// second once the envelope window is full, otherwise nil.
    func process(magnitudes: [Float], hopSeconds: Double) -> Double? {
        var flux: Float = 0
        if previousMagnitudes.count == magnitudes.count {
            for i in 0..<magnitudes.count {
                let delta = magnitudes[i] - previousMagnitudes[i]
                if delta > 0 { flux += delta }
            }
        }
        previousMagnitudes = magnitudes
        envelope.append(flux)
        if envelope.count > windowSize { envelope.removeFirst() }

        framesSinceEstimate += 1
        guard envelope.count == windowSize, framesSinceEstimate >= 24 else { return nil }
        framesSinceEstimate = 0

        guard var bpm = autocorrelate(hopSeconds: hopSeconds) else { return nil }

        // Fix octave errors against the running median.
        if let med = median(estimates) {
            if bpm > med * 1.45 { bpm /= 2 }
            else if bpm < med * 0.55 { bpm *= 2 }
        }
        estimates.append(bpm)
        if estimates.count > 9 { estimates.removeFirst() }
        return median(estimates)
    }

    private func autocorrelate(hopSeconds: Double) -> Double? {
        let n = envelope.count
        let mean = envelope.reduce(0, +) / Float(n)
        let zeroed = envelope.map { $0 - mean }
        let energy = zeroed.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-9 else { return nil }

        // Lags for 50…200 BPM.
        let minLag = max(2, Int((60.0 / 200.0) / hopSeconds))
        let maxLag = min(n - 1, Int((60.0 / 50.0) / hopSeconds))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestValue: Float = -.infinity
        for lag in minLag...maxLag {
            var sum: Float = 0
            for i in 0..<(n - lag) { sum += zeroed[i] * zeroed[i + lag] }
            let value = sum / energy
            if value > bestValue { bestValue = value; bestLag = lag }
        }
        // Too weak to trust — probably silence or ambience.
        guard bestValue > 0.05 else { return nil }
        return 60.0 / (Double(bestLag) * hopSeconds)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}
