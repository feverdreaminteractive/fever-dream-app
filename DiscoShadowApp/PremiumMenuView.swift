import SwiftUI
import StoreKit

struct PremiumMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeManager: StoreManager
    @State private var isPurchasing = false
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

                                VStack(spacing: 8) {
                                    Text("All 4 premium effects included • 1 month free trial")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)

                                    Text("🎛️ NEW: Crossfader feature coming soon")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 1.0))
                                        .multilineTextAlignment(.center)
                                }

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
                                Task {
                                    print("🛒 Button tapped - checking for products...")
                                    print("🛒 Available products: \(storeManager.products.map { $0.id })")

                                    // Force reload products if none are loaded
                                    if storeManager.products.isEmpty {
                                        print("🛒 No products loaded, forcing reload...")
                                        storeManager.loadProducts()

                                        // Wait a moment for products to load
                                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                        print("🛒 After reload, products: \(storeManager.products.map { $0.id })")
                                    }

                                    guard let product = storeManager.subscriptionProduct() else {
                                        print("🛒 ERROR: No subscription product found!")
                                        print("🛒 Products loaded: \(storeManager.products.count)")
                                        print("🛒 Error message: \(storeManager.errorMessage ?? "none")")
                                        return
                                    }

                                    print("🛒 Found product: \(product.id) - \(product.displayName)")
                                    isPurchasing = true
                                    do {
                                        print("🛒 Starting purchase...")
                                        try await storeManager.purchase(product)
                                        print("🛒 Purchase completed!")
                                    } catch {
                                        print("🛒 Purchase failed: \(error)")
                                    }
                                    isPurchasing = false
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
                                        colors: [.green, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                                .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isPurchasing)
                            .scaleEffect(1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPurchasing)
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
                                                Task {
                                                    guard let product = storeManager.subscriptionProduct() else { return }
                                                    isPurchasing = true
                                                    do {
                                                        try await storeManager.purchase(product)
                                                    } catch {
                                                        print("Purchase failed: \(error)")
                                                    }
                                                    isPurchasing = false
                                                }
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

                                Text("🎛️ Early access to new crossfader feature")
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
    case tunnel = "tunnel_effect"
    case analogGlitch = "analog_glitch_effect"
    case kaleidoscope = "kaleidoscope_effect"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .crtDitherGlitch: return "HYPNOTIST"
        case .badTV: return "BAD TV"
        case .strobe: return "STROBE"
        case .convergence: return "CONVERGENCE"
        case .tunnel: return "TUNNEL"
        case .analogGlitch: return "ANALOG GLITCH"
        case .kaleidoscope: return "KALEIDOSCOPE"
        }
    }

    var description: String {
        switch self {
        case .crtDitherGlitch: return "Hypnotic waves, fast strobing colors, and audio-reactive image shake"
        case .badTV: return "Infinite feedback loops with vintage TV static, creating hypnotic recursive visuals"
        case .strobe: return "Audio-reactive RGB color channel strobing with independent frequency control"
        case .convergence: return "RGB channel separation with random displacement creating chromatic aberration glitch effects"
        case .tunnel: return "Concentric geometric tunnel effect with audio-reactive depth and motion"
        case .analogGlitch: return "Video interference simulation with scan lines, noise, and color distortion"
        case .kaleidoscope: return "Bilateral mirror symmetry creating kaleidoscopic visual patterns"
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
        case .tunnel: return "scope"
        case .analogGlitch: return "waveform.path.ecg"
        case .kaleidoscope: return "kaleidoscope"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .crtDitherGlitch: return [.red, .black, .gray]
        case .badTV: return [.white, .gray, .black, .blue]
        case .strobe: return [.red, .green, .blue, .white]
        case .convergence: return [.cyan, .pink, .yellow, .black]
        case .tunnel: return [.purple, .pink, .blue, .black]
        case .analogGlitch: return [.green, .yellow, .red, .gray]
        case .kaleidoscope: return [.orange, .red, .purple, .pink]
        }
    }
}

#Preview {
    PremiumMenuView()
}