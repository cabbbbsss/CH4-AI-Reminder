//
//  PaywallSheets.swift
//  Eve
//
//  The two RevenueCat-hosted surfaces: the paywall (sell EVE Plus) and the
//  Customer Center (manage, cancel, refund, downgrade). Both are laid out from
//  the RevenueCat dashboard rather than in code, so copy, pricing and design
//  change without shipping a build. That also means EVE's colour assets don't
//  apply inside them — style them in the dashboard, not here.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - Paywall

/// The paywall as a sheet. Renders the `current` offering's paywall, so which
/// packages appear — Lifetime, Yearly, Monthly — is a dashboard decision.
struct EvePaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called after a purchase or restore that actually unlocked Pro, so a
    /// caller can continue whatever the user was blocked on.
    var onUnlocked: (() -> Void)?

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { _ in
                SubscriptionService.shared.refreshAfterPaywall()
                onUnlocked?()
                dismiss()
            }
            .onRestoreCompleted { customerInfo in
                // Unlike a purchase, a restore can legitimately find nothing —
                // only dismiss when it actually granted the entitlement.
                guard customerInfo.entitlements[SubscriptionService.entitlementID]?.isActive == true else { return }
                SubscriptionService.shared.refreshAfterPaywall()
                onUnlocked?()
                dismiss()
            }
            .onRequestedDismissal { dismiss() }
    }
}

extension View {
    /// Presents the EVE Plus paywall as a sheet.
    ///
    /// ```swift
    /// .evePaywall(isPresented: $showPaywall)
    /// ```
    func evePaywall(isPresented: Binding<Bool>, onUnlocked: (() -> Void)? = nil) -> some View {
        sheet(isPresented: isPresented) {
            EvePaywallSheet(onUnlocked: onUnlocked)
        }
    }

    /// Shows the paywall automatically whenever this view appears without the
    /// `eve_pro` entitlement, and nothing once the user has it.
    ///
    /// Use this to gate a whole screen. For a single button or row, prefer
    /// checking `SubscriptionService.shared.isPro` and presenting
    /// ``evePaywall(isPresented:onUnlocked:)`` yourself, so the user sees what
    /// they're buying before the sheet arrives.
    ///
    /// If `CustomerInfo` can't be fetched — offline, first launch — RevenueCat
    /// deliberately shows nothing rather than locking a paying user out.
    func eveProGate() -> some View {
        presentPaywallIfNeeded(
            requiredEntitlementIdentifier: SubscriptionService.entitlementID,
            purchaseCompleted: { _ in SubscriptionService.shared.refreshAfterPaywall() },
            restoreCompleted: { _ in SubscriptionService.shared.refreshAfterPaywall() }
        )
    }
}

// MARK: - Customer Center

extension View {
    /// Presents RevenueCat's Customer Center: manage or cancel a subscription,
    /// request a refund, switch plan, restore, and answer the churn survey.
    ///
    /// Worth wiring wherever a subscriber would otherwise be sent to the
    /// Settings app — it handles the whole of "I want to cancel" in-app, and
    /// the retention offers it can show are configured in the dashboard.
    func eveCustomerCenter(isPresented: Binding<Bool>) -> some View {
        presentCustomerCenter(
            isPresented: isPresented,
            restoreCompleted: { _ in SubscriptionService.shared.refreshAfterPaywall() },
            onDismiss: { isPresented.wrappedValue = false }
        )
    }
}
