import SwiftUI
import AVFoundation
import Metal
import MetalKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showInfo = false

    var body: some View {
        ZStack {
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        PsychedelicText("FΣVΣЯ DЯΣΛM", size: 24)

                        PsychedelicText("", size: 12)
                            .foregroundStyle(
                                AngularGradient(
                                    colors: [.white],
                                    center: .center
                                )
                            )
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)

                Spacer()

                if showInfo {
                    VStack(spacing: 12) {
                        Text("🌈 MAXIMUM PSYCHEDELIC EXPERIENCE 🌈")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.pink, .purple, .cyan, .green, .yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .multilineTextAlignment(.center)

                        Text("✨ Kaleidoscope Morphing\n🎆 Digital Glitch Artifacts\n🌊 Space-Time Warping\n💫 Chromatic Aberration\n🔥 Pulsating Rainbow Colors\n🌀 Fractal Noise Layers")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.black.opacity(0.95))
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }

                // Warp Magnitude Slider
                VStack(spacing: 8) {
                    HStack {
                        Text("🌊 WARP INTENSITY")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(cameraManager.warpMagnitude * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan)
                    }

                    Slider(value: $cameraManager.warpMagnitude, in: 0.0...2.0, step: 0.1)
                        .accentColor(.cyan)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .padding(.horizontal)

                HStack(spacing: 20) {
                    Button(action: {
                        if cameraManager.isRecording {
                            cameraManager.stopRecording()
                        } else {
                            cameraManager.startRecording()
                        }
                    }) {
                        Image(systemName: cameraManager.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.title)
                            .foregroundColor(cameraManager.isRecording ? .red : .white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showInfo.toggle()
                        }
                    }) {
                        Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .alert(isPresented: $cameraManager.shouldShowAlertView) {
            Alert(
                title: Text(cameraManager.alertError.title),
                message: Text(cameraManager.alertError.message),
                primaryButton: .default(Text(cameraManager.alertError.primaryButtonTitle), action: cameraManager.alertError.primaryAction),
                secondaryButton: .cancel(Text(cameraManager.alertError.secondaryButtonTitle ?? "Cancel"), action: cameraManager.alertError.secondaryAction)
            )
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let preview = CameraPreviewUIView()
        preview.cameraManager = cameraManager
        return preview
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Effects are now fully automatic
    }
}

class CameraPreviewUIView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    var cameraManager: CameraManager? {
        didSet {
            setupPreview()
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var effectLayer: CALayer?
    private let ciContext = CIContext() // Reuse context for performance

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        effectLayer?.frame = bounds
    }

    private func setupPreview() {
        guard let cameraManager = cameraManager else { return }

        previewLayer?.removeFromSuperlayer()
        previewLayer = AVCaptureVideoPreviewLayer(session: cameraManager.session)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = bounds

        if let previewLayer = previewLayer {
            layer.addSublayer(previewLayer)
        }

        // Set up video data output for effects processing
        print("🔗 Setting camera delegate to self")
        cameraManager.videoDataOutputDelegate = self
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("📹 Camera frame captured!")
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cameraManager = cameraManager else {
            print("❌ Failed to get pixel buffer or camera manager")
            return
        }

        // Process the frame with effects
        print("🎬 About to process frame with effects processor...")
        if let processedBuffer = cameraManager.effectsProcessor.processPixelBuffer(pixelBuffer) {
            print("✅ Frame processed successfully")
            // Write processed frame to recording if active
            cameraManager.writeVideoFrame(processedBuffer)

            DispatchQueue.main.async {
                self.displayProcessedFrame(processedBuffer)
            }
        } else {
            print("❌ Effects processor returned nil")
        }
    }

    private func displayProcessedFrame(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            effectLayer?.removeFromSuperlayer()
            effectLayer = CALayer()
            effectLayer?.contents = cgImage
            effectLayer?.frame = bounds
            effectLayer?.contentsGravity = .resizeAspectFill

            if let effectLayer = effectLayer {
                layer.addSublayer(effectLayer)
            }
        }
    }
}

struct PsychedelicText: View {
    let text: String
    let size: CGFloat
    @State private var animationPhase: Double = 0

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .pink,
                        .purple,
                        .blue,
                        .cyan,
                        .green,
                        .yellow,
                        .orange,
                        .red
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: .black, radius: 3, x: 2, y: 2)
            .shadow(color: .pink.opacity(0.7), radius: 10, x: 0, y: 0)
            .shadow(color: .cyan.opacity(0.5), radius: 15, x: 0, y: 0)
            .scaleEffect(1.0 + sin(animationPhase) * 0.05)
            .rotationEffect(.degrees(sin(animationPhase * 0.7) * 2))
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    animationPhase = .pi * 2
                }
            }
    }
}

#Preview {
    ContentView()
}