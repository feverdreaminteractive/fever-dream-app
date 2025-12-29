import SwiftUI
import PhotosUI
import AVFoundation
import Photos

@available(iOS 15.0, *)
struct MediaImportView: View {
    @Binding var isPresented: Bool
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var importedAssetURL: URL?
    @State private var importedImage: UIImage?
    @State private var showEffectsRecorder = false

    // Snapshot state for fullScreenCover to avoid binding issues
    @State private var capturedImage: UIImage?
    @State private var capturedURL: URL?
    @State private var permissionStatus: PHAuthorizationStatus = .notDetermined

    // Pass in current effects setup
    let effectsProcessor: VideoEffectsProcessor?
    let selectedEffect: PremiumEffect?
    let cameraManager: CameraManager

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                // Import options view
                importOptionsView
            }
            .navigationTitle("Import Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedItems,
            maxSelectionCount: 1,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: selectedItems) { oldItems, newItems in
            print("📱 PhotosPicker selection changed")
            print("📱 Old items: \(oldItems.count), New items: \(newItems.count)")
            if !newItems.isEmpty {
                print("📱 First new item: \(newItems.first?.itemIdentifier ?? "unknown")")
            }
            processSelectedMedia(newItems)
        }
        .fullScreenCover(isPresented: $showEffectsRecorder) {
            ImportedMediaRecordingView(
                isPresented: $showEffectsRecorder,
                importedAssetURL: capturedURL,
                importedImage: capturedImage,
                cameraManager: cameraManager,
                selectedEffect: selectedEffect
            )
            .onAppear {
                print("🔍 MediaImportView fullScreenCover - passing captured image: \(capturedImage != nil ? "✓ \(capturedImage!.size)" : "✗")")
                print("🔍 MediaImportView fullScreenCover - passing captured URL: \(capturedURL?.absoluteString ?? "none")")
            }
        }
        .onDisappear {
            // Only clean up if we're actually dismissing, not showing full screen cover
            if !showEffectsRecorder {
                importedImage = nil
                importedAssetURL = nil
                print("🧹 MediaImportView: Cleaned up state on disappear")
            } else {
                print("🔄 MediaImportView: onDisappear called but keeping state for recording view")
            }
        }
        .onAppear {
                print("📱 MediaImportView appeared")
                checkPhotoLibraryPermission()
                print("📱 MediaImportView: importedAssetURL = \(importedAssetURL?.absoluteString ?? "nil")")
                print("📱 MediaImportView: importedImage = \(importedImage != nil ? "image with size \(importedImage!.size)" : "nil")")

                // Additional debug info
                if let image = importedImage {
                    print("📱 Image details: size=\(image.size), scale=\(image.scale)")
                }
                if let url = importedAssetURL {
                    let fileExists = FileManager.default.fileExists(atPath: url.path)
                    print("📱 Video file exists at path: \(fileExists)")
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        print("📱 Video file size: \(fileSize) bytes")
                    } catch {
                        print("📱 Could not read video file attributes: \(error)")
                    }
                }
            }
    }

    // MARK: - Import Options

    private var importOptionsView: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)

                VStack(spacing: 8) {
                    Text("Apply Effects to Your Media")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Import photos or videos and record with disco effects")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 16) {
                // Photo/Video picker button
                Button(action: {
                    print("📱 Photo picker button tapped")
                    print("📱 Permission status: \(permissionStatus.rawValue)")
                    if permissionStatus == .authorized || permissionStatus == .limited {
                        showPhotoPicker = true
                    } else {
                        print("❌ No photo library permission")
                        checkPhotoLibraryPermission()
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Choose Media to Record With")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
                }

                // Current effect info
                if let selectedEffect = selectedEffect {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.cyan)
                        Text("Effect: \(selectedEffect.name)")
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.cyan)
                        Text("Effect: Fever Dream (Default)")
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Processing Logic

    private func processSelectedMedia(_ items: [PhotosPickerItem]) {
        print("🔄 processSelectedMedia called with \(items.count) items")
        guard let item = items.first else {
            print("❌ No items selected")
            return
        }

        print("📋 Selected item content types: \(item.supportedContentTypes)")

        Task {
            do {
                let isImage = item.supportedContentTypes.contains(.image)
                let conformsToImage = item.supportedContentTypes.contains(where: { $0.conforms(to: .image) })
                let isPNG = item.supportedContentTypes.contains(where: { $0.identifier == "public.png" })
                let isJPEG = item.supportedContentTypes.contains(where: { $0.identifier == "public.jpeg" })
                let isJPG = item.supportedContentTypes.contains(where: { $0.identifier == "public.jpg" })
                let isHEIC = item.supportedContentTypes.contains(where: { $0.identifier == "public.heic" })
                let isBMP = item.supportedContentTypes.contains(where: { $0.identifier == "com.microsoft.bmp" })
                let isGIF = item.supportedContentTypes.contains(where: { $0.identifier == "com.compuserve.gif" })

                print("📸 Image detection: isImage=\(isImage), conformsToImage=\(conformsToImage), isPNG=\(isPNG), isJPEG=\(isJPEG), isHEIC=\(isHEIC)")

                if isImage || conformsToImage || isPNG || isJPEG || isJPG || isHEIC || isBMP || isGIF {
                    print("📸 Processing image...")
                    // Store photo for recording
                    // Try direct image loading first
                    do {
                        print("📸 Trying direct image loading...")
                        if let image = try await item.loadTransferable(type: Image.self) {
                            print("📸 SwiftUI Image loaded successfully")
                            // Convert SwiftUI Image to UIImage (this approach might not work directly)
                            // Let's try the data approach as fallback
                        }
                    } catch {
                        print("📸 Direct image loading failed: \(error)")
                    }

                    // Try data loading
                    do {
                        print("📸 Loading transferable data...")
                        let data = try await item.loadTransferable(type: Data.self)
                        print("📸 Data loaded: \(data?.count ?? 0) bytes")

                        if let data = data, let image = UIImage(data: data) {
                            print("📸 UIImage created successfully - size: \(image.size)")
                            await MainActor.run {
                                // Clear any previous video URL
                                importedAssetURL = nil
                                // Set the imported image
                                importedImage = image
                                print("🖼️ Photo imported for recording - size: \(image.size)")
                                print("📱 State updated - image: \(importedImage != nil), url: \(importedAssetURL != nil)")

                                // Small delay to ensure state is properly set
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    print("🔄 About to show effects recorder with image: \(self.importedImage?.size ?? CGSize.zero)")
                                    print("🔍 Pre-show state - image: \(self.importedImage != nil), URL: \(self.importedAssetURL != nil)")
                                    if self.importedImage != nil {
                                        // Capture state before showing fullScreenCover
                                        self.capturedImage = self.importedImage
                                        self.capturedURL = self.importedAssetURL
                                        print("📸 Captured state - image: \(self.capturedImage != nil), URL: \(self.capturedURL != nil)")
                                        print("✅ Image confirmed, showing effects recorder")
                                        showEffectsRecorder = true
                                    } else {
                                        print("❌ No image found, not showing recorder")
                                    }
                                }
                            }
                        } else {
                            print("❌ Failed to create UIImage from data")
                        }
                    } catch {
                        print("❌ Error loading image data: \(error)")
                    }
                } else if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    print("🎬 Processing video...")
                    do {
                        print("🎬 Loading video transferable...")
                        let transferable = try await item.loadTransferable(type: VideoFileTransferable.self)
                        print("🎬 Video transferable loaded: \(transferable != nil)")

                        if let url = transferable?.url {
                            print("🎬 Video URL obtained: \(url)")
                            await MainActor.run {
                                // Clear any previous image
                                importedImage = nil
                                // Set the imported video URL
                                importedAssetURL = url
                                let fileExists = FileManager.default.fileExists(atPath: url.path)
                                print("🎬 Video imported for recording: \(url)")
                                print("📁 Video file exists: \(fileExists)")
                                print("📱 State updated - image: \(importedImage != nil), url: \(importedAssetURL != nil)")

                                // Small delay to ensure state is properly set
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    print("🔄 About to show effects recorder with video URL: \(self.importedAssetURL?.absoluteString ?? "nil")")
                                    print("🔍 Pre-show state - image: \(self.importedImage != nil), URL: \(self.importedAssetURL != nil)")
                                    if self.importedAssetURL != nil {
                                        // Capture state before showing fullScreenCover
                                        self.capturedImage = self.importedImage
                                        self.capturedURL = self.importedAssetURL
                                        print("📸 Captured state - image: \(self.capturedImage != nil), URL: \(self.capturedURL != nil)")
                                        print("✅ Video confirmed, showing effects recorder")
                                        showEffectsRecorder = true
                                        print("🔄 showEffectsRecorder is now: \(showEffectsRecorder)")
                                    } else {
                                        print("❌ No video URL found, not showing recorder")
                                    }
                                }
                            }
                        } else {
                            print("❌ Failed to get video URL from transferable")
                        }
                    } catch {
                        print("❌ Error loading video: \(error)")
                    }
                } else {
                    print("❌ Unsupported content type: \(item.supportedContentTypes)")
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to load media: \(error.localizedDescription)")
                }
            }
        }

        // Don't auto-clear selection to prevent issues
        // selectedItems.removeAll()
    }

    // MARK: - Permission Handling

    private func checkPhotoLibraryPermission() {
        permissionStatus = PHPhotoLibrary.authorizationStatus()
        print("📱 Current photo library permission status: \(permissionStatus.rawValue)")

        switch permissionStatus {
        case .notDetermined:
            print("📱 Requesting photo library permission...")
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.permissionStatus = status
                    print("📱 Permission granted: \(status.rawValue)")
                }
            }
        case .denied, .restricted:
            print("❌ Photo library access denied")
        case .authorized, .limited:
            print("✅ Photo library access authorized")
        @unknown default:
            print("❓ Unknown permission status")
        }
    }
}

// MARK: - Video File Transfer

struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appending(component: "imported_video.mov")
            if FileManager.default.fileExists(atPath: copy.path) {
                _ = try FileManager.default.replaceItem(at: copy, withItemAt: received.file, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                try FileManager.default.copyItem(at: received.file, to: copy)
            }
            return Self.init(url: copy)
        }
    }
}

#Preview {
    MediaImportView(
        isPresented: .constant(true),
        effectsProcessor: nil,
        selectedEffect: nil,
        cameraManager: CameraManager()
    )
}