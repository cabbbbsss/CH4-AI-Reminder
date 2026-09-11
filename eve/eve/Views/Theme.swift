//
//  Theme.swift
//  Eve
//
//  The app's design tokens: spacing, corner radii, type scale, semantic
//  colors and the shared screen background.
//
//  Screens used to hardcode their own sizes ("size: 15, weight: .bold",
//  padding 39, radius 22) and re-declare the same blurred backdrop five
//  times with slightly different numbers. Everything visual now comes from
//  here, so a change lands on every screen at once.
//

import SwiftUI

enum Theme {

    /// The only vertical/horizontal gaps used in the app. Anything not on
    /// this scale is a one-off and should be justified where it's written.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        /// The inset every full-width screen uses from the display edge, so
        /// headers, cards and floating buttons all line up on one margin.
        static let gutter: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 16
        static let panel: CGFloat = 24
        /// The big top-corner sweep on sheets and full-bleed panels.
        static let sheet: CGFloat = 32
    }
}

// MARK: - Semantic colors

/// The asset palette is built from *inverting pairs*: `Text-Primary` is
/// near-white in dark mode and near-black in light mode, and `Text-Secondary`
/// is its exact opposite. That makes `Text-Primary` usable as an inverted
/// panel fill — but only if whatever sits on it switches to `Text-Secondary`.
///
/// Getting that backwards renders content in the same color as the surface
/// behind it (an invisible icon on the "Apple Intelligence missing" card, and
/// hardcoded white log text that vanished in light mode). These names encode
/// the pairing so the compiler-visible name says which surface a color is for.
extension ShapeStyle where Self == Color {

    /// The base background of every screen.
    static var eveBackground: Color { Color(.bgPrimary) }

    /// Cards and panels resting on `eveBackground`.
    static var eveSurface: Color { Color(.bgSecondary) }

    /// Raised controls resting on `eveSurface`.
    static var eveSurfaceRaised: Color { Color(.bgTertiary) }

    /// Primary text and icons on `eveBackground` / `eveSurface`.
    static var eveOnSurface: Color { Color(.textPrimary) }

    /// De-emphasised text on `eveBackground` / `eveSurface`.
    static var eveOnSurfaceMuted: Color { Color(.textTertiary) }

    /// The faintest readable text — placeholders, timestamps, disabled rows.
    static var eveOnSurfaceFaint: Color { Color(.textQuarternary) }

    /// A deliberately inverted panel (a highlighted row, a callout card).
    /// Anything drawn on this MUST use `eveOnInverseSurface`.
    static var eveInverseSurface: Color { Color(.textPrimary) }

    /// Text and icons on `eveInverseSurface`.
    static var eveOnInverseSurface: Color { Color(.textSecondary) }
}

// MARK: - Type scale

/// Every size maps onto a system text style, so the whole app now responds
/// to Dynamic Type — `.system(size:)` is a fixed point size and ignored the
/// user's accessibility text setting entirely.
extension Font {

    /// Splash-screen wordmark. The one intentionally fixed size in the app.
    static let eveHero = Font.system(size: 76, weight: .bold)

    /// The single largest piece of text on a screen: a greeting, a month.
    static let eveScreenTitle = Font.system(.title, weight: .semibold)

    /// Onboarding headlines and question text.
    static let eveHeadline = Font.system(.title2, weight: .bold)

    /// A section heading inside a screen ("Today's Routine").
    static let eveSectionTitle = Font.system(.headline, weight: .bold)

    /// The title line of a card or list row.
    static let eveCardTitle = Font.system(.subheadline, weight: .bold)

    /// Running text inside a card.
    static let eveBody = Font.system(.subheadline, weight: .medium)

    /// Supporting detail under a title — locations, times, subtitles.
    static let eveDetail = Font.system(.footnote, weight: .regular)

    /// Metadata: progress counters, relative times.
    static let eveCaption = Font.system(.caption, weight: .semibold)

    /// All-caps labels above a card's content.
    static let eveOverline = Font.system(.caption2, weight: .bold)

    /// Button labels.
    static let eveButton = Font.system(.callout, weight: .bold)
}

// MARK: - Shared background

/// The soft blurred wash behind every screen.
///
/// Sized off the container rather than the fixed 800×500 rectangle each
/// screen used to draw at a hardcoded `position(x: 200, y: 150)` — those
/// numbers assumed a 390pt-wide iPhone and drifted off-centre everywhere else.
struct AuroraBackground: View {

    /// Where the wash sits on most screens.
    ///
    /// Named because the splash deliberately starts lower and animates back to
    /// this on its way out — two screens showing the wash at different heights
    /// cross-fade as a visible shift in brightness, which reads as the
    /// background "changing colour" mid-transition.
    static let defaultFocus: CGFloat = 0.18

    /// How far down the screen the wash is centred, as a fraction of height.
    var focus: CGFloat = defaultFocus

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.eveBackground

