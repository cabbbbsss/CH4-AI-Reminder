//
//  PlusCrown.swift
//  Eve
//

import SwiftUI

/// The EVE Plus crown, from Sketch — the one glyph every place the tier is
/// marked draws, so Home, Location and Settings cannot drift apart.
///
/// The artboards use it two ways, which is what `tint` selects between:
///
/// - On the dark inverse surface (Home's pill) it keeps its own
///   white → pale-blue gradient and carries the artboard's drop shadow.
/// - On a light surface (the Location badge, a Settings row) the artboard
///   draws it in the dark navy instead. Tinting template-renders the same
///   artwork, which is also what makes it adapt: the tokens handed in are
///   appearance-aware, so the crown inverts with the rest of the UI rather
///   than staying a fixed colour that disappears in one mode.
struct PlusCrown: View {

    var height: CGFloat

    /// `nil` keeps the artwork's own gradient; a colour template-renders it.
    var tint: Color? = nil

    /// The artboard's shadow, on the marks that carry one.
    var shadow: Bool = false

    var body: some View {
        glyph
            .frame(height: height)
            .shadow(
                color: shadow ? Self.shadowColor : .clear,
                radius: shadow ? 5 : 0,
                y: shadow ? 4 : 0
            )
    }

    @ViewBuilder
    private var glyph: some View {
        if let tint {
            Image("PlusCrown")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
        } else {
            Image("PlusCrown")
                .resizable()
                .scaledToFit()
        }
    }

    /// The artboard's own `#0D2D5B` at 25%. Deliberately fixed rather than
    /// token-driven: a shadow reads as depth in both appearances, and an
    /// appearance-aware one would turn pale in dark mode and glow.
    private static let shadowColor = Color(red: 0.05, green: 0.18, blue: 0.36).opacity(0.25)
}
