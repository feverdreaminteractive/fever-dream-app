import Foundation
import StoreKit
import SwiftUI

@MainActor
class StoreManager: NSObject, ObservableObject {
    @Published var products: [Product] = []
    @Published var purchasedProducts: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let productIdentifiers = Set([
        "fever_dream_subscription_monthly"
        // Note: Individual effects no longer sold separately - subscription only
    ])

    var hasSubscription: Bool {
        return purchasedProducts.contains("fever_dream_subscription_monthly")
    }

    var ownedEffects: Set<String> {
        if hasSubscription {
            // Subscription gives access to all effects
            return Set(PremiumEffect.allCases.map { $0.id })
        }
        return purchasedProducts
    }

    override init() {
        super.init()
        SKPaymentQueue.default().add(self)
        loadPurchasedProducts()
        startTransactionObserver()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    func loadProducts() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let storeProducts = try await Product.products(for: productIdentifiers)
                self.products = storeProducts.sorted { $0.displayPrice < $1.displayPrice }
                self.isLoading = false
            } catch {
                self.errorMessage = "Failed to load products: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updatePurchasedProducts()

        case .userCancelled:
            break

        case .pending:
            break

        @unknown default:
            break
        }
    }

    func restorePurchases() {
        Task {
            try? await AppStore.sync()
            await updatePurchasedProducts()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func loadPurchasedProducts() {
        Task {
            await updatePurchasedProducts()
        }
    }

    private func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                switch transaction.productType {
                case .autoRenewable:
                    if transaction.revocationDate == nil {
                        purchasedProducts.insert(transaction.productID)
                    } else {
                        purchasedProducts.remove(transaction.productID)
                    }

                case .nonConsumable:
                    if transaction.revocationDate == nil {
                        purchasedProducts.insert(transaction.productID)
                    } else {
                        purchasedProducts.remove(transaction.productID)
                    }

                default:
                    break
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
    }

    func productForEffect(_ effect: PremiumEffect) -> Product? {
        return products.first { $0.id == effect.id }
    }

    func subscriptionProduct() -> Product? {
        return products.first { $0.id == "fever_dream_subscription_monthly" }
    }

    func canUseEffect(_ effect: PremiumEffect) -> Bool {
        return hasSubscription || ownedEffects.contains(effect.id)
    }

    // Monitor subscription status changes
    func startTransactionObserver() {
        Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await updatePurchasedProducts()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
}

extension StoreManager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        // Handle legacy StoreKit transactions if needed
    }
}

enum StoreError: Error {
    case failedVerification
}

// MARK: - Purchase Sheets

struct SubscriptionPurchaseSheet: View {
    let storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 15) {
                        Text("FΣVΣЯ DЯΣΛМ")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.5), radius: 10, x: 0, y: 0)

                        Text("PREMIUM EFFECTS")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Unlock all premium effects with free trial")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    // Features list
                    VStack(spacing: 15) {
                        FeatureRow(icon: "wand.and.rays", title: "All Premium Effects")
                        FeatureRow(icon: "arrow.clockwise", title: "Future Effect Releases")
                        FeatureRow(icon: "calendar", title: "1 Month Free Trial")
                        FeatureRow(icon: "xmark.circle", title: "Cancel Anytime")
                    }

                    Spacer()

                    // Purchase button
                    if let product = storeManager.subscriptionProduct() {
                        VStack(spacing: 15) {
                            VStack(spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("FREE")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 1.0))
                                    Text("then")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("\(product.displayPrice)")
                                        .font(.system(size: 28, weight: .black))
                                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 1.0))
                                }

                                Text("1 month free, then \(product.displayPrice)/month")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Button(action: {
                                Task {
                                    isPurchasing = true
                                    try? await storeManager.purchase(product)
                                    isPurchasing = false
                                    dismiss()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if isPurchasing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    } else {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                    Text("START FREE TRIAL")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.0, green: 1.0, blue: 1.0), Color(red: 1.0, green: 0.0, blue: 1.0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                                .shadow(color: Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isPurchasing)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct IndividualEffectPurchaseSheet: View {
    let effect: PremiumEffect
    let storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 30) {
                    // Effect preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: effect.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 200)

                        VStack(spacing: 15) {
                            Image(systemName: effect.iconName)
                                .font(.system(size: 60))
                                .foregroundColor(.white)

                            Text(effect.name)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }

                    Text(effect.description)
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Spacer()

                    // Purchase button
                    if let product = storeManager.productForEffect(effect) {
                        VStack(spacing: 15) {
                            Text(product.displayPrice)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.green)

                            Button(action: {
                                Task {
                                    isPurchasing = true
                                    try? await storeManager.purchase(product)
                                    isPurchasing = false
                                    dismiss()
                                }
                            }) {
                                HStack {
                                    if isPurchasing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    }
                                    Text("Purchase Effect")
                                        .font(.system(size: 18, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(25)
                            }
                            .disabled(isPurchasing)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(red: 0.0, green: 1.0, blue: 1.0))
                .frame(width: 30)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Spacer()
        }
    }
}