                Ellipse()
                    .fill(Color.eveSurface.opacity(0.8))
                    .frame(
                        width: proxy.size.width * 2.0,
                        height: proxy.size.height * 0.6
                    )
                    .blur(radius: 120)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * focus
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Idle float

extension Animation {

    /// The slow drift the mascot and its thought bubbles ride on, so the
    /// onboarding screens breathe instead of sitting perfectly still.
    ///
    /// Give neighbouring elements slightly different durations — bobbing in
    /// lockstep reads as one rigid object rather than several floating ones.
    static func eveFloat(_ duration: Double) -> Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }
}

extension View {

    /// Adds the idle float to a view.
    ///
    /// The offset is a function of the wall clock, not of view state. That
    /// matters at a screen change: a state-driven bob restarts its phase every
    /// time a view is created, so the splash handing off to the permission step
    /// would drop its mascot from wherever she had drifted to onto whatever
    /// point the next screen's animation started at — and, mid cross-fade, show
    /// both at once at different heights.
    ///
    /// Reading the shared clock instead makes position a pure function of time,
    /// so any two screens using the same `period` agree on where the mascot is
    /// at every instant and the hand-off has nothing to jump.
    ///
    /// Apply innermost, so an entrance fade or a screen-to-screen move applied
    /// further out keeps its own timing.
    func floating(_ amplitude: CGFloat, period: Double) -> some View {
        modifier(IdleFloat(amplitude: amplitude, period: period))
    }
}

private struct IdleFloat: ViewModifier {
    let amplitude: CGFloat
    let period: Double

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            content.offset(y: sin(seconds * 2 * .pi / period) * amplitude)
        }
    }
}

// MARK: - Mascot placement

/// Where Eve's mascot stands on each onboarding screen, as fractions of the
/// display.
///
/// Shared rather than written into each screen so the splash can animate to
/// exactly where the permission step will draw her. If these two drifted
/// apart the hand-off between the screens would visibly jump, which is the
/// one thing the transition exists to avoid.
enum MascotPlacement {

    /// Splash: centred just past the trailing edge, so only her leading half
    /// is on screen.
    static let splashWidth: CGFloat = 0.75
    static let splashCenterX: CGFloat = 0.95

    /// Permission: centred on the leading edge, mirrored, leaving the right
    /// of the display for the copy.
    static let permissionWidth: CGFloat = 0.80
    static let permissionCenterX: CGFloat = 0

    /// Identical on both screens, so the walk between them is purely sideways.
    static let centerY: CGFloat = 0.48

    /// The mascot's idle bob, in seconds.
    ///
    /// Both onboarding screens must use the same value: `floating` derives the
    /// offset from the clock, so equal periods mean equal positions at any
    /// instant — which is what makes the hand-off seamless. Different periods
    /// would put the two screens out of phase again.
    static let floatPeriod: Double = 3.0

    /// The thought bubble's bob. Deliberately not the mascot's, so the two
    /// don't drift in lockstep and read as one rigid object.
    static let bubbleFloatPeriod: Double = 2.4
}

// MARK: - Thought bubble

/// The white cloud the mascot "thinks" in, used across onboarding: a glyph
/// inside an ellipse, with the small dots trailing off towards Eve.
///
/// Shared rather than redeclared per screen so the two onboarding steps can't
/// drift apart, and so the tail can be mirrored to point at the mascot
/// whichever edge it is bleeding off.
struct ThoughtBubble: View {

    /// SF Symbol drawn inside the cloud. nil leaves the cloud empty.
    var systemName: String?

    /// The side the tail dots sit on — point them towards the mascot.
    var tail: HorizontalEdge = .trailing

    /// How many tail dots to draw (1 or 2).
    var tailDots: Int = 1

    /// Everything inside scales from this, so the bubble stays in proportion
    /// at any screen width.
    var width: CGFloat

    var body: some View {
        let direction: CGFloat = tail == .leading ? -1 : 1

        // Sized to the ellipse alone, so `.position` places the cloud itself.
        // The tail dots deliberately overflow the frame.
        ZStack {
            Ellipse()
                .fill(.white)
                .frame(width: width, height: width * 0.72)
                .shadow(color: .black.opacity(0.10), radius: width * 0.09, y: width * 0.05)
                .overlay {
                    if let systemName {
                        Image(systemName: systemName)
                            .font(.system(size: width * 0.34, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

            Circle()
                .fill(.white)
                .frame(width: width * 0.085, height: width * 0.085)
                .offset(x: direction * width * 0.44, y: width * 0.36)

            if tailDots > 1 {
                Circle()
                    .fill(.white)
                    .frame(width: width * 0.055, height: width * 0.055)
                    .offset(x: direction * width * 0.54, y: width * 0.46)
            }
        }
        .frame(width: width, height: width * 0.72)
    }
}

// MARK: - Card

extension View {

    /// Standard card treatment: a surface fill with a continuous corner.
    func eveCard(
        radius: CGFloat = Theme.Radius.card,
        fill: Color = .eveSurface
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Selective corner rounding

/// Rounds only some corners — used for the chat bubble's flat top-left and
/// the calendar panel's top sweep.
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
