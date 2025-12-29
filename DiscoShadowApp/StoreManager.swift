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
        "feverdream.premium.monthly"
        // Note: Individual effects no longer sold separately - subscription only
    ])

    var hasSubscription: Bool {
        return purchasedProducts.contains("feverdream.premium.monthly")
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

        // Configure for Xcode 16 StoreKit testing
        #if DEBUG
        print("🏪 StoreManager: Running in Xcode 16 DEBUG mode")
        print("🏪 StoreManager: 🆕 Xcode 16 StoreKit Testing:")
        print("🏪 StoreManager: 1. In Xcode 16, StoreKit testing is more seamless")
        print("🏪 StoreManager: 2. Should automatically use Face ID when available")
        print("🏪 StoreManager: 3. Check Product → Scheme → Edit Scheme → StoreKit Configuration")
        print("🏪 StoreManager: 4. For production-like testing, disable Configuration.storekit")
        #endif

        loadPurchasedProducts()
        startTransactionObserver()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    func loadProducts() {
        print("🏪 StoreManager: Starting to load products...")
        print("🏪 StoreManager: Product identifiers: \(productIdentifiers)")

        // Check AppStore availability
        print("🏪 StoreManager: Checking AppStore availability...")
        Task {
            do {
                let canMakePayments = await AppStore.canMakePayments
                print("🏪 StoreManager: Can make payments: \(canMakePayments)")
            } catch {
                print("🏪 StoreManager: Error checking payment capability: \(error)")
            }
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            print("🏪 StoreManager: Task started...")
            do {
                print("🏪 StoreManager: Calling Product.products...")
                let storeProducts = try await Product.products(for: productIdentifiers)
                print("🏪 StoreManager: Product.products returned")
                print("🏪 StoreManager: Loaded \(storeProducts.count) products")
                for product in storeProducts {
                    print("🏪 StoreManager: Product - ID: \(product.id), Name: \(product.displayName), Price: \(product.displayPrice)")
                    if let subscription = product.subscription {
                        print("🏪 StoreManager: Subscription details - Period: \(subscription.subscriptionPeriod)")
                        if let introOffer = subscription.introductoryOffer {
                            print("🏪 StoreManager: Intro offer - Type: \(introOffer.type), Period: \(introOffer.period), Price: \(introOffer.displayPrice)")
                        } else {
                            print("🏪 StoreManager: No introductory offer found")
                        }
                    }
                }
                self.products = storeProducts.sorted { $0.displayPrice < $1.displayPrice }
                self.isLoading = false
                print("🏪 StoreManager: Products loading complete")
            } catch {
                print("🏪 StoreManager: ERROR loading products: \(error)")
                print("🏪 StoreManager: Error type: \(type(of: error))")
                self.errorMessage = "Failed to load products: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func purchase(_ product: Product) async throws {
        print("💳 StoreManager: [Xcode 16] Starting FRICTIONLESS purchase for product: \(product.id)")
        print("💳 StoreManager: Product type: \(product.type)")
        print("💳 StoreManager: Product has introductory offer: \(product.subscription?.introductoryOffer != nil)")

        // Xcode 16 StoreKit 2 improvements - better Face ID integration
        guard await MainActor.run(body: { true }) else {
            throw StoreError.failedVerification
        }

        print("💳 StoreManager: [Xcode 16] Initiating purchase with enhanced authentication...")

        // Xcode 16's StoreKit should automatically handle Face ID for subscription trials
        let result = try await product.purchase()
        print("💳 StoreManager: [Xcode 16] Purchase result: \(result)")

        switch result {
        case .success(let verification):
            print("💳 StoreManager: ✅ Purchase successful, verifying transaction...")
            let transaction = try checkVerified(verification)
            print("💳 StoreManager: ✅ Transaction verified: \(transaction.productID)")
            print("💳 StoreManager: Transaction original ID: \(transaction.originalID)")
            await transaction.finish()
            await updatePurchasedProducts()
            print("💳 StoreManager: ✅ Purchase completed and verified")
            print("💳 StoreManager: Current purchased products: \(purchasedProducts)")
            print("💳 StoreManager: Has active subscription: \(hasSubscription)")

        case .userCancelled:
            print("💳 StoreManager: ❌ Purchase cancelled by user")
            break

        case .pending:
            print("💳 StoreManager: ⏳ Purchase pending - may require family approval")
            break

        @unknown default:
            print("💳 StoreManager: ❓ Unknown purchase result - this shouldn't happen in Xcode 16")
            break
        }
    }

    // Frictionless subscription purchase - automatically starts trial with Face ID
    @MainActor
    func purchaseSubscriptionFrictionless() async throws {
        print("🔥 StoreManager: Starting frictionless subscription purchase")
        print("🔥 StoreManager: Available products: \(products.map { $0.id })")

        guard let subscriptionProduct = subscriptionProduct() else {
            print("🔥 StoreManager: ERROR - No subscription product found!")
            print("🔥 StoreManager: Product count: \(products.count)")
            print("🔥 StoreManager: Looking for ID: feverdream.premium.monthly")
            throw StoreError.failedVerification
        }

        print("🔥 StoreManager: Found subscription product: \(subscriptionProduct.id)")
        // Trigger immediate purchase with Face ID/Touch ID authentication
        try await purchase(subscriptionProduct)
    }

    func restorePurchases() {
        Task {
            try? await AppStore.sync()
            await updatePurchasedProducts()
        }
    }

    func clearSubscriptionCache() {
        print("🧹 StoreManager: Clearing subscription cache...")
        purchasedProducts.removeAll()
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
        print("🔄 StoreManager: Updating purchased products...")
        var foundTransactions = 0
        var tempPurchasedProducts: Set<String> = []

        for await result in Transaction.currentEntitlements {
            foundTransactions += 1
            do {
                let transaction = try checkVerified(result)
                print("🔄 StoreManager: Found transaction - Product: \(transaction.productID), Type: \(transaction.productType)")
                print("🔄 StoreManager: Transaction details - Revoked: \(transaction.revocationDate != nil), Original ID: \(transaction.originalID)")

                // For subscriptions, also check expiration status
                if transaction.productType == .autoRenewable {
                    print("🔄 StoreManager: Subscription transaction ID: \(transaction.id)")
                    if let expirationDate = transaction.expirationDate {
                        let isExpired = expirationDate < Date()
                        print("🔄 StoreManager: Subscription expires: \(expirationDate), Expired: \(isExpired)")

                        // Only add if not revoked AND not expired
                        if transaction.revocationDate == nil && !isExpired {
                            tempPurchasedProducts.insert(transaction.productID)
                            print("🔄 StoreManager: ✅ Added active subscription: \(transaction.productID)")
                        } else {
                            print("🔄 StoreManager: ❌ Subscription not active: \(transaction.productID) (revoked: \(transaction.revocationDate != nil), expired: \(isExpired))")
                        }
                    } else {
                        // No expiration date, check revocation only
                        if transaction.revocationDate == nil {
                            tempPurchasedProducts.insert(transaction.productID)
                            print("🔄 StoreManager: ✅ Added subscription (no expiration): \(transaction.productID)")
                        } else {
                            print("🔄 StoreManager: ❌ Revoked subscription: \(transaction.productID)")
                        }
                    }
                } else if transaction.productType == .nonConsumable {
                    if transaction.revocationDate == nil {
                        tempPurchasedProducts.insert(transaction.productID)
                        print("🔄 StoreManager: ✅ Added non-consumable: \(transaction.productID)")
                    } else {
                        print("🔄 StoreManager: ❌ Revoked non-consumable: \(transaction.productID)")
                    }
                } else {
                    print("🔄 StoreManager: Skipping transaction type: \(transaction.productType)")
                }
            } catch {
                print("🔄 StoreManager: Failed to verify transaction: \(error)")
            }
        }

        // Update the published property on main thread
        await MainActor.run {
            self.purchasedProducts = tempPurchasedProducts
        }

        print("🔄 StoreManager: Update complete. Found \(foundTransactions) transactions. Active products: \(purchasedProducts)")
    }

    func productForEffect(_ effect: PremiumEffect) -> Product? {
        return products.first { $0.id == effect.id }
    }

    func subscriptionProduct() -> Product? {
        return products.first { $0.id == "feverdream.premium.monthly" }
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