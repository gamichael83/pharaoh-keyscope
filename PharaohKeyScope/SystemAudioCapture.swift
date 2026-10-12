import CoreMedia
import Foundation
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? {
        "No display found for system-audio capture."
    }
}

/// Captures whatever is playing through the Mac's speakers using
/// ScreenCaptureKit. Audio-only in spirit — the stream is configured with a
/// trickle of video that we simply ignore.
///
/// First launch will prompt for Screen Recording permission in
/// System Settings → Privacy & Security. That's a macOS requirement for
/// system-audio capture, even with no video being recorded.
final class SystemAudioCapture: NSObject {
    /// Mono Float32 samples + sample rate, delivered on an internal queue.
    var onSamples: (([Float], Double) -> Void)?

    @MainActor weak var model: KeyScopeModel?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.pharaohluxury.keyscope.capture")

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // We only want audio; keep video to a bare-minimum trickle.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        config.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        do { try await stream?.stopCapture() } catch { /* already stopped */ }
        stream = nil
    }

    // MARK: - Audio conversion

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee,
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return }

        let totalLength = CMBlockBufferGetDataLength(dataBuffer)
        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        guard totalLength > 0, bytesPerFrame > 0 else { return }
        let frames = totalLength / bytesPerFrame
        guard frames > 0 else { return }

        // Copy the samples out of the block buffer (this also handles
        // non-contiguous storage) instead of wrestling with AudioBufferList.
        var bytes = [UInt8](repeating: 0, count: totalLength)
        guard CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0,
                                         dataLength: totalLength,
                                         destination: &bytes) == noErr
        else { return }

        let isFloat = asbd.mFormatID == kAudioFormatLinearPCM
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        var mono = [Float]()
        mono.reserveCapacity(frames)
        bytes.withUnsafeBytes { raw in
            if isFloat {
                let ptr = raw.bindMemory(to: Float.self)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += ptr[f * channels + c] }
                    mono.append(sum / Float(channels))
                }
            } else {
                // 16-bit integer fallback.
                let ptr = raw.bindMemory(to: Int16.self)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels {
                        sum += Float(ptr[f * channels + c]) / 32768
                    }
                    mono.append(sum / Float(channels))
                }
            }
        }
        if !mono.isEmpty {
            onSamples?(mono, asbd.mSampleRate)
        }
    }
}

// MARK: - SCStreamOutput / SCStreamDelegate

extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return } // ignore the trickle of video
        handleAudio(sampleBuffer)
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.model?.statusMessage = "Capture stopped: \(error.localizedDescription)"
            self?.model?.isCapturing = false
        }
    }
}
