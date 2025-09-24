import SwiftUI
import AVFoundation
import Metal
import MetalKit
import UIKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showMenu = false
    @State private var showVideoGallery = false
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var captureMode: CaptureMode = .video

    enum CaptureMode: String, CaseIterable {
        case photo = "PHOTO"
        case video = "VIDEO"
    }

    // Capture button for both photo and video
    var captureButton: some View {
        Button(action: {
            switch captureMode {
            case .photo:
                cameraManager.capturePhoto()
            case .video:
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                } else {
                    cameraManager.startRecording()
                }
            }
        }) {
            ZStack {
                Circle()
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)

                if captureMode == .video {
                    Circle()
                        .foregroundColor(cameraManager.isRecording ? .red : .white)
                        .frame(width: 65, height: 65)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        )

                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .foregroundColor(.white)
                            .frame(width: 25, height: 25)
                    }
                } else {
                    // Photo mode - simple white circle
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .frame(width: 65, height: 65)
                }
            }
        }
    }

    // Video thumbnail preview (placeholder for now)
    var videoThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .frame(width: 60, height: 60, alignment: .center)
            .foregroundColor(.gray.opacity(0.3))
            .overlay(
                Image(systemName: "video.fill")
                    .foregroundColor(.white)
                    .font(.title3)
            )
    }

    // Camera flip button
    var flipCameraButton: some View {
        Button(action: {
            cameraManager.switchCamera()
        }) {
            Circle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(width: 45, height: 45, alignment: .center)
                .overlay(
                    Image(systemName: "camera.rotate.fill")
                        .foregroundColor(.white)
                )
        }
        .disabled(cameraManager.isRecording)
        .opacity(cameraManager.isRecording ? 0.5 : 1.0)
    }

    var body: some View {
        ZStack {
            GeometryReader { reader in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)

                    VStack {
                        // Simple top bar with app title and menu
                        HStack {
                            Text("FΣVΣЯ DЯΣΛM")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Spacer()

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showMenu.toggle()
                                }
                            }) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        // Camera preview with zoom gesture
                        CameraPreviewView(cameraManager: cameraManager)
                            .gesture(
                                DragGesture().onChanged({ (val) in
                                    // Only accept vertical drag for zoom
                                    if abs(val.translation.height) > abs(val.translation.width) {
                                        // Get the percentage of vertical screen space covered by drag
                                        let percentage: CGFloat = -(val.translation.height / reader.size.height)
                                        // Calculate new zoom factor
                                        let calc = currentZoomFactor + percentage
                                        // Limit zoom factor to a maximum of 5x and a minimum of 1x
                                        let zoomFactor: CGFloat = min(max(calc, 1), 5)
                                        // Store the newly calculated zoom factor
                                        currentZoomFactor = zoomFactor
                                        // Apply zoom to camera
                                        cameraManager.setZoom(zoomFactor)
                                    }
                                })
                            )

                        // Mode switcher
                        HStack(spacing: 30) {
                            ForEach(CaptureMode.allCases, id: \.self) { mode in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        captureMode = mode
                                    }
                                }) {
                                    Text(mode.rawValue)
                                        .font(.system(size: 16, weight: captureMode == mode ? .bold : .medium))
                                        .foregroundColor(captureMode == mode ? .yellow : .white.opacity(0.7))
                                        .scaleEffect(captureMode == mode ? 1.1 : 1.0)
                                }
                                .disabled(cameraManager.isRecording)
                            }
                        }
                        .padding(.vertical, 10)

                        // Professional camera controls at bottom
                        HStack {
                            Button(action: {
                                showVideoGallery = true
                            }) {
                                videoThumbnail
                            }

                            Spacer()

                            captureButton

                            Spacer()

                            flipCameraButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }

            // Simple Menu Overlay
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
                        .background(Color.black.opacity(0.9))
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

    // Focus ring like Camera-SwiftUI
    let focusView: UIView = {
        let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        focusView.layer.borderColor = UIColor.white.cgColor
        focusView.layer.borderWidth = 1.5
        focusView.layer.cornerRadius = 25
        focusView.layer.opacity = 0
        focusView.backgroundColor = .clear
        return focusView
    }()

    @objc func focusAndExposeTap(gestureRecognizer: UITapGestureRecognizer) {
        guard let previewLayer = previewLayer else { return }

        let layerPoint = gestureRecognizer.location(in: gestureRecognizer.view)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)

        let focusCircleDiam: CGFloat = 50
        let shiftedLayerPoint = CGPoint(x: layerPoint.x - (focusCircleDiam / 2),
            y: layerPoint.y - (focusCircleDiam / 2))

        focusView.layer.frame = CGRect(origin: shiftedLayerPoint, size: CGSize(width: focusCircleDiam, height: focusCircleDiam))

        // Call focus and exposure on CameraManager
        if let cameraManager = self.cameraManager {
            cameraManager.setFocusAndExposure(at: devicePoint)
        }

        UIView.animate(withDuration: 0.3, animations: {
            self.focusView.layer.opacity = 1
        }) { (completed) in
            if completed {
                UIView.animate(withDuration: 0.3) {
                    self.focusView.layer.opacity = 0
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        effectLayer?.frame = bounds

        // Set up focus view and tap gesture
        self.layer.addSublayer(focusView.layer)

        let gRecognizer = UITapGestureRecognizer(target: self, action: #selector(CameraPreviewUIView.focusAndExposeTap(gestureRecognizer:)))
        self.addGestureRecognizer(gRecognizer)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 25, height: 25)

                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


#Preview {
    ContentView()
}