//
//  PaywallView.swift
//  SelfLie
//
//  Created by Codex on 2025-??.
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(PaywallController.self) private var paywallController
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedPackageID: String?
    @State private var purchaseMessage: String?
    @State private var isRefreshing = false
    
    private let benefits = [
        "Unlimited Number of Reps",
        "Cloud Sync Across Devices",
        "No Anoying Ads",
        "Widgets and other upcoming features"
    ]
    
    private var packages: [Package] { subscriptionManager.availablePackages }
    private var selectedPackage: Package? {
        guard let id = selectedPackageID else { return nil }
        return subscriptionManager.package(with: id)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundGradient
                .ignoresSafeArea()
            
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        benefitList
                        planSelection
                        termsText
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 56)
                    .padding(.bottom, 100)
                }
            
                
                VStack {
                    Spacer()
                    bottomActionBar
                }
            }
            HStack{
                restoreButton
                Spacer()
                closeButton
            }
            .padding()
        }
        .task { await refreshOfferingsIfNeeded() }
        .onChange(of: subscriptionManager.availablePackages.map { $0.identifier }) { _, newIdentifiers in
            guard !newIdentifiers.isEmpty else {
                selectedPackageID = nil
                return
            }
            if let annual = subscriptionManager.offering?.annual {
                selectedPackageID = annual.identifier
            } else if selectedPackageID == nil || !newIdentifiers.contains(where: { $0 == selectedPackageID }) {
                selectedPackageID = newIdentifiers.first
            }
        }
        .onAppear {
            if selectedPackageID == nil, let annual = subscriptionManager.offering?.annual {
                selectedPackageID = annual.identifier
            } else if selectedPackageID == nil {
                selectedPackageID = subscriptionManager.availablePackages.first?.identifier
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get Premium Access")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(titleColor)
            Text("Create unlimited reps and practice every rep without limits.")
                .font(.body)
                .foregroundStyle(subtitleColor)
        }
    }
    
    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(benefits, id: \.self) { benefit in
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.purple)
                    Text(benefit)
                        .font(.headline)
                        .foregroundStyle(titleColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(benefitBackground)
                )
            }
        }
    }
    
    private var planSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your plan")
                .font(.headline)
                .foregroundStyle(titleColor)
            if packages.isEmpty {
                loadingState
            } else {
                ForEach(packages, id: \.identifier) { package in
                    Button {
                        HapticManager.shared.trigger(.selection)
                        handlePackageSelection(package)
                    } label: {
                        PaywallPlanCard(
                            package: package,
                            isSelected: package.identifier == selectedPackageID,
                            pricePerDayText: pricePerDayText(for: package),
                            isBestValue: package.identifier == subscriptionManager.offering?.annual?.identifier,
                            isOneTime: package.storeProduct.subscriptionPeriod == nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var termsText: some View {
        Text("You may cancel your free trial at any time through your iTunes account settings; otherwise, your subscription will automatically renew. To avoid being charged, cancellation must occur at least 24 hours before the end of the free trial or any subscription period. Subscriptions that include a free trial will automatically convert to a paid subscription upon renewal. Please note that any unused portion of a free trial will be forfeited if you purchase a premium subscription during the trial period. Subscription payments will be billed to your iTunes account upon purchase confirmation and at the start of each renewal term. For more information, please see our Terms of Use and Privacy Policy.")
            .font(.footnote)
            .foregroundColor(.gray)
    }
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            if subscriptionManager.isRefreshing || isRefreshing {
                ProgressView("Loading plans…")
                    .progressViewStyle(.circular)
            } else if let message = subscriptionManager.lastErrorMessage {
                VStack(spacing: 8) {
                    Text("We couldn't load purchase options.")
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(subtitleColor)
                    Button("Retry") {
                        Task { await refreshOfferings(force: true) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(benefitBackground)
        )
    }
    
    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            if let message = purchaseMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(subtitleColor)
                    .multilineTextAlignment(.center)
            }
            Button(action: purchaseSelectedPlan) {
                HStack {
                    if subscriptionManager.isProcessingTransaction {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 8)
                    }else{
                        Text("Continue")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.purple))
                .foregroundStyle(.white)
            }
            .clipShape(.capsule)
            .disabled(selectedPackage == nil || subscriptionManager.isProcessingTransaction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)

    }
    
    private var closeButton: some View {
        Button {
            HapticManager.shared.trigger(.lightImpact)
            paywallController.dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .fontWeight(.regular)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.7) : .secondary)
        }
    }
    
    private var restoreButton: some View {
        Button {
            HapticManager.shared.trigger(.lightImpact)
            restorePurchases()
        } label: {
            Text("Restore")
                .fontDesign(.default)
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.7) : .secondary)
        }
    }
    
    private func purchaseSelectedPlan() {
        guard let package = selectedPackage else { return }
        triggerPurchase(for: package)
    }
    
    private func restorePurchases() {
        purchaseMessage = nil
        Task {
            let outcome = await subscriptionManager.restorePurchases()
            switch outcome {
            case .success:
                HapticManager.shared.trigger(.success)
                paywallController.dismiss()
            case .failure(let error):
                handle(error: error)
            }
        }
    }
    
    private func handle(error: Error) {
        let nsError = error as NSError
        if let code = RevenueCat.ErrorCode(rawValue: nsError.code), code == .purchaseCancelledError {
            return
        }
        purchaseMessage = error.localizedDescription
        HapticManager.shared.trigger(.error)
    }
    
    private func refreshOfferingsIfNeeded() async {
        if packages.isEmpty {
            await refreshOfferings(force: false)
        }
    }
    
    private func refreshOfferings(force: Bool) async {
        isRefreshing = true
        await subscriptionManager.refreshData(force: force)
        isRefreshing = false
    }
    
    private func pricePerDayText(for package: Package) -> String? {
        guard package.identifier == subscriptionManager.offering?.annual?.identifier,
              let perDay = package.storeProduct.pricePerDay else {
            return nil
        }
        let formatter = package.storeProduct.priceFormatter ?? NumberFormatter()
        formatter.numberStyle = .currency
        if let locale = package.storeProduct.priceFormatter?.locale {
            formatter.locale = locale
        }
        guard let formatted = formatter.string(for: perDay) else { return nil }
        return "Less than \(formatted)/day!"
    }
    
    private func handlePackageSelection(_ package: Package) {
        if selectedPackageID != package.identifier {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPackageID = package.identifier
            }
            triggerPurchase(for: package)
        } else {
            triggerPurchase(for: package)
        }
    }
    
    private func triggerPurchase(for package: Package) {
        purchaseMessage = nil
        Task {
            let outcome = await subscriptionManager.purchase(package: package)
            switch outcome {
            case .success:
                HapticManager.shared.trigger(.success)
                paywallController.dismiss()
            case .cancelled:
                break
            case .failure(let error):
                handle(error: error)
            }
        }
    }
    
    private var backgroundGradient: LinearGradient {
        let colors: [Color]
        if colorScheme == .dark {
            colors = [Color.black, Color(white: 0.08)]
        } else {
            colors = [Color(white: 0.95), Color.white]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private var titleColor: Color {
        colorScheme == .dark ? Color.white : Color.primary
    }
    
    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.secondary
    }
    
    private var benefitBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.85)
    }
}

