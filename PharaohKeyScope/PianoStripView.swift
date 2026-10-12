import SwiftUI

/// Two-octave piano strip highlighting the detected scale.
/// The tonic key glows gold, other scale tones glow dimmer.
struct PianoStripView: View {
    @Environment(KeyScopeModel.self) private var model

    private let gold = Color(red: 0.85, green: 0.68, blue: 0.25)

    /// 24 semitones starting at C: (pitchClass, isBlackKey).
    private var keys: [(pc: Int, isBlack: Bool)] {
        (0..<24).map { i in
            let pc = i % 12
            return (pc, [1, 3, 6, 8, 10].contains(pc))
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<24, id: \.self) { i in
                let key = keys[i]
                RoundedRectangle(cornerRadius: 3)
                    .fill(keyColor(key))
                    .frame(width: key.isBlack ? 16 : 26,
                           height: key.isBlack ? 64 : 96)
            }
        }
        .frame(height: 100)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func keyColor(_ key: (pc: Int, isBlack: Bool)) -> Color {
        if key.pc == model.tonicPitchClass { return gold }
        if model.scalePitchClasses.contains(key.pc) { return gold.opacity(0.45) }
        return key.isBlack ? Color(white: 0.12) : Color(white: 0.85)
    }
}
