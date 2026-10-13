# Pharaoh KeyScope — Build Changelog

Every functional build pushed to GitHub, in order. The in-app "Build N"
label (bottom status bar) matches the commit message here.

## Build 12 — Reset reliability fix
- Reset no longer clears the audio ring buffer or peak tracker —
  Build 11's version stalled the pipeline (nothing detected after Reset).
  Now only the key/tempo detector state is cleared; audio keeps flowing.

## Build 11 — Tempo octave correction
- If the half-tempo lag also has a strong autocorrelation peak
  (≥ 0.6× the winning peak), the detector now prefers the slower,
  fundamental beat. Fixes double-time readings like 143 BPM on a
  72 BPM ballad, where eighth-note subdivisions outscored the true tactus.

## Build 10 — Reset button
- New **Reset** button in the status bar: clears all detector memory
  (key smoothing, bass chroma, tempo history, sticky display) and the
  on-screen readouts, so analysis restarts fresh on your command —
  use it when a new track starts.
- KeyDetector, TempoDetector, and AudioAnalyzer each grew a `reset()`.

## Build 9 — Tempo reliability fix
- Restored the full 512-frame (~22 s) autocorrelation window: Build 7's
  shorter window was too noisy and soft/slow beats fell below the
  detection threshold (BPM went blank on ballads).
- First BPM attempt now after 256 frames (~11 s) instead of 512.
- 120-BPM preference widened (σ = 1.5 octaves) so slow tempos like
  72 BPM aren't penalized; detection threshold 0.12 → 0.10.

## Build 8 — In-app build number
- Status bar now shows "Build N", matching the GitHub commit message,
  so every screenshot self-identifies which code produced it.

## Build 7 — Faster tempo lock (reverted in Build 9)
- Tempo window 512 → 256 frames, first reading after ~7 s.
- Turned out to break weak beats — reverted.

## Build 6 — Tiebreak noise fix
- The bass-tonic tiebreak could flip keys on noise-level bass
  differences (e.g. 0.02 vs 0.01 still triggered the 1.25× ratio).
- Now requires the runner-up's tonic to be near-dominant in the bass
  (≥ 0.8× the strongest bass note, and that max > 0.1).

## Build 5 — Bass-tonic tiebreak
- When the top two key candidates are within 0.06 correlation
  (cousin keys share most notes), the one whose tonic dominates the
  < 250 Hz bass chroma wins. The 808/bassline usually sits on the true
  tonic.

## Build 4 — Verify Pitch + permission reset
- **Verify Pitch** button: synthesizes 1.5 s of 440 Hz internally and
  runs it through the real FFT/chroma pipeline — PASS only if the
  detected note is A. No YouTube needed.
- Detects ScreenCapture permission denials (TCC wording) and offers a
  **Reset Permission** button (`tccutil reset`, then quits for a clean
  prompt on relaunch).

## Build 3 — Bass-emphasized chroma
- Chroma bins weighted by 1 / (1 + (f/1000)²), range capped 55–3000 Hz:
  fundamentals outvote the upper harmonics of buzzy detuned synths
  (a saw wave's overtones can imply a whole different key).

## Build 2 — Key hysteresis
- The displayed key now holds unless a challenger beats its correlation
  by 0.08, sustained over 12 consecutive wins — stops the flickering
  between close candidates.

## Build 1 — Initial release
- System-audio capture (ScreenCaptureKit), live key detection
  (Krumhansl template matching on 8192-point FFT chroma), BPM via
  log-domain spectral flux + autocorrelation, live note visualizer,
  Camelot readout, menu-bar mini view.
