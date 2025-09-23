import SwiftUI
import Photos
import PhotosUI
import AVKit
import Combine

struct VideoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var videos: [PHAsset] = []
    @State private var isLoading = true
    @State private var selectedVideo: PHAsset?
    @State private var showVideoPlayer = false
    @State private var videoURL: URL?
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
                } else if videos.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))

                        Text("No DiscoShadow Videos")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Record some psychedelic videos to see them here!")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(videos, id: \.localIdentifier) { video in
                                VideoThumbnailView(asset: video) {
                                    selectedVideo = video
                                    loadVideoURL(for: video)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("DiscoShadow Videos")
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
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let videoURL = videoURL {
                VideoPlayerView(videoURL: videoURL) {
                    showVideoPlayer = false
                    self.videoURL = nil
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
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var videoAssets: [PHAsset] = []

        assets.enumerateObjects { asset, _, _ in
            videoAssets.append(asset)
        }

        DispatchQueue.main.async {
            self.videos = videoAssets
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
                        self.videoURL = tempURL
                        self.showVideoPlayer = true
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
                    self.videoURL = urlAsset.url
                    self.showVideoPlayer = true
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
}

struct VideoThumbnailView: View {
    let asset: PHAsset
    let onTap: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
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
        .onAppear {
            loadThumbnail()
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

#Preview {
    VideoGalleryView()
}