import SwiftUI

/// Foreground/background wells plus the classic two-row swatch strip.
/// Click sets the foreground, ⌥-click (or right-click) sets the background — same as the
/// mouse buttons on the canvas, so the two halves of the app agree.
struct PaletteBar: View {
    @ObservedObject var editor: Editor

    var body: some View {
        HStack(spacing: 14) {
            ColourPair(editor: editor)

            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(PaletteBar.swatches[row], id: \.self) { hex in
                            Swatch(color: Color(hex: hex)) { secondary in
                                if secondary { editor.secondary = Color(hex: hex) }
                                else { editor.primary = Color(hex: hex) }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    static let swatches: [[UInt32]] = [
        [0x000000, 0x808080, 0x800000, 0x808000, 0x008000, 0x008080, 0x000080,
         0x800080, 0x808040, 0x004040, 0x0080FF, 0x004080, 0x8000FF, 0x804000],
        [0xFFFFFF, 0xC0C0C0, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF,
         0xFF00FF, 0xFFFF80, 0x00FF80, 0x80FFFF, 0x8080FF, 0xFF0080, 0xFF8040],
    ]
}

private struct Swatch: View {
    let color: Color
    let pick: (_ secondary: Bool) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: 17, height: 17)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture { pick(NSEvent.modifierFlags.contains(.option)) }
            .contextMenu { Button("Set as Background") { pick(true) } }
    }
}

private struct ColourPair: View {
    @ObservedObject var editor: Editor

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                well($editor.secondary)
                    .offset(x: 13, y: 13)
                well($editor.primary)
            }
            .frame(width: 45, height: 45)

            Button {
                editor.swapColours()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Swap foreground and background  (X)")
        }
    }

    private func well(_ binding: Binding<Color>) -> some View {
        ColorPicker("", selection: binding, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32, height: 32)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