private struct PaywallPlanCard: View {
    let package: Package
    let isSelected: Bool
    let pricePerDayText: String?
    let isBestValue: Bool
    let isOneTime: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var borderColor: Color {
        if isSelected {
            return .purple
        }
        return colorScheme == .dark ? Color.white.opacity(0.2) : Color(UIColor.systemGray4)
    }
    
    private var backgroundColor: Color {
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(.title3.weight(.semibold))
                    Text(package.localizedPriceString)
                        .font(.headline)
                    if let pricePerDayText {
                        Text(pricePerDayText)
                            .font(.caption)
                            .foregroundStyle(.purple)
                    } else if isOneTime {
                        Text("One-time purchase")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(subscriptionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                }
            }
            if isBestValue {
                Text("Best Value")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.purple.opacity(colorScheme == .dark ? 0.24 : 0.15)))
                    .foregroundStyle(.purple)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
    }
    
    private var displayTitle: String {
        if !package.storeProduct.localizedTitle.isEmpty {
            return package.storeProduct.localizedTitle
        }
        switch package.storeProduct.productIdentifier {
        case "reps_499_1m":
            return "Monthly Plan"
        case "reps_4999_1y":
            return "Yearly Plan"
        case "reps_9999_lifetime":
            return "Lifetime Access"
        default:
            if let period = package.storeProduct.subscriptionPeriod {
                return periodTitle(for: period)
            } else {
                return "Premium Access"
            }
        }
    }
    
    private var subscriptionDescription: String {
        guard let period = package.storeProduct.subscriptionPeriod else {
            return ""
        }
        switch period.unit {
        case .month:
            return "Billed monthly"
        case .year:
            return "Billed yearly"
        case .week:
            return "Billed weekly"
        case .day:
            return "Daily billing"
        @unknown default:
            return "Subscription"
        }
    }
    
    private func periodTitle(for period: RevenueCat.SubscriptionPeriod) -> String {
        switch period.unit {
        case .month:
            return "Monthly Plan"
        case .year:
            return "Yearly Plan"
        case .week:
            return "Weekly Plan"
        case .day:
            return "Daily Plan"
        @unknown default:
            return "Premium Access"
        }
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionManager())
        .environment(PaywallController())
}
