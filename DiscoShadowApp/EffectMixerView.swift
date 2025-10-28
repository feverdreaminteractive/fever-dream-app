import SwiftUI

struct EffectMixerView: View {
    @ObservedObject var metalRenderer: MetalRenderer
    @EnvironmentObject var storeManager: StoreManager
    @State private var showingMixer = true

    private let leftEffect: PremiumEffect? = nil
    private let rightEffect: PremiumEffect? = .convergence

    @State private var crossfaderPosition: Double = 0.0

    var body: some View {
        VStack {
            if storeManager.hasSubscription {
                VStack(spacing: 20) {
                    HStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text("FEVER DREAM")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(crossfaderPosition < 0 ? .cyan : .cyan.opacity(0.5))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(crossfaderPosition < 0 ? Color.cyan.opacity(0.8) : Color.black.opacity(0.6))
                                .frame(width: 80, height: 40)
                                .overlay(
                                    Text("FVR")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(crossfaderPosition < 0 ? .black : .white.opacity(0.7))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(crossfaderPosition < 0 ? .cyan : Color.white.opacity(0.3), lineWidth: 2)
                                )
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            Text("CONVERGENCE")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(crossfaderPosition > 0 ? .purple : .purple.opacity(0.5))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(crossfaderPosition > 0 ? Color.purple.opacity(0.8) : Color.black.opacity(0.6))
                                .frame(width: 80, height: 40)
                                .overlay(
                                    Text("CNV")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(crossfaderPosition > 0 ? .black : .white.opacity(0.7))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(crossfaderPosition > 0 ? .purple : Color.white.opacity(0.3), lineWidth: 2)
                                )
                        }
                    }

                    CrossfaderSlider(position: $crossfaderPosition)

                    HStack(spacing: 20) {
                        Text("L")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text("🎛️ CROSSFADER")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()

                        Text("R")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.8))
                        .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                )
                .onChange(of: crossfaderPosition) { _, newValue in
                    updateEffectBasedOnCrossfader(newValue)
                }
            }
        }
    }

    private func updateEffectBasedOnCrossfader(_ position: Double) {
        metalRenderer.crossfaderPosition = Float(position)

        if position < -0.1 {
            metalRenderer.activePremiumEffect = leftEffect
        } else if position > 0.1 {
            metalRenderer.activePremiumEffect = rightEffect
        } else {
            metalRenderer.activePremiumEffect = nil
        }
    }
}

struct CrossfaderSlider: View {
    @Binding var position: Double
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.6))
                    .frame(height: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                Circle()
                    .fill(
                        LinearGradient(
                            colors: position < 0 ? [.cyan, .blue] : position > 0 ? [.purple, .pink] : [.white, .gray],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .offset(x: CGFloat(position) * (geometry.size.width - 30) / 2)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let sliderWidth = geometry.size.width - 30
                        let newPosition = (value.location.x - 15) / sliderWidth * 2 - 1
                        position = max(-1, min(1, newPosition))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 30)
    }
}