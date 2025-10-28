import SwiftUI
import AVFoundation
import Metal
import MetalKit
import UIKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showVideoGallery = false
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var captureMode: CaptureMode = .video
    @State private var isAppReady = false
    @State private var showPremiumMenu = false
    @StateObject private var storeManager = StoreManager()
    @State private var selectedEffect: PremiumEffect? = nil
    @State private var showEffectSelector = false
    @State private var currentEffectIndex = 0
    @State private var latestMediaThumbnail: UIImage?
    @State private var hasMediaFiles = false

    // All available effects (including default as nil)
    private var allEffects: [PremiumEffect?] {
        [nil] + PremiumEffect.allCases
    }

    // Effect cycling functions
    private func nextEffect() {
        currentEffectIndex = (currentEffectIndex + 1) % allEffects.count
        selectedEffect = allEffects[currentEffectIndex]
    }

    private func previousEffect() {
        currentEffectIndex = (currentEffectIndex - 1 + allEffects.count) % allEffects.count
        selectedEffect = allEffects[currentEffectIndex]
    }

    // Load latest media thumbnail
    private func loadLatestMediaThumbnail() {
        print("🔄 Loading latest media thumbnail for gallery icon")
        DispatchQueue.global(qos: .utility).async {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: documentsURL,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )

                // Filter for Fever Dream files and sort by filename (newest first)
                let feverDreamFiles = fileURLs.filter { url in
                    let fileName = url.lastPathComponent
                    return fileName.hasPrefix("FeverDream_") && (fileName.hasSuffix(".mp4") || fileName.hasSuffix(".jpg"))
                }.sorted { url1, url2 in
                    // Extract timestamps from filenames for proper comparison
                    let extractTimestamp = { (filename: String) -> Double in
                        let components = filename.components(separatedBy: "_")
                        if components.count >= 3 {
                            let timestampPart = components[2].components(separatedBy: ".")[0]
                            return Double(timestampPart) ?? 0
                        }
                        return 0
                    }

                    let timestamp1 = extractTimestamp(url1.lastPathComponent)
                    let timestamp2 = extractTimestamp(url2.lastPathComponent)
                    return timestamp1 > timestamp2  // Newer first
                }
                print("🔄 All sorted files for gallery icon: \(feverDreamFiles.map { $0.lastPathComponent })")

                DispatchQueue.main.async {
                    self.hasMediaFiles = !feverDreamFiles.isEmpty
                }

                guard let latestFile = feverDreamFiles.first else {
                    print("🔄 No media files found for gallery icon")
                    DispatchQueue.main.async {
                        self.latestMediaThumbnail = nil
                    }
                    return
                }
                print("🔄 Latest media file for gallery icon: \(latestFile.lastPathComponent)")

                let isVideo = latestFile.pathExtension.lowercased() == "mp4"
                let thumbnailImage: UIImage?

                if isVideo {
                    thumbnailImage = generateVideoThumbnail(from: latestFile)
                } else {
                    thumbnailImage = loadImageThumbnail(from: latestFile)
                }

                DispatchQueue.main.async {
                    self.latestMediaThumbnail = thumbnailImage
                }

            } catch {
                print("Error loading latest media: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.hasMediaFiles = false
                    self.latestMediaThumbnail = nil
                }
            }
        }
    }

    private func generateVideoThumbnail(from videoURL: URL) -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 65, height: 65)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private func loadImageThumbnail(from url: URL) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let targetSize = CGSize(width: 65, height: 65)
        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            let image = UIImage(cgImage: cgImage)
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    enum CaptureMode: String, CaseIterable {
        case photo = "PHOTO"
        case video = "VIDEO"
    }

    // Capture button for both photo and video
    var captureButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
            }
        }) {
            ZStack {
                // Always maintain the same outer dimensions to prevent UI shifts
                Circle()
                    .fill(Color.clear)
                    .frame(width: 80, height: 80)

                if captureMode == .video {
                    // Native iOS-style video record button
                    // Outer white circle with thin border (like native app)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )

                    // Inner element that changes when recording
                    if cameraManager.isRecording {
                        // Recording state: red rounded square
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                    } else {
                        // Not recording: red circle inside white circle
                        Circle()
                            .fill(Color.red)
                            .frame(width: 50, height: 50)
                    }

                    // Recording pulse effect (outer ring)
                    if cameraManager.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.6), lineWidth: 2)
                            .frame(width: 80, height: 80)
                            .scaleEffect(1.2)
                            .opacity(0.8)
                            .animation(
                                .easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                                value: cameraManager.isRecording
                            )
                    }
                } else {
                    // Photo mode - classic camera button style
                    // Outer white circle with thin border
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
        .frame(width: 80, height: 80) // Fixed frame to prevent shifts
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: cameraManager.isRecording)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: captureMode)
    }

    // Media thumbnail preview showing latest captured media
    var mediaThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .frame(width: 65, height: 65, alignment: .center)
                .foregroundColor(.gray.opacity(0.3))

            if let thumbnail = latestMediaThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 65, height: 65)
                    .clipped()
                    .cornerRadius(12)
            } else {
                Image(systemName: hasMediaFiles ? "photo.fill" : (captureMode == .photo ? "photo.fill" : "video.fill"))
                    .foregroundColor(.white)
                    .font(.system(size: 20))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    latestMediaThumbnail != nil ?
                    LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.6), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                    LinearGradient(colors: [.white.opacity(0.2)], startPoint: .center, endPoint: .center),
                    lineWidth: latestMediaThumbnail != nil ? 2 : 1
                )
        )
    }

    // Flash/torch button
    var flashButton: some View {
        Button(action: {
            cameraManager.toggleTorch()
        }) {
            Circle()
                .fill(
                    cameraManager.isTorchOn ?
                    LinearGradient(colors: [Color.yellow.opacity(0.6), Color.orange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                    LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.3), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 50, height: 50, alignment: .center)
                .overlay(
                    Circle()
                        .stroke(
                            cameraManager.isTorchOn ?
                            LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.6), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .foregroundColor(cameraManager.isTorchOn ? .white : .white)
                        .font(.system(size: 18))
                )
        }
        .disabled(cameraManager.isRecording || cameraManager.isUsingFrontCamera)
        .opacity((cameraManager.isRecording || cameraManager.isUsingFrontCamera) ? 0.3 : 1.0)
        .scaleEffect((cameraManager.isRecording || cameraManager.isUsingFrontCamera) ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording || cameraManager.isUsingFrontCamera)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cameraManager.isTorchOn)
    }

    // Camera flip button
    var flipCameraButton: some View {
        Button(action: {
            cameraManager.switchCamera()
        }) {
            Circle()
                .fill(
                    LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.3), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 50, height: 50, alignment: .center)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.6), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Image(systemName: "camera.rotate.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                )
        }
        .disabled(cameraManager.isRecording || cameraManager.isSwitchingCamera)
        .opacity((cameraManager.isRecording || cameraManager.isSwitchingCamera) ? 0.5 : 1.0)
        .scaleEffect((cameraManager.isRecording || cameraManager.isSwitchingCamera) ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording || cameraManager.isSwitchingCamera)
    }

    // Loading screen view
    var loadingView: some View {
        LoadingScreenView()
            .onAppear {
                // Simulate app initialization time
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        isAppReady = true
                    }
                }
            }
    }

    // Main content view with camera and controls
    var mainContentView: some View {
        GeometryReader { reader in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                VStack {
                    topBarView
                    cameraPreviewWithGestures(reader: reader)
                    modeSwitcherView
                    effectsSelectorView

                    // Crossfader (premium feature - only for subscribers)
                    if storeManager.hasSubscription,
                       let metalRenderer = cameraManager.effectsProcessor.getMetalRenderer() {
                        EffectMixerView(metalRenderer: metalRenderer)
                            .environmentObject(storeManager)
                            .padding(.horizontal)
                    } else {
                        // Premium upsell for crossfader
                        CrossfaderUpsellView(storeManager: storeManager, showPremiumMenu: $showPremiumMenu)
                            .padding(.horizontal)
                    }

                    cameraControlsView
                }
            }
        }
    }

    // Top navigation bar
    var topBarView: some View {
        VStack(spacing: 0) {
            HStack {
                // Flash button on top-left (only for back camera)
                if !cameraManager.isUsingFrontCamera {
                    flashButton
                } else {
                    // Empty space to keep title centered
                    Color.clear
                        .frame(width: 44, height: 44)
                }

                Spacer()

                Text("FΣVΣЯ DЯΣΛМ")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                // Flip camera button on top-right
                flipCameraButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(
                Color.black.opacity(0.4)
                    .ignoresSafeArea(.all, edges: .top)
            )
        }
        .zIndex(100) // Ensure top bar stays on top
    }

    // Camera preview with gestures
    func cameraPreviewWithGestures(reader: GeometryProxy) -> some View {
        CameraPreviewView(cameraManager: cameraManager)
            .id("cameraPreview") // Give stable identity
            .gesture(
                SimultaneousGesture(
                    // Vertical drag for zoom
                    DragGesture().onChanged({ (val) in
                        let percentage: CGFloat = -(val.translation.height / reader.size.height)
                        let calc = currentZoomFactor + percentage
                        let zoomFactor: CGFloat = min(max(calc, 1), 5)
                        currentZoomFactor = zoomFactor
                        cameraManager.setZoom(zoomFactor)
                    }),
                    // Pinch gesture for zoom
                    MagnificationGesture()
                        .onChanged({ magnification in
                            let newZoom = currentZoomFactor * magnification
                            let clampedZoom = min(max(newZoom, 1), 5)
                            cameraManager.setZoom(clampedZoom)
                        })
                        .onEnded({ magnification in
                            // Update the stored zoom factor when gesture ends
                            let newZoom = currentZoomFactor * magnification
                            currentZoomFactor = min(max(newZoom, 1), 5)
                        })
                )
            )
    }

    // Enhanced mode switcher between photo and video
    var modeSwitcherView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            captureMode = mode
                        }
                    }) {
                        VStack(spacing: 6) {
                            // Icon for each mode
                            Image(systemName: mode == .photo ? "camera.fill" : "video.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(captureMode == mode ? .white : .white.opacity(0.4))

                            // Mode label
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: captureMode == mode ? .semibold : .medium, design: .rounded))
                                .foregroundColor(captureMode == mode ? .white : .white.opacity(0.4))
                        }
                        .frame(width: 80, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    captureMode == mode ?
                                    LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.3), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color.clear], startPoint: .center, endPoint: .center)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            captureMode == mode ?
                                            LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                            LinearGradient(colors: [Color.clear], startPoint: .center, endPoint: .center),
                                            lineWidth: captureMode == mode ? 2 : 0
                                        )
                                )
                        )
                        .scaleEffect(captureMode == mode ? 1.05 : 1.0)
                    }
                    .disabled(cameraManager.isRecording)
                    .opacity(cameraManager.isRecording ? 0.5 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: captureMode)
                    .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording)
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
        }
    }

    // Effects selector interface
    var effectsSelectorView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button(action: {
                        print("🎨 Effects button tapped!")
                        showEffectSelector.toggle()
                    }) {
                        HStack(spacing: 10) {
                            Spacer()

                            VStack(alignment: .center, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(selectedEffect?.name ?? "FEVER DREAM")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 1.0))

                                    if !storeManager.hasSubscription {
                                        Text("PREMIUM")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.yellow)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.yellow.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.black.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(
                                            LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 1.0)], startPoint: .leading, endPoint: .trailing),
                                            lineWidth: 1.5
                                        )
                                )
                        )
                    }
                    .disabled(cameraManager.isRecording)
                    .scaleEffect(cameraManager.isRecording ? 0.95 : 1.0)
                    .opacity(cameraManager.isRecording ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording)
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
        }
    }

    // Camera controls at bottom
    var cameraControlsView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    showVideoGallery = true
                }) {
                    mediaThumbnail
                }

                Spacer()

                // Centered capture button
                captureButton

                Spacer()

                // Empty space to balance the layout (same width as gallery button)
                Color.clear
                    .frame(width: 65, height: 65)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(
                Color.black.opacity(0.4)
                    .ignoresSafeArea(.all, edges: .bottom)
            )
        }
    }


    var body: some View {
        ZStack {
            if !isAppReady {
                loadingView
            } else {
                mainContentView
            }
        }
        .onAppear {
            cameraManager.startSession()
            cameraManager.setStoreManager(storeManager)
            loadLatestMediaThumbnail()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MediaCaptured"))) { _ in
            print("🔄 ContentView received MediaCaptured notification, updating gallery icon")
            // Refresh thumbnail when new media is captured
            loadLatestMediaThumbnail()
        }
        .onChange(of: selectedEffect) { newEffect in
            cameraManager.setSelectedEffect(newEffect)
            // Sync currentEffectIndex with selectedEffect
            if let index = allEffects.firstIndex(where: { $0 == newEffect }) {
                currentEffectIndex = index
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
        .sheet(isPresented: $showPremiumMenu) {
            PremiumMenuView()
                .environmentObject(storeManager)
        }
        .sheet(isPresented: $showEffectSelector) {
            EffectsSelectorView(selectedEffect: $selectedEffect, storeManager: storeManager, showPremiumMenu: $showPremiumMenu)
        }
    }
}

struct EffectOptionView: View {
    let name: String
    let description: String
    let iconName: String
    let gradientColors: [Color]
    let isSelected: Bool
    let isOwned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isOwned ? .white : .white.opacity(0.5))

                        if !isOwned {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 12))
                        }
                    }

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(isOwned ? .white.opacity(0.7) : .white.opacity(0.4))
                }

                Spacer()

                if !isOwned {
                    Text("PREMIUM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(6)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 20))
                }
            }
            .padding()
            .background(
                isSelected && isOwned ?
                LinearGradient(colors: [Color.cyan.opacity(0.2), Color.purple.opacity(0.2)], startPoint: .leading, endPoint: .trailing) :
                LinearGradient(colors: [isOwned ? Color.white.opacity(0.05) : Color.white.opacity(0.02)], startPoint: .center, endPoint: .center)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected && isOwned ?
                        LinearGradient(colors: [Color.cyan, Color.purple], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [isOwned ? Color.white.opacity(0.3) : Color.white.opacity(0.1)], startPoint: .center, endPoint: .center),
                        lineWidth: isSelected && isOwned ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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


struct LoadingScreenView: View {
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // App title with chromatic aberration effect
                ZStack {
                    // Red channel (shifted right)
                    Text("FΣVΣЯ DЯΣΛM")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.red)
                        .offset(x: 2, y: 0)
                        .opacity(0.8)

                    // Green channel (centered)
                    Text("FΣVΣЯ DЯΣΛM")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                        .offset(x: 0, y: 0)
                        .opacity(0.8)

                    // Blue channel (shifted left)
                    Text("FΣVΣЯ DЯΣΛM")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.blue)
                        .offset(x: -2, y: 0)
                        .opacity(0.8)

                    // White overlay for readability
                    Text("FΣVΣЯ DЯΣΛM")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(0.9)
                }
                .shadow(color: Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.3), radius: 15, x: 0, y: 0)
            }
        }
    }
}

