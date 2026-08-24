//
//  ProViews.swift
//  YomMockCore
//
//  Shared SwiftUI surfaces for YomMock Pro: the RevenueCat paywall, the
//  Customer Center (iPadOS), entitlement status and a manual package list.
//  Purchase/restore logic lives in ProSupport.swift (SubscriptionManager).
//

import RevenueCat
import RevenueCatUI
import SwiftUI

// MARK: - Manage subscription

/// Self-serve subscription management. Customer Center is iOS/iPadOS-only;
/// on macOS we hand off to the App Store subscription page.
struct ManageSubscriptionButton: View {
    @Environment(\.openURL) private var openURL
    #if os(iOS)
        @State private var showCustomerCenter = false
    #endif

    var body: some View {
        Button {
            #if os(iOS)
                showCustomerCenter = true
            #else
                openURL(Self.manageSubscriptionsURL)
            #endif
        } label: {
            Label("Manage Subscription", systemImage: "person.crop.circle")
        }
        #if os(iOS)
            .sheet(isPresented: $showCustomerCenter) {
                CustomerCenterView()
            }
        #endif
    }

    #if os(macOS)
        private static let manageSubscriptionsURL = URL(
            string: "https://apps.apple.com/account/subscriptions")!
    #endif
}

// MARK: - Status

struct ProStatusSection: View {
    let manager: SubscriptionManager

    var body: some View {
        Section("Status") {
            LabeledContent("Plan", value: manager.isPro ? "YomMock Pro" : "Free")
            if let entitlement = manager.activeEntitlement, entitlement.isActive {
                LabeledContent("Product", value: entitlement.productIdentifier)
                if let expiration = entitlement.expirationDate {
                    LabeledContent(
                        entitlement.willRenew ? "Renews" : "Expires",
                        value: expiration.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if let error = manager.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }
}

// MARK: - Manual package list

/// Direct purchase rows for the configured products. The RevenueCat Paywall
/// is the primary purchase surface; this list keeps the store functional and
/// inspectable straight from settings.
private struct PackagePurchaseRow: View {
    let title: String
    let package: Package?
    let purchase: (Package) async -> Void

    var body: some View {
        LabeledContent {
            if let package {
                Button("Buy \(package.storeProduct.localizedPriceString)") {
                    Task { await purchase(package) }
                }
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: "tag")
        }
    }
}

// MARK: - Settings pane

/// Full subscription pane: status, paywall entry, per-product purchase,
/// management and restore. Hosted by the macOS Settings scene / Pro window
/// and by the iPad pro sheet.
struct SubscriptionSettingsView: View {
    @State private var manager = SubscriptionManager.shared
    @State private var isPurchasing = false
    @State private var outcomeMessage: String?

    var body: some View {
        Form {
            ProStatusSection(manager: manager)

            if !manager.isPro {
                Section("Products") {
                    PackagePurchaseRow(
                        title: "Monthly", package: manager.monthlyPackage, purchase: run)
                    PackagePurchaseRow(
                        title: "Yearly", package: manager.yearlyPackage, purchase: run)
                    PackagePurchaseRow(
                        title: "Lifetime", package: manager.lifetimePackage, purchase: run)
                }
            }

            Section {
                ManageSubscriptionButton()
                Button {
                    Task { await runRestore() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
                .disabled(isPurchasing)
            }
        }
        .formStyle(.grouped)
        .overlay {
            if manager.isLoading && manager.offering == nil {
                ProgressView("Loading products…")
            }
        }
        .task { await manager.refresh() }
        .alert("YomMock Pro", isPresented: outcomeMessageBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(outcomeMessage ?? "")
        }
    }

    private var outcomeMessageBinding: Binding<Bool> {
        Binding(
            get: { outcomeMessage != nil },
            set: { if !$0 { outcomeMessage = nil } }
        )
    }

    private func run(_ package: Package) async {
        isPurchasing = true
        defer { isPurchasing = false }
        handle(await manager.purchase(package))
    }

    private func runRestore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        handle(await manager.restore())
    }

    private func handle(_ outcome: PurchaseOutcome) {
        switch outcome {
        case .unlocked:
            outcomeMessage = "YomMock Pro is now active. Enjoy!"
        case .cancelled:
            break
        case .failed(let message):
            outcomeMessage = message
        }
    }
}
