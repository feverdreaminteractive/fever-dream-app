import SwiftUI
import AVKit
import Combine

struct VideoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mediaFiles: [MediaFile] = []
    @State private var isLoading = true
    @State private var selectedMediaFile: MediaFile?
    @State private var showMediaViewer = false
    @State private var isVideoPlayerReady = false
    @State private var viewRefreshTrigger = 0

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading Fever Dream media...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                } else if mediaFiles.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.6))

                        Text("No Fever Dream Media")
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
                            ForEach(mediaFiles.indices, id: \.self) { index in
                                let mediaFile = mediaFiles[index]
                                MediaFileThumbnailView(mediaFile: mediaFile) {
                                    print("🎯 Thumbnail tapped: \(mediaFile.url.lastPathComponent) (isVideo: \(mediaFile.isVideo))")
                                    selectedMediaFile = mediaFile
                                    // Always show viewer immediately - let it handle loading states
                                    showMediaViewer = true
                                    print("🎬 FullScreenCover requested for \(mediaFile.isVideo ? "video" : "photo")")
                                }
                                .id("\(index)-\(mediaFile.url.lastPathComponent)") // Force view refresh with index
                            }
                        }
                        .padding()
                        .id(viewRefreshTrigger) // Force grid refresh when trigger changes
                    }
                }
            }
            .navigationTitle("FΣVΣЯ DЯΣΛM")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadMediaFiles()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            loadMediaFiles()
        }
        .refreshable {
            loadMediaFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MediaCaptured"))) { _ in
            // Auto-refresh when new media is captured
            loadMediaFiles()
        }
        .onChange(of: selectedMediaFile) { newValue in
            if let newValue = newValue {
                print("📁 Selected media file changed to: \(newValue.url.lastPathComponent) (isVideo: \(newValue.isVideo))")
            } else {
                print("📁 Selected media file cleared (nil)")
            }
        }
        .fullScreenCover(isPresented: $showMediaViewer, onDismiss: {
            print("🎬 FullScreenCover dismissed")
        }) {
            if let selectedMediaFile = selectedMediaFile {
                if selectedMediaFile.isVideo {
                    VideoPlayerView(
                        videoURL: selectedMediaFile.url,
                        onPlayerReady: {
                            isVideoPlayerReady = true
                            print("🎬 FullScreenCover presenting video: \(selectedMediaFile.url.lastPathComponent)")
                        }
                    ) {
                        print("🎬 Video player dismissed")
                        showMediaViewer = false
                        self.selectedMediaFile = nil
                        isVideoPlayerReady = false
                    }
                } else {
                    PhotoViewerView(imageURL: selectedMediaFile.url) {
                        print("🎬 Photo viewer dismissed")
                        showMediaViewer = false
                        self.selectedMediaFile = nil
                    }
                    .onAppear {
                        print("🎬 FullScreenCover presenting photo: \(selectedMediaFile.url.lastPathComponent)")
                    }
                }
            } else {
                // Fallback for edge cases where selectedMediaFile becomes nil
                Color.black
                    .ignoresSafeArea()
                    .onAppear {
                        print("🚨 FullScreenCover presented but selectedMediaFile is nil!")
                        print("🎬 Showing fallback black screen, dismissing...")
                        showMediaViewer = false
                    }
            }
        }
    }

    private func loadMediaFiles() {
        isLoading = true

        DispatchQueue.global(qos: .background).async {  // Use background queue to avoid blocking
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            var files: [MediaFile] = []

            do {
                // Limit properties to reduce file system load
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: documentsURL,
                    includingPropertiesForKeys: [.contentModificationDateKey],  // Use modification date instead
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )

                // Filter for Fever Dream files (videos and photos)
                let feverDreamFiles = fileURLs.filter { url in
                    let fileName = url.lastPathComponent
                    return fileName.hasPrefix("FeverDream_") && (fileName.hasSuffix(".mp4") || fileName.hasSuffix(".jpg"))
                }

                // Sort by filename (which contains timestamp) - faster than file system queries
                let sortedFiles = feverDreamFiles.sorted { url1, url2 in
                    return url1.lastPathComponent > url2.lastPathComponent  // Newer first based on filename
                }

                // Limit to most recent 20 files for performance
                let recentFiles = Array(sortedFiles.prefix(20))

                for fileURL in recentFiles {
                    let isVideo = fileURL.pathExtension.lowercased() == "mp4"

                    // Verify file exists and is accessible
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        files.append(MediaFile(url: fileURL, isVideo: isVideo))
                        print("📁 Found \(isVideo ? "video" : "photo"): \(fileURL.lastPathComponent)")
                    } else {
                        print("⚠️ File not accessible: \(fileURL.lastPathComponent)")
                    }
                }

            } catch {
                print("Error loading media files: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.mediaFiles = files
                self.isLoading = false
                self.viewRefreshTrigger += 1 // Force view refresh
                print("📋 Loaded \(files.count) media files total")
                print("📋 Videos: \(files.filter { $0.isVideo }.count), Photos: \(files.filter { !$0.isVideo }.count)")
            }
        }
    }

    func refreshGallery() {
        loadMediaFiles()
    }
}

