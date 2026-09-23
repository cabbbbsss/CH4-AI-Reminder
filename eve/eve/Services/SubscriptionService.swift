//
//  SubscriptionService.swift
//  Eve
//
//  Wraps RevenueCat — the one external capability behind EVE Plus. This is the
//  single source of truth for "is this user a subscriber"; nothing else in the
//  app should touch `Purchases` directly. Mirrors PermissionManager's shape:
//  a @MainActor @Observable singleton that Views bind to with @Bindable.
//

import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    // MARK: - Dashboard configuration
    //
    // These three identifiers must match the RevenueCat dashboard exactly.
    // Everything else about pricing — how many tiers, what they cost, which
    // paywall renders — is configured remotely and needs no app release.

    /// The entitlement that unlocks every paid feature.
    ///
    /// Gate on *this*, never on a product or package identifier: products get
    /// replaced whenever pricing changes, and an entitlement survives that.
    static let entitlementID = "eve_pro"

    /// What the tier is called in the app's own UI.
    ///
    /// Deliberately *not* derived from ``entitlementID``: the entitlement stayed
    /// `eve_pro` (renaming one in the dashboard means migrating every subscriber
    /// on it, for an identifier no user ever sees) while the paywall sells
    /// "EVE Plus". This is the only place the app says the name itself — keep it
    /// matching the paywall copy in the dashboard.
    static let displayName = "EVE Plus"

    /// RevenueCat's public SDK key. Public by design — it can only read
    /// offerings and start purchases, so shipping it in the binary is expected
    /// (the secret key, which can mutate subscriber state, never leaves the
    /// dashboard). Swap this for the `appl_…` production key before submitting;
    /// a `test_…` key only reaches RevenueCat's Test Store, not App Store Connect.
    private static let apiKey = "test_UvsrpxjISkvnAtPLeZrXESJDtnx"

    /// Package identifiers configured on the offering, in display order.
    ///
    /// RevenueCat's built-in package types (`$rc_lifetime`, `$rc_annual`,
    /// `$rc_monthly`) are tried first via `Offering.lifetime`/`.annual`/`.monthly`;
    /// these are the custom-identifier fallback for an offering that was set up
    /// with plain names instead.
    private static let packageIdentifierFallbacks = ["lifetime", "yearly", "monthly"]

    // MARK: - Observable state

    /// Latest entitlement snapshot. `nil` until the first fetch resolves —
    /// treat that as "not yet known", not as "not subscribed".
    private(set) var customerInfo: CustomerInfo?

    /// The offering that backs the paywall, or `nil` while loading / on failure.
    private(set) var currentOffering: Offering?

    private(set) var isLoadingOfferings = false
    private(set) var isPurchasing = false

    /// Last user-presentable failure. Views clear it once shown.
    var lastErrorMessage: String?

    private var customerInfoTask: Task<Void, Never>?

    private init() {}

    // MARK: - Entitlement

    /// Whether EVE Plus is unlocked right now.
    ///
    /// Reads the cached `CustomerInfo`, so it is synchronous and safe to call
    /// from a view body. RevenueCat keeps the cache warm across launches, which
    /// means this is correct offline too.
    var isPro: Bool {
        entitlement?.isActive == true
    }

    /// The raw entitlement, for screens that want renewal date or store.
    var entitlement: EntitlementInfo? {
        customerInfo?.entitlements[Self.entitlementID]
    }

    /// When the current subscription lapses. `nil` for lifetime purchases.
    var proExpirationDate: Date? {
        entitlement?.expirationDate
    }

    /// A one-line status for the Settings row.
    var statusDescription: String {
        guard let entitlement, entitlement.isActive else { return "Free" }
        if entitlement.expirationDate == nil { return "Lifetime" }
        if entitlement.willRenew { return "Renews automatically" }
        if let date = entitlement.expirationDate {
            return "Until \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Active"
    }

    // MARK: - Feature limits

    /// How many saved places a free account may keep.
    ///
    /// Expressed as a count rather than a bool so the gate reads the same
    /// everywhere it is checked, and so raising the allowance later is a
    /// one-line change here instead of a hunt through the views.
    static let freeLocationLimit = 1

    /// Whether another saved place may be added, given how many exist now.
    ///
    /// Subscribers are unlimited; a free account stops at
    /// ``freeLocationLimit``, and the caller should show the paywall instead
    /// of the add sheet once this returns `false`.
    func canAddLocation(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeLocationLimit
    }

    // MARK: - Lifecycle

    /// Configures the SDK. Call once, as early as possible — RevenueCat needs to
    /// be configured before any `Purchases.shared` access, including the ones
    /// RevenueCatUI makes when a paywall appears.
    static func configure() {
        guard !Purchases.isConfigured else { return }

        #if DEBUG
        Purchases.logLevel = .info
        #else
        Purchases.logLevel = .error
        #endif

        Purchases.configure(
            with: Configuration.builder(withAPIKey: apiKey)
                // StoreKit 2 end-to-end. Requires an In-App Purchase Key in the
                // RevenueCat dashboard: https://rev.cat/in-app-purchase-key-configuration
                .with(storeKitVersion: .storeKit2)
                // Let StoreKit surface its own billing / price-consent sheets
                // rather than us having to host them.
                .with(showStoreMessagesAutomatically: true)
                .build()
        )
    }

    /// Configures the SDK and begins observing entitlement changes.
    ///
    /// Safe to call repeatedly; the stream is only attached once. Because the
    /// stream also fires for renewals, expirations and purchases made on another
    /// device, `isPro` stays correct without any polling.
    func start() {
        Self.configure()

        guard customerInfoTask == nil else { return }
        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.customerInfo = info
            }
        }

        Task { await refresh() }
    }

    /// Re-reads entitlements and offerings. Worth calling when the app returns
    /// to the foreground, in case a subscription was changed in the App Store.
    func refresh() async {
        await loadOfferings()

        do {
            customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    /// Fire-and-forget refresh for the RevenueCatUI callbacks.
    ///
    /// `customerInfoStream` already delivers the new entitlement on its own;
    /// this just closes the gap for anything reading `isPro` on the very next
    /// frame, and re-reads the offering in case the purchase changed it.
    func refreshAfterPaywall() {
        Task { await refresh() }
    }

    // MARK: - Offerings

    /// Loads the current offering — the set of packages the dashboard says this
    /// user should see. Never hardcode the product list here: which packages are
    /// in the offering, and any A/B experiment over them, is a remote decision.
    func loadOfferings() async {
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }

        do {
            currentOffering = try await Purchases.shared.offerings().current
        } catch {
            currentOffering = nil
            lastErrorMessage = Self.message(for: error)
        }
    }

    /// Lifetime → Yearly → Monthly, skipping any the offering doesn't carry.
    ///
    /// Only needed by a hand-built paywall; the RevenueCat-hosted paywall lays
    /// the offering out itself.
    var orderedPackages: [Package] {
        guard let offering = currentOffering else { return [] }

        let byType = [offering.lifetime, offering.annual, offering.monthly]
        let resolved = zip(byType, Self.packageIdentifierFallbacks).map { typed, identifier in
            typed ?? offering.package(identifier: identifier)
        }

        let ordered = resolved.compactMap { $0 }
        // An offering built entirely out of custom package types matches nothing
        // above — fall back to whatever order the dashboard defined.
        return ordered.isEmpty ? offering.availablePackages : ordered
    }

    // MARK: - Purchasing

    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        case failed(String)
    }

    /// Buys a package and reports what happened.
    ///
    /// A user backing out of the App Store sheet is `.cancelled`, not an error —
    /// showing an alert for it is the most common paywall mistake. Entitlement
    /// state is not set here: the returned `CustomerInfo` flows back through
    /// `customerInfoStream`, so there is exactly one place it is written.
    @discardableResult
    func purchase(_ package: Package) async -> PurchaseOutcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            customerInfo = result.customerInfo
            return isPro ? .purchased : .failed("The purchase went through but \(Self.displayName) didn't unlock. Try Restore Purchases.")
        } catch {
            if (error as? ErrorCode) == .purchaseCancelledError { return .cancelled }
            let message = Self.message(for: error)
            lastErrorMessage = message
            return .failed(message)
        }
    }

    /// Restores purchases made with this Apple ID.
    ///
    /// Required by App Review for any app selling non-consumables or
    /// subscriptions, and the fix for a user who reinstalled or switched device.
    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            customerInfo = try await Purchases.shared.restorePurchases()
            if !isPro {
                lastErrorMessage = "No previous \(Self.displayName) purchase was found for this Apple ID."
            }
            return isPro
        } catch {
            lastErrorMessage = Self.message(for: error)
            return false
        }
    }

    // MARK: - Errors

    /// Turns a RevenueCat failure into something worth showing a user.
    ///
    /// Only the codes with a real user action attached get custom copy;
    /// everything else falls through to the SDK's own localized description,
    /// which is already written for end users.
    private static func message(for error: Error) -> String {
        guard let code = error as? ErrorCode else { return error.localizedDescription }

        switch code {
        case .purchaseCancelledError:
            return "Purchase cancelled."
        case .purchaseNotAllowedError:
            return "This device isn't allowed to make purchases. Check Screen Time restrictions."
        case .paymentPendingError:
            return "Your purchase is pending approval. \(displayName) unlocks as soon as it clears."
        case .productAlreadyPurchasedError:
            return "You already own this. Tap Restore Purchases to unlock it here."
        case .networkError, .offlineConnectionError:
            return "Couldn't reach the App Store. Check your connection and try again."
        case .storeProblemError:
            return "The App Store is having trouble right now. Please try again shortly."
        case .configurationError, .invalidAppUserIdError:
            return "\(displayName) isn't set up correctly. Please contact support."
        default:
            return error.localizedDescription
        }
    }
}
