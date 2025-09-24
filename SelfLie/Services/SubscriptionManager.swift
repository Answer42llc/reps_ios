//
//  SubscriptionManager.swift
//  SelfLie
//
//  Created by Codex on 2025-??.
//

import Foundation
import CoreData
import RevenueCat
import Observation

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()
    static let entitlementID = "premium"
    private static let freeAffirmationLimit = 3
    
    // MARK: - Published State
    private(set) var customerInfo: CustomerInfo?
    private(set) var offering: Offering?
    private(set) var availablePackages: [Package] = []
    private(set) var isRefreshing = false
    private(set) var isProcessingTransaction = false
    private(set) var lastErrorMessage: String?
    
    // MARK: - Internal
    @ObservationIgnored
    private var customerInfoTask: Task<Void, Never>?
    
    init() {
        startListeningForCustomerInfoUpdates()
        Task { await refreshData() }
    }
    
    deinit {
        customerInfoTask?.cancel()
    }
    
    // MARK: - Derived State
    var hasPremiumAccess: Bool {
        customerInfo?.entitlements.all[Self.entitlementID]?.isActive == true
    }
    
    var canUsePremiumFeatures: Bool {
        hasPremiumAccess
    }
    
    // MARK: - Public API
    func refreshData(force: Bool = false) async {
        guard !isRefreshing || force else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastErrorMessage = nil
        do {
            async let infoTask = Purchases.shared.customerInfo()
            async let offeringsTask = Purchases.shared.offerings()
            let (info, offerings) = try await (infoTask, offeringsTask)
            updateCustomerInfo(info)
            updateOffering(offerings.current)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    func purchase(package: Package) async -> PurchaseOutcome {
        guard !isProcessingTransaction else {
            return .failure(PurchaseError.transactionInFlight)
        }
        isProcessingTransaction = true
        lastErrorMessage = nil
        defer { isProcessingTransaction = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            updateCustomerInfo(result.customerInfo)
            return result.userCancelled ? .cancelled : .success(result.customerInfo)
        } catch {
            lastErrorMessage = error.localizedDescription
            return .failure(error)
        }
    }
    
    func restorePurchases() async -> RestoreOutcome {
        guard !isProcessingTransaction else {
            return .failure(PurchaseError.transactionInFlight)
        }
        isProcessingTransaction = true
        lastErrorMessage = nil
        defer { isProcessingTransaction = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateCustomerInfo(info)
            return .success(info)
        } catch {
            lastErrorMessage = error.localizedDescription
            return .failure(error)
        }
    }
    
    func canCreateAffirmation(totalCount: Int) -> Bool {
        hasPremiumAccess || totalCount < Self.freeAffirmationLimit
    }
    
    func isAffirmationWithinFreeQuota(_ affirmation: Affirmation) -> Bool {
        guard !hasPremiumAccess else { return true }
        let context = affirmation.managedObjectContext ?? PersistenceController.shared.container.viewContext
        var isWithinQuota = false
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "Affirmation")
            request.sortDescriptors = [NSSortDescriptor(key: "dateCreated", ascending: false)]
            request.fetchLimit = Self.freeAffirmationLimit
            request.resultType = .managedObjectIDResultType
            if let ids = try? context.fetch(request) {
                isWithinQuota = ids.contains(affirmation.objectID)
            }
        }
        return isWithinQuota
    }
    
    func package(with identifier: String) -> Package? {
        availablePackages.first { $0.identifier == identifier }
    }
    
    // MARK: - Helpers
    private func startListeningForCustomerInfoUpdates() {
        customerInfoTask = Task { [weak self] in
            guard let self else { return }
            for await info in Purchases.shared.customerInfoStream {
                self.updateCustomerInfo(info)
            }
        }
    }
    
    private func updateCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
    }
    
    private func updateOffering(_ offering: Offering?) {
        self.offering = offering
        availablePackages = Self.orderedPackages(from: offering)
    }
    
    private static func orderedPackages(from offering: Offering?) -> [Package] {
        guard let offering else { return [] }
        var ordered: [Package] = []
        if let monthly = offering.monthly { ordered.append(monthly) }
        if let annual = offering.annual { ordered.append(annual) }
        if let lifetime = offering.lifetime { ordered.append(lifetime) }
        let remaining = offering.availablePackages.filter { pkg in
            !ordered.contains(where: { $0.identifier == pkg.identifier })
        }
        ordered.append(contentsOf: remaining)
        return ordered
    }
}

// MARK: - Purchase Outcome
extension SubscriptionManager {
    enum PurchaseOutcome {
        case success(CustomerInfo)
        case cancelled
        case failure(Error)
    }
    
    enum RestoreOutcome {
        case success(CustomerInfo)
        case failure(Error)
    }
    
    enum PurchaseError: LocalizedError {
        case transactionInFlight
        
        var errorDescription: String? {
            switch self {
            case .transactionInFlight:
                return "Another purchase is currently processing."
            }
        }
    }
}