struct MediaFile: Equatable {
    let url: URL
    let isVideo: Bool
}

struct MediaFileThumbnailView: View {
    let mediaFile: MediaFile
    let onTap: () -> Void
    @State private var thumbnail: UIImage?
    @State private var showShareSheet = false
    @State private var isInteractive = false

    // Simple thumbnail cache to avoid regenerating with size limit
    private static var thumbnailCache: [String: UIImage] = [:]
    private static let maxCacheSize = 50 // Limit cache size to prevent memory issues

    var body: some View {
        ZStack {
            Button(action: {
                if isInteractive {
                    onTap()
                } else {
                    print("🚫 Thumbnail not yet interactive: \(mediaFile.url.lastPathComponent)")
                }
            }) {
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
                    if mediaFile.isVideo {
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
                    }
                }
            }

            // Share button overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        shareMedia()
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
            print("🔄 Thumbnail view appeared: \(mediaFile.url.lastPathComponent)")
            loadThumbnail()
        }
        .onChange(of: thumbnail) { newThumbnail in
            // Make interactive once thumbnail is loaded
            if newThumbnail != nil {
                isInteractive = true
                print("✅ Thumbnail loaded and interactive: \(mediaFile.url.lastPathComponent)")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [mediaFile.url])
        }
    }

    private func loadThumbnail() {
        let cacheKey = mediaFile.url.lastPathComponent

        // Check cache first
        if let cachedThumbnail = Self.thumbnailCache[cacheKey] {
            self.thumbnail = cachedThumbnail
            return
        }

        // Use higher priority queue for video thumbnails
        let queue: DispatchQoS.QoSClass = mediaFile.isVideo ? .userInitiated : .utility

        DispatchQueue.global(qos: queue).async {

            let thumbnailImage: UIImage?

            if mediaFile.isVideo {
                // Ensure video file exists before trying to generate thumbnail
                guard FileManager.default.fileExists(atPath: mediaFile.url.path) else {
                    DispatchQueue.main.async {
                        let placeholder = self.createPlaceholderThumbnail(isVideo: true)
                        Self.thumbnailCache[cacheKey] = placeholder
                        self.thumbnail = placeholder
                    }
                    return
                }
                thumbnailImage = generateVideoThumbnail(from: mediaFile.url)
            } else {
                thumbnailImage = loadImageThumbnail(from: mediaFile.url)
            }

            DispatchQueue.main.async {

                if let image = thumbnailImage {
                    // Manage cache size to prevent memory issues
                    if Self.thumbnailCache.count >= Self.maxCacheSize {
                        // Remove oldest entries (simple FIFO)
                        let keysToRemove = Array(Self.thumbnailCache.keys.prefix(10))
                        keysToRemove.forEach { Self.thumbnailCache.removeValue(forKey: $0) }
                    }
                    Self.thumbnailCache[cacheKey] = image
                    self.thumbnail = image
                } else {
                    // Use placeholder if loading failed
                    let placeholder = createPlaceholderThumbnail(isVideo: mediaFile.isVideo)
                    Self.thumbnailCache[cacheKey] = placeholder
                    self.thumbnail = placeholder
                }
            }
        }
    }

    private func loadImageThumbnail(from url: URL) -> UIImage? {
        // Load and resize image to avoid memory issues with autoreleasepool
        return autoreleasepool {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                return nil
            }

            // Create thumbnail-sized version efficiently
            let targetSize = CGSize(width: 110, height: 110)
            let renderer = UIGraphicsImageRenderer(size: targetSize)

            return renderer.image { _ in
                let image = UIImage(cgImage: cgImage)
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
    }

    private func generateVideoThumbnail(from videoURL: URL) -> UIImage? {
        return autoreleasepool {
            let asset = AVAsset(url: videoURL)

            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            // More aggressive performance optimizations
            imageGenerator.maximumSize = CGSize(width: 110, height: 110)
            imageGenerator.apertureMode = .cleanAperture

            // Use synchronous generation for faster thumbnails
            let time = CMTime(seconds: 0.0, preferredTimescale: 1) // Get first frame

            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                return UIImage(cgImage: cgImage)
            } catch {
                // Fallback: try a slightly later frame
                let fallbackTime = CMTime(seconds: 0.5, preferredTimescale: 1)
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: fallbackTime, actualTime: nil)
                    return UIImage(cgImage: cgImage)
                } catch {
                    return createPlaceholderThumbnail(isVideo: true)
                }
            }
        }
    }

    private func createPlaceholderThumbnail(isVideo: Bool) -> UIImage {
        let size = CGSize(width: 110, height: 110)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Draw a gradient placeholder
            let colors = [UIColor.purple.cgColor, UIColor.blue.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            // Add icon
            let iconName = isVideo ? "play.circle" : "photo"
            if let systemImage = UIImage(systemName: iconName)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                systemImage.draw(in: CGRect(x: size.width/2 - 15, y: size.height/2 - 15, width: 30, height: 30))
            }
        }
    }

    private func shareMedia() {
        showShareSheet = true
    }
}

