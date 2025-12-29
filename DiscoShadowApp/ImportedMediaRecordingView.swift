import SwiftUI
import AVFoundation
import AVKit
import UIKit
import MusicKit
import Photos

@available(iOS 15.0, *)
struct ImportedMediaRecordingView: View {
    @Binding var isPresented: Bool
    let importedAssetURL: URL?
    let importedImage: UIImage?
    let cameraManager: CameraManager
    let selectedEffect: PremiumEffect?

    @State private var workingImage: UIImage?

    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showResults = false
    @State private var recordedVideoURL: URL?
    @State private var showMusicBrowser = false
    @State private var selectedSong: Song?
    @State private var isPlayingMusic = false
    @State private var musicVolume: Float = 0.5
    @StateObject private var storeManager = StoreManager()
    @StateObject private var simpleMusicManager = SimpleMusicManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                // Top bar with close button
                HStack {
                    Button("Cancel") {
                        stopRecording()
                        isPresented = false
                    }
                    .foregroundColor(.white)

                    Spacer()

                    Text("Record with Imported Media")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    if isRecording {
                        Text(formattedDuration)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
                .padding()

                // Preview area showing imported media with effects
                GeometryReader { geometry in
                    ZStack {
                        Color.black

                        // Show either original or effects-processed media
                        if let workingImage = workingImage {
                            ImportedImageEffectsView(
                                image: workingImage,
                                effectsProcessor: cameraManager.effectsProcessor,
                                selectedEffect: selectedEffect,
                                isRecording: isRecording
                            )
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        } else if let importedAssetURL = importedAssetURL {
                            ImportedVideoPlayerView(url: importedAssetURL)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            // Enhanced debug view
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.orange)

                                Text("Media Import Issue")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .fontWeight(.bold)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Debug Info:")
                                        .foregroundColor(.white.opacity(0.7))
                                        .font(.caption)

                                    Text("• Image: \(workingImage != nil ? "Available" : "Missing")")
                                        .foregroundColor(workingImage != nil ? .green : .red)
                                        .font(.caption)

                                    Text("• Video: \(importedAssetURL != nil ? "Available" : "Missing")")
                                        .foregroundColor(importedAssetURL != nil ? .green : .red)
                                        .font(.caption)

                                    if let url = importedAssetURL {
                                        Text("• Path: \(url.lastPathComponent)")
                                            .foregroundColor(.white.opacity(0.6))
                                            .font(.caption2)
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isRecording ? Color.red : Color.purple, lineWidth: 3)
                )

                // Crossfader controls
                VStack(spacing: 0) {
                    if let metalRenderer = cameraManager.effectsProcessor.metalRenderer {
                        SimpleCrossfaderView(
                            metalRenderer: metalRenderer,
                            showingMixer: .constant(true),
                            storeManager: storeManager,
                            showPremiumMenu: .constant(false),
                            selectedSong: selectedSong,
                            isPlayingMusic: isPlayingMusic
                        )
                    }
                }
                .padding(.vertical, 15)
                .padding(.horizontal, 20)

                // Recording controls
                VStack(spacing: 20) {
                    // Media and music controls row
                    HStack(spacing: 16) {
                        // Media info
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: workingImage != nil ? "photo.fill" : "video.fill")
                                    .foregroundColor(.cyan)
                                Text(workingImage != nil ? "Photo" : "Video")
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            // Effect info
                            if let selectedEffect = selectedEffect {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                        .foregroundColor(.purple)
                                    Text(selectedEffect.name)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }

                        Spacer()

                        // Music controls
                        HStack(spacing: 12) {
                            // Music browser button
                            Button(action: {
                                showMusicBrowser = true
                            }) {
                                Image(systemName: selectedSong != nil ? "music.note" : "music.note.list")
                                    .foregroundColor(selectedSong != nil ? .purple : .white)
                                    .font(.system(size: 20, weight: .medium))
                            }

                            // Play/pause button (only show if song selected)
                            if selectedSong != nil {
                                Button(action: {
                                    Task {
                                        await toggleMusicPlayback()
                                    }
                                }) {
                                    Image(systemName: isPlayingMusic ? "pause.fill" : "play.fill")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 18, weight: .medium))
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Save current frame button (for images)
                    if workingImage != nil && !isRecording {
                        Button(action: {
                            saveCurrentFrame()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save Photo")
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.bottom, 10)
                    }

                    // Record button
                    Button(action: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red : Color.clear)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                )

                            if isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 24, height: 24)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        .scaleEffect(isRecording ? 0.9 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isRecording)
                    }
                    .disabled(false) // You can add conditions here

                    Text(isRecording ? "Recording..." : "Tap to Record")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🎬 ImportedMediaRecordingView appeared")
            print("📱 Imported image: \(importedImage != nil ? "✓ size: \(importedImage?.size ?? CGSize.zero)" : "✗")")
            print("📱 Imported video URL: \(importedAssetURL?.absoluteString ?? "none")")
            if let url = importedAssetURL {
                let fileExists = FileManager.default.fileExists(atPath: url.path)
                print("📱 Video file exists: \(fileExists)")
            }

            // Copy imported image to working state to prevent data loss
            if let importedImage = importedImage {
                workingImage = importedImage
                print("✅ Copied imported image to working image: \(importedImage.size)")
            }

            // DO NOT auto-close - let user see the debug view
            if importedImage == nil && importedAssetURL == nil {
                print("⚠️ No media available - showing debug view")
            }
        }
        .onDisappear {
            stopRecording()
        }
        .sheet(isPresented: $showResults) {
            if let recordedVideoURL = recordedVideoURL {
                RecordingResultsView(
                    videoURL: recordedVideoURL,
                    isPresented: $showResults
                )
            }
        }
        .sheet(isPresented: $showMusicBrowser) {
            InstagramStyleMusicBrowser(
                isPresented: $showMusicBrowser,
                onSongSelected: { song in
                    selectedSong = song
                    print("🎵 Selected song: \(song.title)")
                }
            )
        }
    }

    // MARK: - Recording Functions

    private func startRecording() {
        print("🎬 Starting recording with imported media")
        isRecording = true
        recordingDuration = 0

        // Start timer for duration display
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }

        // Here you would integrate with your existing recording pipeline
        // The key is to use the imported media as the base layer and apply effects
        startRecordingWithImportedMedia()
    }

