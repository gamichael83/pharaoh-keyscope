# Pharaoh KeyScope

A macOS app in the spirit of Mixed In Key Live: it listens to **whatever is
playing through your Mac's speakers** — Spotify, YouTube, Splice, a sample
library, Ableton, Logic, djay Pro — and instantly shows you the **key
(Camelot code + name), BPM, and live notes**, plus a collapsed menubar view
that floats over your other apps.

Independent homage, not affiliated with Mixed In Key.

## Features

- **System-audio capture** via ScreenCaptureKit — no virtual audio driver needed
- **Key detection**: FFT → 12-band chroma → Krumhansl–Schmuckler key profiles,
  with temporal smoothing and a confidence meter
- **Camelot wheel readout** (e.g. `8B`) — matches the tags in your DJ library
- **BPM detection**: spectral-flux onset envelope → autocorrelation, with
  octave-error correction and median smoothing
- **Live note visualizer**: 12 glowing bars; tonic in gold, scale tones dimmed
- **Scale piano strip**: two octaves highlighting the detected scale
- **Menubar mini view**: key + BPM at a glance while you work in other apps
- Pharaoh gold-on-dark UI

## Requirements

- A Mac with Apple Silicon or Intel, running **macOS 14 (Sonoma) or later**
- **Xcode 16** (free from the Mac App Store)
- An Apple ID signed into Xcode (for code signing; free account is fine)

## Build & run

1. Copy this folder to your Mac.
2. Open `PharaohKeyScope.xcodeproj` in Xcode.
3. Select the `PharaohKeyScope` scheme and your Mac as the destination.
4. Press **⌘R** to build and run.
5. On first launch, macOS asks for **Screen Recording** permission
   (System Settings → Privacy & Security → Screen Recording). This is Apple's
   requirement for capturing system audio — the app records no video and
   never leaves your machine.

Tip: the first key/BPM reading needs a few seconds of music. Percussion-only
intros may read as low confidence until the harmony kicks in — that's normal.

## How it works

```
Speakers → ScreenCaptureKit → mono Float32 @ 48 kHz
        → 4096-pt Hann FFT (Accelerate, hop 2048)
        ├→ chroma (12 pitch classes, 55 Hz–4.2 kHz)
        │    └→ Krumhansl correlation × 24 keys → key + Camelot + confidence
        └→ spectral flux → 11 s onset envelope → autocorrelation
             └→ BPM (50–200) with octave correction
```

## Project layout

| File | What it does |
|---|---|
| `KeyScopeApp.swift` | App entry, window + menubar scenes, pipeline wiring |
| `KeyScopeModel.swift` | Observable UI state |
| `SystemAudioCapture.swift` | ScreenCaptureKit system-audio capture |
| `AudioAnalyzer.swift` | FFT → chroma, drives key + tempo detectors |
| `KeyDetector.swift` | Krumhansl–Schmuckler key + Camelot mapping |
| `TempoDetector.swift` | Onset envelope → autocorrelation BPM |
| `MainView.swift` | Full window UI |
| `NoteVisualizerView.swift` | Live 12-bar chroma display |
| `PianoStripView.swift` | Scale-highlight piano strip |
| `MenuBarView.swift` | Collapsed menubar view |

## Roadmap ideas

- Key/BPM history log per session (great for digging through sample packs)
- "Tap to freeze" a reading for the current sample
- Configurable Camelot-only menubar text
- Audio Unit / plug-in variant for use inside Logic or Ableton
