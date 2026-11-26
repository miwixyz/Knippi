// AmbientBackdrop.swift — ruhig lebender Hintergrund für Knippis Fenster (Glas-Umbau Phase 2).
//
// Ein MeshGradient aus den Schiefer-Tönen der Familie mit einem weichen Akzent-Glühen.
// Er bewegt sich sehr langsam (ein Zyklus ~24 s), damit Liquid-Glass-Flächen darüber
// lebendig wirken. Inhalte (Karten, Bild) liegen weiter auf festen Flächen (Regel G1).
//
// Bedienungshilfen: „Bewegung reduzieren“ → stillstehend. „Transparenz reduzieren“
// oder „Kontrast erhöhen“ → einfacher fester Familien-Verlauf.

import SwiftUI

struct AmbientBackdrop: View {
    /// Stärke des Akzent-Glühens (0 … 1). Einstellungen ruhiger, Editor/Verlauf etwas mehr.
    var glow: Double = 0.55

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            LinearGradient(colors: base, startPoint: .top, endPoint: .bottom)
        } else if reduceMotion {
            mesh(phase: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                mesh(phase: (t.truncatingRemainder(dividingBy: 24)) / 24 * 2 * .pi)
            }
        }
    }

    private var base: [Color] {
        colorScheme == .dark
            ? [Color(hex: 0x0D1019), Color(hex: 0x161A25), Color(hex: 0x1F2433)]
            : [Color(hex: 0xF3F5F9), Color(hex: 0xE7E9F1), Color(hex: 0xD9DDE8)]
    }

    private func mesh(phase: Double) -> some View {
        let dx = Float(sin(phase)) * 0.08
        let dy = Float(cos(phase)) * 0.06
        let dark = colorScheme == .dark
        let accent = FamilyTheme.accent
        let glowColor = accent.opacity((dark ? 0.32 : 0.22) * glow)
        let coolColor = Color(hex: dark ? 0x2A3350 : 0xC9D3EA).opacity(0.9)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + dx, 0.5 + dy], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                base[0], base[0], coolColor,
                base[1], glowColor.mix(with: base[1], by: 0.35), base[1],
                coolColor, base[2], base[2],
            ],
            smoothsColors: true
        )
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
