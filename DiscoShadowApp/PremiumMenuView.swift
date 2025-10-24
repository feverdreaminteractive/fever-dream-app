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
                        VStack(spacing: 15) {
                            Text("FΣVΣЯ DЯΣΛM")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .purple.opacity(0.5), radius: 10, x: 0, y: 0)

                            VStack(spacing: 5) {
                                Text("PREMIUM EFFECTS")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text("Unlock advanced visual effects")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
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

                                Text("All 4 premium effects included • 1 month free trial")
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
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("START FREE TRIAL")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [.green, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                                .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .scaleEffect(1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showingSubscriptionSheet)
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

                        // Premium Effects Preview Section
                        VStack(spacing: 20) {
                            Text("INCLUDED PREMIUM EFFECTS")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 16) {
                                ForEach(PremiumEffect.allCases, id: \.self) { effect in
                                    PremiumEffectCard(
                                        effect: effect,
                                        isOwned: storeManager.ownedEffects.contains(effect.id),
                                        onTap: {
                                            // All effects included in subscription - no individual purchases
                                            if !storeManager.hasSubscription {
                                                showingSubscriptionSheet = true
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // Trial information
                        VStack(spacing: 10) {
                            Text("🎉 FREE for 30 days!")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.green)

                            VStack(spacing: 4) {
                                Text("✨ Unlimited access to all premium effects")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))

                                Text("Cancel anytime. No commitment.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                            }
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
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: effect.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 110)
                        .shadow(color: effect.gradientColors.first?.opacity(0.3) ?? .clear, radius: 8, x: 0, y: 4)

                    if isOwned {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            Text("OWNED")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: effect.iconName)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                Text("PREMIUM")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.yellow)
                            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                        }
                    }
                }

                VStack(spacing: 6) {
                    Text(effect.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(effect.description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(.bottom, 8)
        }
        .disabled(isOwned)
        .opacity(isOwned ? 0.8 : 1.0)
        .scaleEffect(isOwned ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isOwned)
    }
}

// MARK: - Premium Effects Enum

enum PremiumEffect: String, CaseIterable, Identifiable {
    case crtDitherGlitch = "crt_dither_glitch_effect"
    case badTV = "bad_tv_effect"
    case strobe = "strobe_effect"
    case convergence = "convergence_effect"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .crtDitherGlitch: return "HYPNOTIST"
        case .badTV: return "BAD TV"
        case .strobe: return "STROBE"
        case .convergence: return "CONVERGENCE"
        }
    }

    var description: String {
        switch self {
        case .crtDitherGlitch: return "Hypnotic waves, fast strobing colors, and audio-reactive image shake"
        case .badTV: return "Infinite feedback loops with vintage TV static, creating hypnotic recursive visuals"
        case .strobe: return "Audio-reactive RGB color channel strobing with independent frequency control"
        case .convergence: return "RGB channel separation with random displacement creating chromatic aberration glitch effects"
        }
    }

    // Individual pricing removed - all effects included in subscription
    var price: String {
        return "SUBSCRIPTION"
    }

    var iconName: String {
        switch self {
        case .crtDitherGlitch: return "video.and.waveform.fill"
        case .badTV: return "tv.fill"
        case .strobe: return "flashlight.on.fill"
        case .convergence: return "camera.filters"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .crtDitherGlitch: return [.red, .black, .gray]
        case .badTV: return [.white, .gray, .black, .blue]
        case .strobe: return [.red, .green, .blue, .white]
        case .convergence: return [.cyan, .pink, .yellow, .black]
        }
    }
}

#Preview {
    PremiumMenuView()
}