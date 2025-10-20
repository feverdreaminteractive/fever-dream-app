import SwiftUI
import StoreKit

struct PremiumMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreManager()
    @State private var showingSubscriptionSheet = false
    @State private var showingIndividualEffectSheet = false
    @State private var selectedEffect: PremiumEffect?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 10) {
                            Text("FΣVΣЯ DЯΣΛM")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white)

                            Text("PREMIUM EFFECTS")
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                        .padding(.top, 20)

                        // Subscription Option
                        VStack(spacing: 20) {
                            VStack(spacing: 15) {
                                HStack {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.yellow)

                                    Text("UNLIMITED ACCESS")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }

                                Text("All premium effects • 1 month free trial")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)

                                VStack(spacing: 5) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("FREE")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.green)
                                        Text("then")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                        Text("$1.99")
                                            .font(.system(size: 28, weight: .black))
                                            .foregroundColor(.green)
                                    }

                                    Text("1 month free, then $1.99/month")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }

                            Button(action: {
                                showingSubscriptionSheet = true
                            }) {
                                Text("START FREE TRIAL")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [.green, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(25)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.yellow.opacity(0.1))
                                )
                        )
                        .padding(.horizontal)

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)

                            Text("OR")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 15)

                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.horizontal)

                        // Individual Effects Section
                        VStack(spacing: 20) {
                            Text("BUY INDIVIDUAL EFFECTS")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 15) {
                                ForEach(PremiumEffect.allCases, id: \.self) { effect in
                                    PremiumEffectCard(
                                        effect: effect,
                                        isOwned: storeManager.ownedEffects.contains(effect.id),
                                        onTap: {
                                            if !storeManager.ownedEffects.contains(effect.id) {
                                                // All effects require subscription now
                                                showingSubscriptionSheet = true
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Trial information
                        VStack(spacing: 10) {
                            Text("🎉 FREE for 30 days!")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.green)

                            Text("Cancel anytime. No commitment.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.vertical, 15)

                        // Restore Purchases
                        Button("Restore Purchases") {
                            storeManager.restorePurchases()
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingSubscriptionSheet) {
            SubscriptionPurchaseSheet(storeManager: storeManager)
        }
        .sheet(isPresented: $showingIndividualEffectSheet) {
            if let effect = selectedEffect {
                IndividualEffectPurchaseSheet(
                    effect: effect,
                    storeManager: storeManager
                )
            }
        }
        .onAppear {
            storeManager.loadProducts()
        }
    }
}

struct PremiumEffectCard: View {
    let effect: PremiumEffect
    let isOwned: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Effect Preview/Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            LinearGradient(
                                colors: effect.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 100)

                    if isOwned {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                            Text("OWNED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: effect.iconName)
                                .font(.system(size: 30))
                                .foregroundColor(.white)

                            Text("SUBSCRIPTION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                    }
                }

                VStack(spacing: 4) {
                    Text(effect.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    Text(effect.description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .disabled(isOwned)
        .opacity(isOwned ? 0.7 : 1.0)
    }
}

// MARK: - Premium Effects Enum

enum PremiumEffect: String, CaseIterable, Identifiable {
    case crtDitherGlitch = "crt_dither_glitch_effect"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .crtDitherGlitch: return "HYPNOTIST"
        }
    }

    var description: String {
        switch self {
        case .crtDitherGlitch: return "Hypnotic waves, fast strobing colors, and audio-reactive image shake"
        }
    }

    // Individual pricing removed - all effects included in subscription
    var price: String {
        return "SUBSCRIPTION"
    }

    var iconName: String {
        switch self {
        case .crtDitherGlitch: return "video.and.waveform.fill"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .crtDitherGlitch: return [.red, .black, .gray]
        }
    }
}

#Preview {
    PremiumMenuView()
}