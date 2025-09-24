import SwiftUI
import Photos
import PhotosUI
import AVKit
import Combine

struct VideoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mediaAssets: [PHAsset] = []
    @State private var isLoading = true
    @State private var selectedAsset: PHAsset?
    @State private var showMediaViewer = false
    @State private var mediaURL: URL?
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if authorizationStatus == .denied || authorizationStatus == .restricted {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))

                        Text("Photos Access Required")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("To view your DiscoShadow videos, please enable Photos access in Settings.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                } else if isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading videos...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                } else if mediaAssets.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))

                        Text("No DiscoShadow Media")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Capture some psychedelic photos and videos to see them here!")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(mediaAssets, id: \.localIdentifier) { asset in
                                MediaThumbnailView(asset: asset) {
                                    selectedAsset = asset
                                    if asset.mediaType == .video {
                                        loadVideoURL(for: asset)
                                    } else {
                                        loadPhotoURL(for: asset)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("DiscoShadow Gallery")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            checkPhotosPermission()
        }
        .fullScreenCover(isPresented: $showMediaViewer) {
            if let mediaURL = mediaURL, let selectedAsset = selectedAsset {
                if selectedAsset.mediaType == .video {
                    VideoPlayerView(videoURL: mediaURL) {
                        showMediaViewer = false
                        self.mediaURL = nil
                    }
                } else {
                    PhotoViewerView(photoURL: mediaURL) {
                        showMediaViewer = false
                        self.mediaURL = nil
                    }
                }
            }
        }
    }

    private func checkPhotosPermission() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch authorizationStatus {
        case .authorized, .limited:
            loadVideos()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.loadVideos()
                    } else {
                        self.isLoading = false
                    }
                }
            }
        case .denied, .restricted:
            isLoading = false
        @unknown default:
            isLoading = false
        }
    }

    private func loadVideos() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Fetch both photos and videos
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                           PHAssetMediaType.video.rawValue,
                                           PHAssetMediaType.image.rawValue)

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var allAssets: [PHAsset] = []

        assets.enumerateObjects { asset, _, _ in
            allAssets.append(asset)
        }

        DispatchQueue.main.async {
            self.mediaAssets = allAssets
            self.isLoading = false
        }
    }

    private func loadVideoURL(for asset: PHAsset) {
        print("🎬 Loading video for asset: \(asset.localIdentifier)")

        let options = PHVideoRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // Try to export the video to a temporary file
        PHImageManager.default().requestExportSession(forVideo: asset, options: options, exportPreset: AVAssetExportPresetHighestQuality) { exportSession, info in

            guard let exportSession = exportSession else {
                print("❌ Failed to create export session")
                DispatchQueue.main.async {
                    // Fallback to direct URL approach
                    self.loadVideoURLDirectly(for: asset)
                }
                return
            }

            // Create temporary file URL
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("temp_video_\(UUID().uuidString).mp4")

            exportSession.outputURL = tempURL
            exportSession.outputFileType = .mp4

            exportSession.exportAsynchronously {
                DispatchQueue.main.async {
                    switch exportSession.status {
                    case .completed:
                        print("✅ Video exported successfully to: \(tempURL)")
                        self.mediaURL = tempURL
                        self.showMediaViewer = true
                    case .failed:
                        print("❌ Export failed: \(String(describing: exportSession.error))")
                        // Fallback to direct URL approach
                        self.loadVideoURLDirectly(for: asset)
                    case .cancelled:
                        print("❌ Export cancelled")
                    default:
                        print("❌ Export status: \(exportSession.status.rawValue)")
                    }
                }
            }
        }
    }

    private func loadVideoURLDirectly(for asset: PHAsset) {
        print("🔄 Trying direct URL approach for asset: \(asset.localIdentifier)")

        let options = PHVideoRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            DispatchQueue.main.async {
                if let urlAsset = avAsset as? AVURLAsset {
                    print("✅ Got direct video URL: \(urlAsset.url)")
                    self.mediaURL = urlAsset.url
                    self.showMediaViewer = true
                } else if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Error loading video: \(error)")
                } else {
                    print("❌ Failed to get video URL from asset")
                    print("📊 Asset info: \(String(describing: info))")
                    print("📊 AVAsset type: \(String(describing: type(of: avAsset)))")
                }
            }
        }
    }

    private func loadPhotoURL(for asset: PHAsset) {
        print("📸 Loading photo for asset: \(asset.localIdentifier)")

        let options = PHImageRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // Create temporary file URL for photo
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("temp_photo_\(UUID().uuidString).jpg")

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, _, _, info in
            DispatchQueue.main.async {
                if let imageData = imageData {
                    do {
                        try imageData.write(to: tempURL)
                        print("✅ Photo exported successfully to: \(tempURL)")
                        self.mediaURL = tempURL
                        self.showMediaViewer = true
                    } catch {
                        print("❌ Failed to write photo data: \(error)")
                    }
                } else if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Error loading photo: \(error)")
                } else {
                    print("❌ Failed to get photo data from asset")
                }
            }
        }
    }
}

