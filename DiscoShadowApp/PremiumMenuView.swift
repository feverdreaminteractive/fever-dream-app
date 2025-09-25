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

                                Text("Get all premium effects + future releases")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)

                                VStack(spacing: 5) {
                                    Text("$10.00")
                                        .font(.system(size: 28, weight: .black))
                                        .foregroundColor(.green)

                                    Text("per year")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }

                            Button(action: {
                                showingSubscriptionSheet = true
                            }) {
                                Text("SUBSCRIBE NOW")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
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
                                                selectedEffect = effect
                                                showingIndividualEffectSheet = true
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }

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

                            Text(effect.price)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
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
    case bridgetRileyOpArt = "bridget_riley_op_art_effect"
    case opArtTriangles = "op_art_triangles_effect"
    case tunnelVision = "tunnel_vision_effect"
    case basicFeedback = "basic_feedback_effect"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .crtDitherGlitch: return "VHS DATAMOSH"
        case .bridgetRileyOpArt: return "ATARI 1977 RETRO"
        case .opArtTriangles: return "BLOTTER"
        case .tunnelVision: return "OP-ART WAVES"
        case .basicFeedback: return "FEEDBACK TRAILS"
        }
    }

    var description: String {
        switch self {
        case .crtDitherGlitch: return "Vintage VHS tape corruption with datamoshing artifacts"
        case .bridgetRileyOpArt: return "Retro computer graphics with pixelated video and geometric patterns"
        case .opArtTriangles: return "Psychedelic patterns with audio-reactive color explosions and visual distortions"
        case .tunnelVision: return "Animated Op-Art waves with HSV color cycling and audio-reactive distortions"
        case .basicFeedback: return "Classic feedback effect with audio-reactive trailing and echo patterns"
        }
    }

    var price: String {
        switch self {
        case .crtDitherGlitch: return "$3.99"
        case .bridgetRileyOpArt: return "$4.99"
        case .opArtTriangles: return "$3.99"
        case .tunnelVision: return "$4.99"
        case .basicFeedback: return "$2.99"
        }
    }

    var iconName: String {
        switch self {
        case .crtDitherGlitch: return "video.and.waveform.fill"
        case .bridgetRileyOpArt: return "circle.hexagonpath.fill"
        case .opArtTriangles: return "triangle.fill"
        case .tunnelVision: return "waveform"
        case .basicFeedback: return "arrow.triangle.2.circlepath"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .crtDitherGlitch: return [.red, .black, .gray]
        case .bridgetRileyOpArt: return [.black, .white, .gray]
        case .opArtTriangles: return [.purple, .pink, .cyan]
        case .tunnelVision: return [.red, .pink, .orange]
        case .basicFeedback: return [.blue, .cyan, .green]
        }
    }
}

#Preview {
    PremiumMenuView()
}