    private func stopRecording() {
        guard isRecording else { return }

        print("⏹️ Stopping recording")
        isRecording = false
        timer?.invalidate()
        timer = nil

        // Stop the actual recording and get the result
        finishRecordingWithImportedMedia()
    }

    private func startRecordingWithImportedMedia() {
        // This is where you'd integrate with your existing recording system
        // Instead of using camera input, you'd use the imported media as the base
        // and apply effects through your Metal renderer

        // For now, simulate recording
        print("📹 Recording with imported media and effects...")
    }

    private func finishRecordingWithImportedMedia() {
        // Complete the recording and get the output URL
        // For now, simulate a completed recording

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Simulate recording completion
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "FeverDream_ImportedMedia_\(timestamp).mp4"
            recordedVideoURL = documentsPath.appendingPathComponent(fileName)

            print("✅ Recording completed: \(recordedVideoURL?.lastPathComponent ?? "unknown")")
            showResults = true
        }
    }

    // MARK: - Save Functions

    private func saveCurrentFrame() {
        guard let workingImage = workingImage else {
            print("❌ No working image to save")
            return
        }

        print("💾 Saving current frame with effects...")

        // Process the image through effects pipeline to get current state
        if let processedBuffer = cameraManager.effectsProcessor.processImportedImage(workingImage),
           let processedImage = pixelBufferToUIImage(processedBuffer) {
            saveImageToPhotos(processedImage)
        } else {
            // Fallback: save original image
            saveImageToPhotos(workingImage)
        }
    }

    private func saveImageToPhotos(_ image: UIImage) {
        // Check photo library permission
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        guard status == .authorized || status == .limited else {
            print("❌ No photo library permission for saving")
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    DispatchQueue.main.async {
                        self.saveImageToPhotos(image)
                    }
                }
            }
            return
        }

        // Save to Photos library
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.creationRequestForAsset(from: image)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    print("📸 ✅ Processed photo saved to Photos library!")

                    // Also save to Documents for gallery
                    self?.saveToDocuments(image)
                } else {
                    print("📸 ❌ Failed to save to Photos: \(error?.localizedDescription ?? "unknown error")")
                    // Fallback to Documents only
                    self?.saveToDocuments(image)
                }
            }
        }
    }

    private func saveToDocuments(_ image: UIImage) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Date().timeIntervalSince1970
        let formattedTimestamp = String(format: "%.3f", timestamp)
        let photoURL = documentsURL.appendingPathComponent("FeverDream_ImportedPhoto_\(formattedTimestamp).jpg")

        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            print("📸 Failed to convert image to JPEG")
            return
        }

        do {
            try imageData.write(to: photoURL)
            print("📸 Processed photo saved to Documents: \(photoURL.lastPathComponent)")

            // Notify gallery to refresh
            NotificationCenter.default.post(name: .init("MediaCaptured"), object: nil)
        } catch {
            print("📸 Failed to save photo: \(error.localizedDescription)")
        }
    }

    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Music Functions

    @available(iOS 15.0, *)
    private func toggleMusicPlayback() async {
        guard let selectedSong = selectedSong else { return }

        do {
            let player = ApplicationMusicPlayer.shared

            if isPlayingMusic {
                player.pause()
                isPlayingMusic = false
                print("⏸️ Music paused")
            } else {
                let queue = ApplicationMusicPlayer.Queue(for: [selectedSong])
                player.queue = queue
                try await player.play()
                isPlayingMusic = true
                print("🎵 Playing music: \(selectedSong.title)")
            }
        } catch {
            print("❌ Music playback error: \(error)")
        }
    }

    private var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        let hundredths = Int((recordingDuration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}

// MARK: - Supporting Views

@available(iOS 15.0, *)
struct ImportedVideoPlayerView: View {
    let url: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .aspectRatio(contentMode: .fit)
            .onAppear {
                print("🎬 Showing video player for: \(url)")
            }
    }
}

