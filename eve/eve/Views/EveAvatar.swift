//
//  EveAvatar.swift
//  Eve
//

import SwiftUI

/// Eve's avatar beside a speech bubble — crowned for EVE Plus subscribers.
///
/// Home, Insight and History all draw it through here, so a subscriber sees
/// the same crowned Eve on every screen she speaks from.
///
/// The crowned version is Sketch `EF478372` exported whole (`AvatarPlus`,
/// 1x–3x) rather than composed from `Avatar` plus separate crown and ribbon
/// assets. One change from the artboard: the ribbon group's 18pt navy shadow
/// is off in the export. Sketch clips that shadow to the ribbon's own frame,
/// so it rendered as a faint hard-edged box behind the avatar.
///
/// It is taller than the plain avatar — crown above, ribbon tails below — so
/// it is laid out against the plain avatar's square frame and allowed to
/// spill out of it: the sphere lands exactly where the plain one sits, and
/// subscribing doesn't shift the bubble beside it.
struct EveAvatar: View {

    /// Side of the square frame the plain avatar fills.
    var size: CGFloat

    @Bindable private var subscriptions = SubscriptionService.shared

    var body: some View {
        if subscriptions.isPro {
            Color.clear
                .frame(width: size, height: size)
                .overlay(alignment: .topLeading) {
                    crowned
                }
        } else {
            Image("Avatar")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    // MARK: - Crowned

    /// `AvatarPlus` sized so its sphere matches the plain avatar's, then
    /// offset so the two spheres share a centre.
    private var crowned: some View {
        let scale = size * Self.plainSphere / Self.plusSphere
        return Image("AvatarPlus")
            .resizable()
            .frame(width: Self.plusSize.width * scale, height: Self.plusSize.height * scale)
            .offset(
                x: size / 2 - Self.plusSphereCentre.x * scale,
                y: size / 2 - Self.plusSphereCentre.y * scale
            )
    }

    /// `Avatar` carries a soft glow out to its own edges — the solid body is
    /// 88.3% of the image, centred.
    private static let plainSphere: CGFloat = 0.883

    /// Measured on `AvatarPlus@3x.png`, in its pixels: the image, the sphere's
    /// diameter (Sketch's 60pt `Oval 3`), and the sphere's centre.
    private static let plusSize = CGSize(width: 214, height: 265)
    private static let plusSphere: CGFloat = 179
    private static let plusSphereCentre = CGPoint(x: 106, y: 157.5)
}

#Preview {
    EveAvatar(size: 70)
        .padding(40)
}
