import SwiftUI

/// Twelve live chroma bars (C … B). The tonic glows gold, other scale notes
/// glow dimmer — the "musical X-ray" view.
struct NoteVisualizerView: View {
    @Environment(KeyScopeModel.self) private var model

    private let names = ["C", "C#", "D", "D#", "E", "F",
                         "F#", "G", "G#", "A", "A#", "B"]
    private let gold = Color(red: 0.85, green: 0.68, blue: 0.25)

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<12, id: \.self) { i in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(i))
                        .frame(height: max(4, CGFloat(model.chroma[i]) * 90))
                        .animation(.easeOut(duration: 0.08),
                                   value: model.chroma[i])
                    Text(names[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 122)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func barColor(_ i: Int) -> Color {
        if i == model.tonicPitchClass { return gold }
        if model.scalePitchClasses.contains(i) { return gold.opacity(0.55) }
        return .white.opacity(0.25)
    }
}
