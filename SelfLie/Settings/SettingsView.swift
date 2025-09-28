import SwiftUI
import RevenueCat
import UIKit

struct SettingsView: View {
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(PaywallController.self) private var paywallController
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false

    @State private var didCopyUserID = false

    private let supportEmail = "support@myreps.app"
    private let termsURL = URL(string: "https://myreps.app/terms")!
    private let privacyURL = URL(string: "https://myreps.app/privacy")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                subscriptionSection
                accountSection
                supportSection
                legalSection
                privacySection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var subscriptionSection: some View {
        SettingsCard(title: "Subscription") {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: subscriptionIconName)
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 6) {
                    Text(subscriptionPlan.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let detail = subscriptionDetailText {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if subscriptionPlan == .free {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if subscriptionPlan == .free {
                    HapticManager.shared.trigger(.lightImpact)
                    paywallController.present(context: .general)
                }
            }
        }
    }

    private var accountSection: some View {
        SettingsCard(title: "Account") {
            VStack(alignment: .leading, spacing: 12) {
                Text("User ID")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Text(appUserID)
                        .font(.callout.monospaced())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Button {
                        copyAppUserID()
                    } label: {
                        Label("Copy", systemImage: didCopyUserID ? "checkmark.circle.fill" : "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .foregroundColor(.purple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy user ID")
                }

                if didCopyUserID {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
        }
    }

    private var supportSection: some View {
        SettingsCard(title: "Support") {
            Button {
                HapticManager.shared.trigger(.lightImpact)
                contactSupport()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Contact Us")
                            .font(.headline)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var legalSection: some View {
        SettingsCard(title: "Legal") {
            VStack(spacing: 0) {
                Button {
                    HapticManager.shared.trigger(.selection)
                    openURL(termsURL)
                } label: {
                    settingsRowLabel(title: "Terms of Service")
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.secondary.opacity(colorScheme == .dark ? 0.3 : 0.1))
                    .padding(.vertical, 8)

                Button {
                    HapticManager.shared.trigger(.selection)
                    openURL(privacyURL)
                } label: {
                    settingsRowLabel(title: "Privacy Policy")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var privacySection: some View {
        SettingsCard(title: nil) {
            Toggle(isOn: $privacyModeEnabled) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy Mode")
                        .font(.headline)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .purple))
        }
    }

    private var subscriptionDetailText: String? {
        switch subscriptionPlan {
        case .free:
            return "Unlock unlimited reps with Premium"
        case .monthly:
            return renewalText(prefix: "Renews", expiration: currentEntitlement?.expirationDate)
        case .yearly:
            return renewalText(prefix: "Renews", expiration: currentEntitlement?.expirationDate)
        case .lifetime:
            return "Lifetime access"
        }
    }

    private func renewalText(prefix: String, expiration: Date?) -> String {
        guard let expiration else {
            return "Active subscription"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(prefix) on \(formatter.string(from: expiration))"
    }

    private var subscriptionIconName: String {
        switch subscriptionPlan {
        case .free:
            return "sparkles"
        case .monthly:
            return "calendar"
        case .yearly:
            return "calendar.badge.clock"
        case .lifetime:
            return "infinity"
        }
    }

    private var currentEntitlement: EntitlementInfo? {
        subscriptionManager.customerInfo?.entitlements.all[SubscriptionManager.entitlementID]
    }

    private var subscriptionPlan: SubscriptionPlan {
        guard let entitlement = currentEntitlement, entitlement.isActive else {
            return .free
        }
        let productID = entitlement.productIdentifier.lowercased()
        if productID.contains("lifetime") || entitlement.expirationDate == nil {
            return .lifetime
        }
        if productID.contains("1y") || productID.contains("year") || productID.contains("annual") {
            return .yearly
        }
        return .monthly
    }

    private var appUserID: String {
        if let original = subscriptionManager.customerInfo?.originalAppUserId, !original.isEmpty {
            return original
        }
        return Purchases.shared.appUserID
    }

    private func copyAppUserID() {
        UIPasteboard.general.string = appUserID
        HapticManager.shared.trigger(.success)
        withAnimation {
            didCopyUserID = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                didCopyUserID = false
            }
        }
    }

    private func contactSupport() {
        let subject = "Reps Support"
        let body = """
        Hi Reps Support Team,

        I need help with...

        ---
        RevenueCat User ID: \(appUserID)
        App Version: \(appVersion)
        Device: \(UIDevice.current.friendlyModelName)
        OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Locale: \(Locale.current.identifier)
        Preferred Language: \(Locale.preferredLanguages.first ?? "Unknown")
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        if let url = components.url {
            openURL(url)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    @ViewBuilder
    private func settingsRowLabel(title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private enum SubscriptionPlan: Equatable {
    case free
    case monthly
    case yearly
    case lifetime

    var title: String {
        switch self {
        case .free:
            return "Free Plan"
        case .monthly:
            return "Monthly Plan"
        case .yearly:
            return "Yearly Plan"
        case .lifetime:
            return "Lifetime Plan"
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .cornerRadius(20)
        .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.25) : Color.black.opacity(0.05)
    }
}

private extension UIDevice {
    var friendlyModelName: String {
        #if targetEnvironment(simulator)
        return "Simulator (\(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Unknown"))"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer -> String in
            let int8Pointer = UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            return String(cString: int8Pointer)
        }
        return identifier
        #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SubscriptionManager())
            .environment(PaywallController())
    }
}
