//
//  ProSupport.swift
//  YomMockCore
//
//  RevenueCat integration: SDK configuration, entitlement state, offerings
//  and purchase/restore flows. Shared by the macOS and iPadOS apps.
//

import Foundation
import RevenueCat

/// Identifiers mirrored by the RevenueCat project configuration.
enum ProConstants {
    #if DEBUG
        /// Debug builds use the Test Store key — purchases are simulated,
        /// no App Store Connect or sandbox account needed.
        static let apiKey = "test_AtWicvLnZsCwNvgutrzHtxQhfpb"
    #else
        // TODO: paste the production public SDK key (appl_...) from
        // RevenueCat Dashboard -> Apps -> YomMock -> API keys.
        /// Release builds (TestFlight/App Store) must use the production
        /// key — Test Store keys are rejected by the SDK in release.
        static let apiKey = "appl_xXQkdkijNjaoMDRWDnQeEJiMBrg"
    #endif
    static let entitlementID = "yommock_pro"

    static let monthlyProductID = "subscription_monthly_1"
    static let yearlyProductID = "subscription_yearly_1"
    static let lifetimeProductID = "subscription_lifetime_1"
}

enum PurchaseOutcome: Equatable {
    /// Purchase/restore finished and `yommock_pro` is active.
    case unlocked
    case cancelled
    case failed(String)
}

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    private(set) var customerInfo: CustomerInfo?
    private(set) var offering: Offering?
    private(set) var isLoading = false
    var lastErrorMessage: String?

    private var observationTask: Task<Void, Never>?

    var isPro: Bool {
        customerInfo?.entitlements[ProConstants.entitlementID]?.isActive == true
    }

    var activeEntitlement: EntitlementInfo? {
        customerInfo?.entitlements[ProConstants.entitlementID]
    }

    var monthlyPackage: Package? { package(forProductID: ProConstants.monthlyProductID) }
    var yearlyPackage: Package? { package(forProductID: ProConstants.yearlyProductID) }
    var lifetimePackage: Package? { package(forProductID: ProConstants.lifetimeProductID) }

    /// Call once at launch, before any view touches `Purchases.shared`.
    static func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
            Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: ProConstants.apiKey)
    }

    /// Starts live entitlement tracking and loads the current offering.
    /// Idempotent — call after `configure()`.
    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.customerInfo = info
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            customerInfo = try await Purchases.shared.customerInfo()
            offering = try await Purchases.shared.offerings().current
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func purchase(_ package: Package) async -> PurchaseOutcome {
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            customerInfo = result.customerInfo
            return isPro
                ? .unlocked
                : .failed("Purchase completed but \(ProConstants.entitlementID) is not active.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> PurchaseOutcome {
        do {
            customerInfo = try await Purchases.shared.restorePurchases()
            return isPro
                ? .unlocked
                : .failed(
                    "No purchase with an active \(ProConstants.entitlementID) entitlement was found."
                )
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func package(forProductID id: String) -> Package? {
        offering?.availablePackages.first { $0.storeProduct.productIdentifier == id }
    }
}