struct EffectsSelectorView: View {
    @Binding var selectedEffect: PremiumEffect?
    let storeManager: StoreManager
    @Binding var showPremiumMenu: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 10) {
                            Text("VISUAL EFFECTS")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Choose your visual style")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.top, 20)

                        // Default effect
                        EffectOptionView(
                            name: "FEVER DREAM",
                            description: "Classic retro vibes with audio-reactive colors",
                            iconName: "wand.and.stars",
                            gradientColors: [Color(red: 1.0, green: 0.0, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 1.0)],
                            isSelected: selectedEffect == nil,
                            isOwned: true,
                            action: {
                                selectedEffect = nil
                                dismiss()
                            }
                        )

                        // Premium effects
                        ForEach(PremiumEffect.allCases) { effect in
                            EffectOptionView(
                                name: effect.name,
                                description: effect.description,
                                iconName: effect.iconName,
                                gradientColors: effect.gradientColors,
                                isSelected: selectedEffect == effect,
                                isOwned: storeManager.canUseEffect(effect),
                                action: {
                                    print("🎯 Effect selected: \(effect.name)")
                                    if storeManager.canUseEffect(effect) {
                                        selectedEffect = effect
                                        dismiss()
                                    } else {
                                        // Show premium menu for purchase
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            showPremiumMenu = true
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Effect Mixer Components

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

struct CrossfaderUpsellView: View {
    let storeManager: StoreManager
    @Binding var showPremiumMenu: Bool

    var body: some View {
        VStack(spacing: 15) {
            // Header
            HStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)

                Text("CROSSFADER")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
            }

            Text("Mix between effects in real-time")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            // Mock crossfader (disabled)
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    // Left Effect
                    VStack(spacing: 8) {
                        Text("FEVER DREAM")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan.opacity(0.6))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 60, height: 30)
                            .overlay(
                                Text("FVR")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }

                    Spacer()

                    // Right Effect
                    VStack(spacing: 8) {
                        Text("HYPNOTIST")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.purple.opacity(0.6))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 60, height: 30)
                            .overlay(
                                Text("HYP")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                }

                // Mock crossfader slider (disabled)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.6))
                        .frame(height: 12)
                        .overlay(
                            LinearGradient(
                                colors: [.cyan.opacity(0.3), .yellow.opacity(0.2), .purple.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )

                    // Centered handle
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 20, height: 16)
                        .overlay(
                            VStack(spacing: 1) {
                                Rectangle().fill(Color.black.opacity(0.3)).frame(width: 10, height: 1)
                                Rectangle().fill(Color.black.opacity(0.3)).frame(width: 10, height: 1)
                            }
                        )
                }
            }

            // Upgrade button
            Button(action: {
                showPremiumMenu = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("UNLOCK CROSSFADER")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .shadow(color: .yellow.opacity(0.4), radius: 6, x: 0, y: 3)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [.yellow.opacity(0.4), .orange.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
}

#Preview {
    ContentView()
}