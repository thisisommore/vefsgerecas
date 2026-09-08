//
//  ProViews.swift
//  YomMockCore
//
//  Shared SwiftUI surfaces for YomMock Pro: entitlement status and the
//  local purchase/restore UI. Purchase logic lives in
//  ProSupport.swift (SubscriptionManager).
//

import RevenueCat
import SwiftUI

// MARK: - Legal links

/// Terms of Use and Privacy Policy, required next to every subscription
/// purchase control by App Review Guideline 3.1.2.
enum ProLegal {
    /// Apple's standard EULA. Replace with your custom EULA URL if you ever
    /// add one in App Store Connect.
    static let termsURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://yommock.yomlabs.xyz/privacy")!
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

/// Direct purchase rows for the configured products — the app's only
/// purchase surface, fully local SwiftUI with no remote configuration.
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

// MARK: - Sheet wrapper

/// `SubscriptionSettingsView` with an explicit Cancel footer for sheet
/// presentations. macOS sheets don't dismiss on outside clicks, so every
/// sheet needs its own way out.
struct ProUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SubscriptionSettingsView()
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Settings pane

/// Full subscription pane: status, per-product purchase and restore. Hosted
/// by the macOS Settings scene / Pro window and by the iPad pro sheet.
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
                Button {
                    Task { await runRestore() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
                .disabled(isPurchasing)
            }

            Section {
                Link("Terms of Use (EULA)", destination: ProLegal.termsURL)
                Link("Privacy Policy", destination: ProLegal.privacyURL)
            } footer: {
                Text(
                    "Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. Payment is charged to your Apple ID account. Manage or cancel anytime in your App Store account settings."
                )
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
