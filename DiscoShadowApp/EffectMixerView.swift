import SwiftUI

struct EffectMixerView: View {
    @ObservedObject var metalRenderer: MetalRenderer
    @State private var showingMixer = true  // Always show the mixer

    // Two effects to mix between
    private let leftEffect: PremiumEffect? = nil  // Fever Dream (default disco)
    private let rightEffect: PremiumEffect? = .crtDitherGlitch  // Hypnotist

    // Crossfader position (-1.0 = full left, 0.0 = center, 1.0 = full right)
    @State private var crossfaderPosition: Double = 0.0

    var body: some View {
        VStack {
            // Two-Effect Crossfader Mixer Panel (always visible)
                VStack(spacing: 20) {
                    // Effect Labels
                    HStack(spacing: 20) {
                        // Left Effect
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

                        // Right Effect
                        VStack(spacing: 8) {
                            Text("HYPNOTIST")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(crossfaderPosition > 0 ? .purple : .purple.opacity(0.5))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(crossfaderPosition > 0 ? Color.purple.opacity(0.8) : Color.black.opacity(0.6))
                                .frame(width: 80, height: 40)
                                .overlay(
                                    Text("HYP")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(crossfaderPosition > 0 ? .black : .white.opacity(0.7))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(crossfaderPosition > 0 ? .purple : Color.white.opacity(0.3), lineWidth: 2)
                                )
                        }
                    }

                    // Crossfader
                    VStack(spacing: 12) {
                        Text("CROSSFADER")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))

                        CrossfaderSlider(position: $crossfaderPosition)

                        // Mix Level Indicator
                        HStack {
                            Text("L")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(crossfaderPosition < -0.1 ? .cyan : .white.opacity(0.5))

                            Spacer()

                            Text("MIX")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(abs(crossfaderPosition) < 0.3 ? .yellow : .white.opacity(0.5))

                            Spacer()

                            Text("R")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(crossfaderPosition > 0.1 ? .purple : .white.opacity(0.5))
                        }
                    }

                    // Quick Preset Buttons
                    HStack(spacing: 10) {
                        PresetButton(title: "FEVER") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                crossfaderPosition = -1.0
                            }
                        }

                        PresetButton(title: "MIX") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                crossfaderPosition = 0.0
                            }
                        }

                        PresetButton(title: "HYPNO") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                crossfaderPosition = 1.0
                            }
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(
                                    LinearGradient(
                                        colors: [.cyan.opacity(0.6), .purple.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onChange(of: crossfaderPosition) { _, _ in updateMixer() }
        .onAppear {
            print("🎚️ EffectMixerView: Mixer appearing, activating crossfader")
            updateMixer()
        }
    }

    private func updateMixer() {
        // Enable crossfader mode in MetalRenderer
        metalRenderer.isCrossfaderActive = true

        // Set the two effects and crossfader position
        metalRenderer.leftEffect = leftEffect
        metalRenderer.rightEffect = rightEffect
        metalRenderer.crossfaderPosition = Float(crossfaderPosition)

        print("🎚️ EffectMixerView: Crossfader updated - Position: \(crossfaderPosition), Left: \(leftEffect), Right: \(rightEffect)")
    }
}

struct CrossfaderSlider: View {
    @Binding var position: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.8))
                    .frame(height: 16)
                    .overlay(
                        // Gradient track showing mix zones
                        LinearGradient(
                            colors: [.cyan.opacity(0.5), .yellow.opacity(0.3), .purple.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                // Center line
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 2, height: 20)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Crossfader Handle
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(width: 30, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        // Handle grip lines
                        VStack(spacing: 2) {
                            Rectangle().fill(Color.black.opacity(0.4)).frame(width: 16, height: 1)
                            Rectangle().fill(Color.black.opacity(0.4)).frame(width: 16, height: 1)
                            Rectangle().fill(Color.black.opacity(0.4)).frame(width: 16, height: 1)
                        }
                    )
                    .position(
                        x: geometry.size.width * CGFloat((position + 1.0) / 2.0),
                        y: geometry.size.height / 2
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newPosition = (Double(value.location.x / geometry.size.width) * 2.0) - 1.0
                        position = max(-1.0, min(1.0, newPosition))
                    }
            )
        }
        .frame(height: 40)
    }
}

struct PresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                )
        }
    }
}

#Preview {
    EffectMixerView(metalRenderer: MetalRenderer())
        .background(Color.black)
}