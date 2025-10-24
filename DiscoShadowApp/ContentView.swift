import SwiftUI
import AVFoundation
import Metal
import MetalKit
import UIKit

enum CaptureMode: String, CaseIterable {
    case photo = "PHOTO"
    case video = "VIDEO"
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showVideoGallery = false
    @State private var currentZoomFactor: CGFloat = 1.0
    @State private var captureMode: CaptureMode = .video
    @State private var isAppReady = false
    @State private var showPremiumMenu = false
    @StateObject private var storeManager = StoreManager()
    @State private var selectedEffect: PremiumEffect? = nil
    @State private var currentEffectIndex = 0
    @State private var showModeSelector = false
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
                // Outer ring with gradient animation
                Circle()
                    .fill(
                        cameraManager.isRecording ?
                        LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [.white], startPoint: .center, endPoint: .center)
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(cameraManager.isRecording ? 1.1 : 1.0)
                    .opacity(cameraManager.isRecording ? 0.9 : 1.0)

                if captureMode == .video {
                    Circle()
                        .fill(
                            cameraManager.isRecording ?
                            LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0), .red], startPoint: .topLeading, endPoint: .bottomTrailing) :
                            LinearGradient(colors: [.white], startPoint: .center, endPoint: .center)
                        )
                        .frame(width: 65, height: 65)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        )
                        .scaleEffect(cameraManager.isRecording ? 0.9 : 1.0)

                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                } else {
                    // Photo mode - simple white circle with subtle animation
                    Circle()
                        .stroke(Color.black.opacity(0.8), lineWidth: 2)
                        .frame(width: 65, height: 65)
                        .scaleEffect(1.0)
                }

                // Recording pulse effect with gradient
                if cameraManager.isRecording {
                    Circle()
                        .stroke(
                            LinearGradient(colors: [Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.8), Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 3
                        )
                        .frame(width: 90, height: 90)
                        .scaleEffect(1.2)
                        .opacity(0.7)
                        .animation(
                            .easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                            value: cameraManager.isRecording
                        )
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: cameraManager.isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: captureMode)
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
                    effectsSelectorView
                    cameraControlsView
                }
            }
        }
    }

    // Top navigation bar
    var topBarView: some View {
        VStack(spacing: 0) {
            HStack {
                // Camera flip button in top left
                Button(action: {
                    cameraManager.switchCamera()
                }) {
                    Image(systemName: "camera.rotate.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20, weight: .medium))
                }
                .disabled(cameraManager.isRecording || cameraManager.isSwitchingCamera)
                .opacity((cameraManager.isRecording || cameraManager.isSwitchingCamera) ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording || cameraManager.isSwitchingCamera)

                Spacer()

                // Center title
                Text("FΣVΣЯ DЯΣΛМ")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                // Flash button in top right (like native camera app)
                if !cameraManager.isUsingFrontCamera {
                    Button(action: {
                        cameraManager.toggleTorch()
                    }) {
                        Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundColor(cameraManager.isTorchOn ? .yellow : .white)
                            .font(.system(size: 20, weight: .medium))
                    }
                    .disabled(cameraManager.isRecording)
                    .opacity(cameraManager.isRecording ? 0.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cameraManager.isTorchOn)
                } else {
                    // Keep spacing consistent when front camera is active
                    Color.clear.frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(
                // Low opacity bar for better button visibility
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.black.opacity(0.3))
                    .blur(radius: 10)
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


    // Crossfader mixer (always visible)
    var effectsSelectorView: some View {
        VStack(spacing: 0) {
            // Always show crossfader mixer
            if let metalRenderer = cameraManager.effectsProcessor.metalRenderer {
                SimpleCrossfaderView(metalRenderer: metalRenderer, showingMixer: .constant(true))
                    .disabled(cameraManager.isRecording)
                    .opacity(cameraManager.isRecording ? 0.6 : 1.0)
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 20)
    }

    // Camera controls at bottom
    var cameraControlsView: some View {
        VStack(spacing: 0) {
            HStack {
                // Left side - Gallery thumbnail
                Button(action: {
                    showVideoGallery = true
                }) {
                    mediaThumbnail
                }

                Spacer()

                // Center - Capture button only (centered under MIX)
                captureButton

                Spacer()

                // Right side - Mode dropdown arrow (positioned to balance)
                Button(action: {
                    showModeSelector = true
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
                .disabled(cameraManager.isRecording)
                .opacity(cameraManager.isRecording ? 0.3 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
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
        .sheet(isPresented: $showModeSelector) {
            CaptureModePickerView(selectedMode: $captureMode)
        }
    }
}

enum EffectChoice: CaseIterable {
    case feverDream
    case hypnotist
    case badTV
    case strobe
    case convergence

    var displayName: String {
        switch self {
        case .feverDream: return "FEVER DREAM"
        case .hypnotist: return "HYPNOTIST"
        case .badTV: return "BAD TV"
        case .strobe: return "STROBE"
        case .convergence: return "CONVERGENCE"
        }
    }

    var abbreviation: String {
        switch self {
        case .feverDream: return "FVR"
        case .hypnotist: return "HYP"
        case .badTV: return "TV"
        case .strobe: return "STR"
        case .convergence: return "CON"
        }
    }

    func toPremiumEffect() -> PremiumEffect? {
        switch self {
        case .feverDream: return nil  // Default disco effect
        case .hypnotist: return .crtDitherGlitch
        case .badTV: return .badTV
        case .strobe: return .strobe
        case .convergence: return .convergence
        }
    }
}

struct SimpleCrossfaderView: View {
    @ObservedObject var metalRenderer: MetalRenderer
    @Binding var showingMixer: Bool
    @State private var crossfaderPosition: Double = 0.0
    @State private var showLeftEffectSelector = false
    @State private var showRightEffectSelector = false

    // Selectable effects
    @State private var leftEffect: EffectChoice = .feverDream
    @State private var rightEffect: EffectChoice = .hypnotist

    var body: some View {
        VStack {
            // Simple Crossfader Panel
            VStack(spacing: 15) {
                    // Effect Labels - Selectable
                    HStack {
                        Button(action: {
                            showLeftEffectSelector = true
                        }) {
                            HStack(spacing: 4) {
                                Text(leftEffect.displayName)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(crossfaderPosition < 0 ? .cyan : .cyan.opacity(0.5))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        Spacer()

                        Button(action: {
                            showRightEffectSelector = true
                        }) {
                            HStack(spacing: 4) {
                                Text(rightEffect.displayName)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(crossfaderPosition > 0 ? .purple : .purple.opacity(0.5))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }

                    // Crossfader Slider
                    HStack {
                        Text("L")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cyan)

                        Slider(value: $crossfaderPosition, in: -1.0...1.0)
                            .accentColor(.white)

                        Text("R")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple)
                    }

                    // Quick Preset Buttons
                    HStack(spacing: 8) {
                        Button(leftEffect.abbreviation) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                crossfaderPosition = -1.0
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.7))
                        .cornerRadius(8)

                        Button("MIX") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                crossfaderPosition = 0.0
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.7))
                        .cornerRadius(8)

                        Button(rightEffect.abbreviation) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                crossfaderPosition = 1.0
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.7))
                        .cornerRadius(8)
                    }
                }
                .padding(15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
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
        .onChange(of: crossfaderPosition) { _, _ in updateCrossfader() }
        .onChange(of: leftEffect) { _, _ in updateCrossfader() }
        .onChange(of: rightEffect) { _, _ in updateCrossfader() }
        .onAppear {
            metalRenderer.isCrossfaderActive = true
            updateCrossfader()
            print("🎚️ SimpleCrossfaderView: Activated crossfader on appear")
        }
        .sheet(isPresented: $showLeftEffectSelector) {
            EffectPickerView(selectedEffect: $leftEffect, title: "LEFT EFFECT")
        }
        .sheet(isPresented: $showRightEffectSelector) {
            EffectPickerView(selectedEffect: $rightEffect, title: "RIGHT EFFECT")
        }
    }

    private func updateCrossfader() {
        metalRenderer.leftEffect = leftEffect.toPremiumEffect()
        metalRenderer.rightEffect = rightEffect.toPremiumEffect()
        metalRenderer.crossfaderPosition = Float(crossfaderPosition)
        print("🎚️ SimpleCrossfaderView: Updated crossfader - Left: \(leftEffect.displayName), Right: \(rightEffect.displayName), Position: \(crossfaderPosition)")
    }
}

struct EffectPickerView: View {
    @Binding var selectedEffect: EffectChoice
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(EffectChoice.allCases, id: \.self) { effect in
                            Button(action: {
                                selectedEffect = effect
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(effect.displayName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)

                                        Text(getEffectDescription(effect))
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.7))
                                    }

                                    Spacer()

                                    if selectedEffect == effect {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.cyan)
                                            .font(.system(size: 20))
                                    }
                                }
                                .padding()
                                .background(
                                    selectedEffect == effect ?
                                    LinearGradient(colors: [Color.cyan.opacity(0.2), Color.purple.opacity(0.2)], startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [Color.white.opacity(0.05)], startPoint: .center, endPoint: .center)
                                )
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedEffect == effect ?
                                            LinearGradient(colors: [Color.cyan, Color.purple], startPoint: .leading, endPoint: .trailing) :
                                            LinearGradient(colors: [Color.clear], startPoint: .center, endPoint: .center),
                                            lineWidth: selectedEffect == effect ? 2 : 0
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
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

    private func getEffectDescription(_ effect: EffectChoice) -> String {
        switch effect {
        case .feverDream: return "Classic retro vibes with audio-reactive colors"
        case .hypnotist: return "Mesmerizing CRT dither glitch patterns"
        case .badTV: return "Vintage television distortion effects"
        case .strobe: return "Intense flashing light sequences"
        case .convergence: return "Extreme audio-reactive visual convergence"
        }
    }
}

struct CaptureModePickerView: View {
    @Binding var selectedMode: CaptureMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Button(action: {
                            selectedMode = mode
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Image(systemName: mode == .photo ? "camera.fill" : "video.fill")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)

                                        Text(mode.rawValue)
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.white)
                                    }

                                    Text(getModeDescription(mode))
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                Spacer()

                                if selectedMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.cyan)
                                        .font(.system(size: 24))
                                }
                            }
                            .padding(20)
                            .background(
                                selectedMode == mode ?
                                LinearGradient(colors: [Color.cyan.opacity(0.2), Color.purple.opacity(0.2)], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(colors: [Color.white.opacity(0.05)], startPoint: .center, endPoint: .center)
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        selectedMode == mode ?
                                        LinearGradient(colors: [Color.cyan, Color.purple], startPoint: .leading, endPoint: .trailing) :
                                        LinearGradient(colors: [Color.clear], startPoint: .center, endPoint: .center),
                                        lineWidth: selectedMode == mode ? 2 : 0
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("CAPTURE MODE")
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

    private func getModeDescription(_ mode: CaptureMode) -> String {
        switch mode {
        case .photo: return "Capture still images with effects"
        case .video: return "Record video with real-time effects"
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
                // App title
                Text("FΣVΣЯ DЯΣΛM")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                // Loading text
                Text("Loading")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }
}

struct EffectsSelectorView: View {
    @Binding var selectedEffect: PremiumEffect?
    let storeManager: StoreManager
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
                                isOwned: true, // Temporarily bypass ownership check
                                action: {
                                    print("🎯 Effect selected: \(effect.name)")
                                    // Temporarily bypass ownership check for testing
                                    selectedEffect = effect
                                    dismiss()
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
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.0, green: 1.0, blue: 1.0))
                        .font(.system(size: 20))
                }
            }
            .padding()
            .background(
                isSelected ?
                LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.2), Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.2)], startPoint: .leading, endPoint: .trailing) :
                LinearGradient(colors: [Color.white.opacity(0.05)], startPoint: .center, endPoint: .center)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                        LinearGradient(colors: [Color(red: 1.0, green: 0.0, blue: 1.0), Color(red: 0.0, green: 1.0, blue: 1.0)], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [Color.clear], startPoint: .center, endPoint: .center),
                        lineWidth: isSelected ? 2 : 0
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ContentView()
}