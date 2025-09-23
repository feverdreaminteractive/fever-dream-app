import SwiftUI
import AVFoundation
import Metal
import MetalKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showMenu = false
    @State private var showVideoGallery = false
    @State private var animationPhase: Double = 0

    // Animated rainbow gradient for UI elements
    private var rainbowGradient: LinearGradient {
        LinearGradient(
            colors: [
                .red,
                .orange,
                .yellow,
                .green,
                .blue,
                .indigo,
                .purple,
                .red // Loop back to red for smooth animation
            ],
            startPoint: UnitPoint(
                x: 0.5 + 0.5 * cos(animationPhase),
                y: 0.5 + 0.5 * sin(animationPhase)
            ),
            endPoint: UnitPoint(
                x: 0.5 + 0.5 * cos(animationPhase + .pi),
                y: 0.5 + 0.5 * sin(animationPhase + .pi)
            )
        )
    }

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

                HStack(spacing: 30) {
                    // Camera switch button
                    Button(action: {
                        cameraManager.switchCamera()
                    }) {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                ZStack {
                                    Color.black.opacity(0.3)
                                    rainbowGradient.opacity(0.8)
                                }
                            )
                            .clipShape(Circle())
                            .shadow(color: .purple.opacity(0.6), radius: 8, x: 0, y: 0)
                            .shadow(color: .cyan.opacity(0.4), radius: 15, x: 0, y: 0)
                    }
                    .disabled(cameraManager.isRecording)
                    .opacity(cameraManager.isRecording ? 0.5 : 1.0)

                    // Record button
                    Button(action: {
                        if cameraManager.isRecording {
                            cameraManager.stopRecording()
                        } else {
                            cameraManager.startRecording()
                        }
                    }) {
                        Image(systemName: cameraManager.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                ZStack {
                                    Color.black.opacity(0.3)
                                    if cameraManager.isRecording {
                                        Color.red.opacity(0.9)
                                    } else {
                                        rainbowGradient.opacity(0.8)
                                    }
                                }
                            )
                            .clipShape(Circle())
                            .shadow(color: cameraManager.isRecording ? .red.opacity(0.8) : .purple.opacity(0.6), radius: 8, x: 0, y: 0)
                            .shadow(color: cameraManager.isRecording ? .red.opacity(0.5) : .cyan.opacity(0.4), radius: 15, x: 0, y: 0)
                    }

                    // Hamburger menu button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showMenu.toggle()
                        }
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                ZStack {
                                    Color.black.opacity(0.3)
                                    rainbowGradient.opacity(0.8)
                                }
                            )
                            .clipShape(Circle())
                            .shadow(color: .purple.opacity(0.6), radius: 8, x: 0, y: 0)
                            .shadow(color: .cyan.opacity(0.4), radius: 15, x: 0, y: 0)
                    }
                }
                .padding(.bottom, 50)
            }

            // Hamburger Menu Overlay
            if showMenu {
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        VStack(spacing: 0) {
                            // Menu Items
                            MenuButton(icon: "square.and.arrow.down", title: "Download Videos", action: {
                                showVideoGallery = true
                                showMenu = false
                            })

                            MenuButton(icon: "gearshape", title: "Settings", action: {
                                // TODO: Open Settings
                                showMenu = false
                            })

                            MenuButton(icon: "questionmark.circle", title: "Help & Tips", action: {
                                // TODO: Open Help
                                showMenu = false
                            })

                            MenuButton(icon: "star", title: "Rate App", action: {
                                // TODO: Open App Store Rating
                                showMenu = false
                            })

                            MenuButton(icon: "xmark", title: "Close", action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showMenu = false
                                }
                            })
                        }
                        .background(
                            ZStack {
                                Color.black.opacity(0.8)
                                rainbowGradient.opacity(0.3)
                            }
                        )
                        .cornerRadius(20)
                        .padding(.trailing, 20)
                        .padding(.bottom, 120)
                    }
                }
                .background(Color.black.opacity(0.3))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showMenu = false
                    }
                }
            }
        }
        .onAppear {
            cameraManager.startSession()
            // Start rainbow animation
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
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
        .sheet(isPresented: $showVideoGallery) {
            VideoGalleryView()
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

        // Set up video data output for effects processing and recording
        print("🔗 Setting camera video delegate to self")
        cameraManager.videoDataOutputDelegate = self
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let cameraManager = cameraManager else {
            print("❌ Camera manager is nil")
            return
        }

        // Only handle video output - audio is now handled by AudioManager
        if output is AVCaptureVideoDataOutput {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("❌ Failed to get pixel buffer")
                return
            }

            // Process the frame with effects
            if let processedBuffer = cameraManager.effectsProcessor.processPixelBuffer(pixelBuffer) {
                // Write processed frame to recording if active
                cameraManager.writeVideoFrame(processedBuffer)

                DispatchQueue.main.async {
                    self.displayProcessedFrame(processedBuffer)
                }
            } else {
                print("❌ Effects processor returned nil")
            }
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

struct MenuButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    // Rainbow gradient for menu items
    private let rainbowGradient = LinearGradient(
        colors: [
            .red,
            .orange,
            .yellow,
            .green,
            .blue,
            .indigo,
            .purple
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(rainbowGradient)
                    .frame(width: 25, height: 25)

                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(rainbowGradient)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
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