struct MediaThumbnailView: View {
    let asset: PHAsset
    let onTap: () -> Void
    @State private var thumbnail: UIImage?
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            Button(action: onTap) {
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 110, height: 110)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 110, height: 110)
                            .cornerRadius(8)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }

                    // Show play icon only for videos
                    if asset.mediaType == .video {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(radius: 3)
                                Spacer()
                            }
                            Spacer()
                        }

                        VStack {
                            Spacer()
                            HStack {
                                Text(formatDuration(asset.duration))
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                Spacer()
                            }
                            .padding(6)
                        }
                    }
                }
            }

            // Share button overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        shareVideo()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(6)
                Spacer()
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }

    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                self.thumbnail = image
            }
        }
    }

    private func shareVideo() {
        print("📤 Sharing video for asset: \(asset.localIdentifier)")

        let options = PHVideoRequestOptions()
        options.version = .original
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // Export video to temporary file for sharing
        PHImageManager.default().requestExportSession(forVideo: asset, options: options, exportPreset: AVAssetExportPresetHighestQuality) { exportSession, info in

            guard let exportSession = exportSession else {
                print("❌ Failed to create export session for sharing")
                return
            }

            // Create temporary file URL for sharing
            let tempDir = FileManager.default.temporaryDirectory
            let shareFileName = "DiscoShadow_\(Date().timeIntervalSince1970).mp4"
            let tempURL = tempDir.appendingPathComponent(shareFileName)

            exportSession.outputURL = tempURL
            exportSession.outputFileType = .mp4

            exportSession.exportAsynchronously {
                DispatchQueue.main.async {
                    switch exportSession.status {
                    case .completed:
                        print("✅ Video exported for sharing: \(tempURL)")
                        self.shareURL = tempURL
                        self.showShareSheet = true
                    case .failed:
                        print("❌ Share export failed: \(String(describing: exportSession.error))")
                    case .cancelled:
                        print("❌ Share export cancelled")
                    default:
                        print("❌ Share export status: \(exportSession.status.rawValue)")
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct VideoPlayerView: View {
    let videoURL: URL
    let onDismiss: () -> Void
    @State private var player: AVPlayer?
    @State private var playerReady = false
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player, playerReady {
                VideoPlayer(player: player)
                    .onAppear {
                        print("🎬 Starting video playback")
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                        player.seek(to: .zero)
                    }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))

                    Text("Loading video...")
                        .foregroundColor(.white)
                        .font(.caption)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Done") {
                        player?.pause()
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        print("🎮 Setting up player with URL: \(videoURL)")

        // Check if the file exists
        if videoURL.isFileURL {
            let fileExists = FileManager.default.fileExists(atPath: videoURL.path)
            print("📁 File exists at path: \(fileExists) - \(videoURL.path)")

            if !fileExists {
                print("❌ Video file does not exist!")
                return
            }
        }

        player = AVPlayer(url: videoURL)

        // Monitor player status
        player?.currentItem?.publisher(for: \.status)
            .sink { status in
                DispatchQueue.main.async {
                    switch status {
                    case .readyToPlay:
                        print("✅ Player ready to play")
                        playerReady = true
                    case .failed:
                        print("❌ Player failed: \(String(describing: player?.currentItem?.error))")
                        playerReady = false
                    case .unknown:
                        print("⏳ Player status unknown")
                        playerReady = false
                    @unknown default:
                        print("❓ Unknown player status: \(status)")
                        playerReady = false
                    }
                }
            }
            .store(in: &cancellables)

        // Add observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            onDismiss()
        }

        // Add observer for player failures
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ Player failed to play to end: \(error)")
            }
        }
    }

    private func cleanupPlayer() {
        player?.pause()
        player = nil
        playerReady = false
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
    }
}

struct PhotoViewerView: View {
    let photoURL: URL
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: photoURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } placeholder: {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
                .padding()
                Spacer()
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    VideoGalleryView()
}