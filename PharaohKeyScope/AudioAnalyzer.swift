import Accelerate
import Foundation

/// Turns raw system-audio samples into key / BPM / chroma updates.
/// All DSP runs on a private serial queue; results are published to the
/// model on the main actor. Larger FFT (8192) for decent bass resolution,
/// log-compressed chroma so one loud partial can't dominate the key vote.
final class AudioAnalyzer {
    private let frameSize = 8192
    private let hopSize = 2048
    private let processingQueue = DispatchQueue(label: "com.pharaohluxury.keyscope.analysis")

    private var ring: [Float] = []
    private var sampleRate: Double = 48_000
    private let window: [Float]
    private let fftSetup: FFTSetup
    private let keyDetector = KeyDetector()
    private let tempoDetector = TempoDetector()
    private var frameCounter = 0
    private var peakEnergy: Float = 0

    @MainActor weak var model: KeyScopeModel?

    init() {
        var w = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&w, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        window = w
        let log2n = vDSP_Length(log2(Float(frameSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    func receive(samples: [Float], sampleRate: Double) {
        processingQueue.async { [weak self] in
            self?.ingest(samples: samples, sampleRate: sampleRate)
        }
    }

    // MARK: - Pipeline

    private func ingest(samples: [Float], sampleRate: Double) {
        self.sampleRate = sampleRate
        ring.append(contentsOf: samples)
        while ring.count >= frameSize {
            process(frame: Array(ring.prefix(frameSize)))
            ring.removeFirst(hopSize)
        }
        let cap = frameSize * 4
        if ring.count > cap { ring.removeFirst(ring.count - cap) }
    }

    private func process(frame: [Float]) {
        let n = frameSize
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var realp = [Float](repeating: 0, count: n / 2)
        var imagp = [Float](repeating: 0, count: n / 2)
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { bp in
                    bp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Float(n))), FFTDirection(FFT_FORWARD))
            }
        }

        // Power spectrum.
        var magnitudes = [Float](repeating: 0, count: n / 2)
        realp.withUnsafeBufferPointer { rp in
            imagp.withUnsafeBufferPointer { ip in
                var split = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: rp.baseAddress!),
                                            imagp: UnsafeMutablePointer(mutating: ip.baseAddress!))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }
        // Fix DC and Nyquist scaling from the packed real FFT.
        magnitudes[0] *= 0.5
        if magnitudes.count > 1 { magnitudes[magnitudes.count - 1] *= 0.5 }

        analyze(magnitudes: magnitudes)
    }

    private func analyze(magnitudes: [Float]) {
        // Silence gate: ignore frames far below recent peak energy so noise
        // doesn't inject garbage into the detectors.
        let energy = magnitudes.reduce(0, +)
        peakEnergy = max(energy, peakEnergy * 0.999)
        let audible = peakEnergy > 0 && energy > 0.03 * peakEnergy

        var chroma = [Double](repeating: 0, count: 12)
        if audible {
            let bins = magnitudes.count
            for k in 2..<bins {
                let power = Double(magnitudes[k])
                guard power > 0 else { continue }
                let freq = Double(k) * sampleRate / Double(frameSize)
                guard freq >= 55, freq <= 4200 else { continue }
                let midi = 69.0 + 12.0 * log2(freq / 440.0)
                var pc = Int(round(midi)) % 12
                if pc < 0 { pc += 12 }
                chroma[pc] += sqrt(power)
            }
            // Log compression tames a single dominant pitch class
            // (e.g. the kick drum), then unit-sum normalize for correlation.
            let compressed = chroma.map { log(1 + $0) }
            let sum = compressed.reduce(0, +)
            if sum > 0 { chroma = compressed.map { $0 / sum } }
        }

        let hopSeconds = Double(hopSize) / sampleRate
        var detection = keyDetector.last
        var bpm = tempoDetector.last
        if audible {
            detection = keyDetector.update(chroma: chroma)
            bpm = tempoDetector.process(magnitudes: magnitudes, hopSeconds: hopSeconds)
        }

        // Top-3 pitch classes for the readout strip.
        let topNotes: [String]? = audible
            ? chroma.enumerated()
                .sorted { $0.element > $1.element }
                .prefix(3)
                .map { KeyDetection.noteNames[$0.offset] }
            : nil

        frameCounter += 1
        let publishKey = frameCounter % 24 == 0
        Task { @MainActor [weak self, detection, bpm, topNotes, chroma, publishKey] in
            guard let self, let model = self.model else { return }
            model.chroma = chroma
            if let topNotes { model.topNotes = topNotes }
            if publishKey {
                if let detection {
                    model.keyName = detection.name
                    model.camelot = detection.camelot
                    model.confidence = detection.confidence
                    model.scalePitchClasses = detection.scalePitchClasses
                    model.tonicPitchClass = detection.tonic
                }
                if let bpm { model.bpm = bpm }
            }
        }
    }
}