struct VideoPlayerView: View {
    let videoURL: URL
    let onPlayerReady: (() -> Void)?
    let onDismiss: () -> Void
    @State private var player: AVPlayer?
    @State private var playerReady = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isSettingUp = false

    init(videoURL: URL, onPlayerReady: (() -> Void)? = nil, onDismiss: @escaping () -> Void) {
        self.videoURL = videoURL
        self.onPlayerReady = onPlayerReady
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Always show the video player, even if not ready
            if let player = player {
                VideoPlayer(player: player)
                    .opacity(playerReady ? 1.0 : 0.0) // Hide until ready
                    .onAppear {
                        if playerReady {
                            // Small delay to ensure player is fully ready
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                player.play()
                            }
                        }
                    }
                    .onDisappear {
                        player.pause()
                        player.seek(to: .zero)
                    }
                    .onChange(of: playerReady) { ready in
                        if ready {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                player.play()
                            }
                        }
                    }
            }

            // Show loading overlay until player is ready
            if !playerReady {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(2.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))

                    VStack(spacing: 8) {
                        Text("Loading Video...")
                            .foregroundColor(.white)
                            .font(.title2)
                            .fontWeight(.medium)

                        Text("Preparing psychedelic experience")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.body)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
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
            // Start setup immediately if not already done
            if player == nil && !isSettingUp {
                setupPlayer()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func setupPlayer() {
        // Prevent duplicate setup
        guard !isSettingUp && player == nil else {
            print("🚫 Player setup already in progress or completed")
            return
        }

        isSettingUp = true

        // Check if the file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("🚨 Video file does not exist at path: \(videoURL.path)")
            isSettingUp = false
            return
        }

        print("🎥 Setting up video player for: \(videoURL.lastPathComponent)")

        // Configure audio session for video playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔊 Audio session configured for video playback")
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
        }

        // Create player with optimized settings
        player = AVPlayer(url: videoURL)
        player?.automaticallyWaitsToMinimizeStalling = false // Prevent hanging

        // Monitor player status with timeout
        player?.currentItem?.publisher(for: \.status)
            .sink { status in
                DispatchQueue.main.async {
                    switch status {
                    case .readyToPlay:
                        self.playerReady = true
                        self.isSettingUp = false
                        self.onPlayerReady?()
                        print("✅ Video player ready: \(self.videoURL.lastPathComponent)")
                    case .failed:
                        self.playerReady = false
                        self.isSettingUp = false
                        print("❌ Video player failed: \(self.videoURL.lastPathComponent)")
                    case .unknown:
                        // Still loading, keep waiting
                        break
                    @unknown default:
                        self.playerReady = false
                        self.isSettingUp = false
                    }
                }
            }
            .store(in: &cancellables)

        // Add timeout to prevent indefinite hanging
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if self.isSettingUp && !self.playerReady {
                print("⏰ Video player setup timeout: \(self.videoURL.lastPathComponent)")
                self.isSettingUp = false
                // Force ready state to prevent infinite loading
                self.playerReady = true
            }
        }

        // Add observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            onDismiss()
        }
    }

    private func cleanupPlayer() {
        player?.pause()
        player = nil
        playerReady = false
        isSettingUp = false
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        print("🧹 Cleaned up video player: \(videoURL.lastPathComponent)")
    }
}

struct PhotoViewerView: View {
    let imageURL: URL
    let onDismiss: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))

                    Text("Loading photo...")
                        .foregroundColor(.white)
                        .font(.title3)
                }
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
        .onAppear {
            print("📸 Photo viewer appeared for: \(imageURL.lastPathComponent)")
            loadImage()
        }
        .onDisappear {
            print("📸 Photo viewer disappeared for: \(imageURL.lastPathComponent)")
        }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedImage = UIImage(contentsOfFile: imageURL.path)
            DispatchQueue.main.async {
                self.image = loadedImage
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
