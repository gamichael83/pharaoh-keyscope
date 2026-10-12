import Accelerate
import Foundation

/// Turns raw system-audio samples into key / BPM / chroma updates.
/// All DSP runs on a private serial queue; results are published to the
/// @MainActor model. Call `receive` from any thread.
final class AudioAnalyzer {
    private let frameSize = 4096
    private let hopSize = 2048
    private let processingQueue = DispatchQueue(
        label: "com.pharaohluxury.keyscope.analysis")

    private var ring: [Float] = []
    private var sampleRate: Double = 48_000
    private let window: [Float]
    private let fftSetup: FFTSetup
    private let keyDetector = KeyDetector()
    private let tempoDetector = TempoDetector()
    private var frameCounter = 0

    @MainActor weak var model: KeyScopeModel?

    init() {
        var w = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&w, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        window = w
        let log2n = vDSP_Length(log2(Float(frameSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Called from the capture thread with mono Float32 samples.
    func receive(samples: [Float], sampleRate: Double) {
        processingQueue.async { [weak self] in
            self?.ingest(samples: samples, sampleRate: sampleRate)
        }
    }

    // MARK: - Private (processing queue only)

    private func ingest(samples: [Float], sampleRate: Double) {
        self.sampleRate = sampleRate
        ring.append(contentsOf: samples)
        while ring.count >= frameSize {
            process(frame: Array(ring.prefix(frameSize)))
            ring.removeFirst(hopSize)
        }
        // Safety valve: never let the ring grow unbounded.
        let cap = frameSize * 4
        if ring.count > cap { ring.removeFirst(ring.count - cap) }
    }

    private func process(frame: [Float]) {
        // Window, then real-to-complex FFT via Accelerate.
        var windowed = [Float](repeating: 0, count: frameSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

        var realp = [Float](repeating: 0, count: frameSize / 2)
        var imagp = [Float](repeating: 0, count: frameSize / 2)
        var magnitudes = [Float](repeating: 0, count: frameSize / 2)
        let log2n = vDSP_Length(log2(Float(frameSize)))

        realp.withUnsafeMutableBufferPointer { rbp in
            imagp.withUnsafeMutableBufferPointer { ibp in
                var split = DSPSplitComplex(realp: rbp.baseAddress!,
                                            imagp: ibp.baseAddress!)
                windowed.withUnsafeBufferPointer { wbp in
                    wbp.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                      capacity: frameSize / 2) { src in
                        vDSP_ctoz(src, 2, &split, 1, vDSP_Length(frameSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(frameSize / 2))
            }
        }
        analyze(magnitudes: magnitudes)
    }

    private func analyze(magnitudes: [Float]) {
        // --- Chroma: fold the spectrum into 12 pitch classes. ---
        var chroma = [Double](repeating: 0, count: 12)
        let bins = magnitudes.count
        for k in 2..<bins {
            let power = Double(magnitudes[k])
            guard power > 0 else { continue }
            let freq = Double(k) * sampleRate / Double(frameSize)
            guard freq >= 55, freq <= 4200 else { continue } // musical range
            let midi = 69.0 + 12.0 * log2(freq / 440.0)
            var pc = Int(round(midi)) % 12
            if pc < 0 { pc += 12 }
            chroma[pc] += sqrt(power) // soften dominant partials a little
        }
        let peak = chroma.max() ?? 0
        let normalized = peak > 0 ? chroma.map { $0 / peak } : chroma

        // --- Key + tempo ---
        let detection = keyDetector.update(chroma: normalized)
        let hopSeconds = Double(hopSize) / sampleRate
        let bpm = tempoDetector.process(magnitudes: magnitudes,
                                        hopSeconds: hopSeconds)

        // --- Top notes for the readout ---
        let topNotes = normalized.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(3)
            .map { KeyDetection.noteNames[$0.offset] }

        frameCounter += 1
        // Key/BPM text updates ~2×/s; the note visualizer gets every frame.
        let publishKey = frameCounter % 12 == 0

        Task { @MainActor [weak self, detection, bpm, normalized, topNotes, publishKey] in
            guard let model = self?.model else { return }
            model.chroma = normalized
            model.topNotes = topNotes
            if publishKey, let detection {
                model.keyName = detection.name
                model.camelot = detection.camelot
                model.confidence = detection.confidence
                model.scalePitchClasses = detection.scalePitchClasses
                model.tonicPitchClass = detection.tonic
            }
            if let bpm {
                model.bpm = bpm
            }
        }
    }
}