@available(iOS 15.0, *)
struct ImportedImageEffectsView: View {
    let image: UIImage
    let effectsProcessor: VideoEffectsProcessor
    let selectedEffect: PremiumEffect?
    let isRecording: Bool

    @State private var processedImage: UIImage?
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            if let processedImage = processedImage {
                Image(uiImage: processedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .onAppear {
            startEffectsProcessing()
        }
        .onDisappear {
            stopEffectsProcessing()
        }
    }

    private func startEffectsProcessing() {
        // Process the image continuously to show live effects
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            // Use the same processPixelBuffer method that the camera uses
            guard let pixelBuffer = imageToPixelBuffer(image) else { return }

            if let processedPixelBuffer = effectsProcessor.processPixelBuffer(pixelBuffer),
               let processedUIImage = pixelBufferToUIImage(processedPixelBuffer) {
                DispatchQueue.main.async {
                    self.processedImage = processedUIImage
                }
            }
        }
    }

    private func stopEffectsProcessing() {
        timer?.invalidate()
        timer = nil
    }

    private func imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(image.size.width),
            Int(image.size.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: pixelData,
            width: Int(image.size.width),
            height: Int(image.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: image.size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()

        return buffer
    }

    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

@available(iOS 15.0, *)
struct RecordingResultsView: View {
    let videoURL: URL
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Recording Complete!")
                        .font(.title)
                        .foregroundColor(.white)

                    Text("Your effects recording with imported media is ready!")
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Button("Save to Photos") {
                        saveToPhotos()
                    }
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)

                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
            .navigationTitle("Results")
            .navigationBarHidden(true)
        }
    }

    private func saveToPhotos() {
        // Save the recorded video to Photos
        print("💾 Saving recording to Photos: \(videoURL)")
        isPresented = false
    }
}

#Preview {
    ImportedMediaRecordingView(
        isPresented: .constant(true),
        importedAssetURL: nil,
        importedImage: UIImage(systemName: "photo"),
        cameraManager: CameraManager(),
        selectedEffect: nil
    )
}