import SwiftUI

/// The collapsed menubar view — key, Camelot code and BPM at a glance,
/// floating over Spotify, Splice, Ableton, Logic, or anything else.
struct MenuBarView: View {
    @Environment(KeyScopeModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.camelot)
                    .font(.title)
                    .bold()
                    .monospacedDigit()
                Spacer()
                Text(model.bpm > 0 ? "\(Int(model.bpm)) BPM" : "— BPM")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(model.keyName)
                .foregroundStyle(.secondary)

            Divider()

            Button("Show Full Window") { openWindow(id: "main") }
                .keyboardShortcut("o")
            Button("Quit KeyScope") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 250)
    }
}
