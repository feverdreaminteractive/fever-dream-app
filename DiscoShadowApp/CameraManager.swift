import AVFoundation
import UIKit
import Combine
import CoreVideo
import Photos

class CameraManager: NSObject, ObservableObject, RecordingAudioDelegate, AVCapturePhotoCaptureDelegate {
    @Published var isSessionRunning = false
    @Published var shouldShowAlertView = false
    @Published var alertError: AlertError = AlertError()
    @Published var isRecording = false
    @Published var warpMagnitude: Float = 1.0 {
        didSet {
            effectsProcessor.warpMagnitude = warpMagnitude
        }
    }
    @Published var isUsingFrontCamera = false
    @Published var isSwitchingCamera = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isTorchOn = false

    let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "session queue")

    var videoDataOutputDelegate: AVCaptureVideoDataOutputSampleBufferDelegate? {
        didSet {
            updateVideoDataOutputDelegate()
        }
    }

    let effectsProcessor = VideoEffectsProcessor()

    // Premium effects support
    func setSelectedEffect(_ effect: PremiumEffect?) {
        print("📷 CameraManager: Setting effect to: \(effect?.rawValue ?? "nil")")
        effectsProcessor.selectedEffect = effect
    }

    func setStoreManager(_ storeManager: StoreManager) {
        effectsProcessor.storeManager = storeManager
    }

    // Recording components
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterAudioInput: AVAssetWriterInput?
    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private let recordingQueue = DispatchQueue(label: "recording queue", qos: .userInitiated)
    private var recordingStartTime: CMTime?
    private var frameCounter: Int64 = 0

    override init() {
        super.init()
        self.checkPermissions()
        // Set up AudioManager delegate for unified audio pipeline
        effectsProcessor.audioManager?.recordingAudioDelegate = self
        sessionQueue.async {
            self.configureSession()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    self.alertError = AlertError(title: "Camera Access", message: "Camera access is required to use this app", primaryButtonTitle: "Settings", secondaryButtonTitle: nil) {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    } secondaryAction: {}
                    self.shouldShowAlertView = true
                }
                self.sessionQueue.resume()
            }
        default:
            alertError = AlertError(title: "Camera Access", message: "Camera access is required to use this app", primaryButtonTitle: "Settings", secondaryButtonTitle: nil) {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            } secondaryAction: {}
            shouldShowAlertView = true
        }
    }

    private func configureSession() {
        session.sessionPreset = .high

        let cameraPosition: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
            return
        }

        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            return
        }

        guard session.canAddInput(videoDeviceInput) else {
            return
        }
        session.addInput(videoDeviceInput)

        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]

        guard session.canAddOutput(videoDataOutput) else {
            return
        }
        session.addOutput(videoDataOutput)

        // Add photo output
        guard session.canAddOutput(photoOutput) else {
            return
        }
        session.addOutput(photoOutput)

        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            // Mirror front camera for natural selfie experience
            if isUsingFrontCamera {
                connection.isVideoMirrored = true
            }
        }

        // Configure photo output
        if let photoConnection = photoOutput.connection(with: .video) {
            photoConnection.videoOrientation = .portrait
            if isUsingFrontCamera {
                photoConnection.isVideoMirrored = true
            }
        }
    }

    private func updateVideoDataOutputDelegate() {
        sessionQueue.async {
            self.videoDataOutput.setSampleBufferDelegate(
                self.videoDataOutputDelegate,
                queue: DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
            )
        }
    }



    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    func switchCamera() {
        sessionQueue.async {
            guard !self.isRecording && !self.isSwitchingCamera else {
                print("❌ Cannot switch camera while recording or already switching")
                return
            }

            // Set switching state
            DispatchQueue.main.async {
                self.isSwitchingCamera = true
            }

            // Begin configuration to batch changes
            self.session.beginConfiguration()

            // Calculate the new position first
            let newPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .back : .front

            // Get new camera device
            guard let newVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                print("❌ Failed to get camera device for position: \(newPosition)")
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.isSwitchingCamera = false
                }
                return
            }

            do {
                let newVideoInput = try AVCaptureDeviceInput(device: newVideoDevice)

                // Remove current input
                if let currentInput = self.videoDeviceInput {
                    self.session.removeInput(currentInput)
                }

                // Add new input
                if self.session.canAddInput(newVideoInput) {
                    self.session.addInput(newVideoInput)
                    self.videoDeviceInput = newVideoInput

                    // Update video connection mirroring for front camera
                    if let connection = self.videoDataOutput.connection(with: .video) {
                        connection.videoOrientation = .portrait
                        connection.isVideoMirrored = (newPosition == .front)
                    }

                    // Commit all changes at once
                    self.session.commitConfiguration()

                    // Update state on main thread after successful switch
                    DispatchQueue.main.async {
                        self.isUsingFrontCamera.toggle()
                        self.isSwitchingCamera = false
                        // Turn off torch when switching cameras (front camera doesn't have torch)
                        if newPosition == .front {
                            self.isTorchOn = false
                        }
                        print("✅ Camera switched to: \(newPosition == .front ? "front" : "back")")
                    }

                } else {
                    print("❌ Cannot add new camera input")
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.isSwitchingCamera = false
                    }
                }
            } catch {
                print("❌ Failed to create camera input: \(error.localizedDescription)")
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.isSwitchingCamera = false
                }
            }
        }
    }

    func startRecording() {
        print("🎬 startRecording() called")
        recordingQueue.async {
            guard !self.isRecording else {
                print("🎬 Already recording, ignoring startRecording()")
                return
            }

            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let timestamp = Date().timeIntervalSince1970
            let formattedTimestamp = String(format: "%.3f", timestamp)
            let outputURL = documentsURL.appendingPathComponent("FeverDream_DiscoShadow_\(formattedTimestamp).mp4")
            self.recordingURL = outputURL
            print("🎬 Starting recording to: \(outputURL.path)")

            do {
                // Create asset writer
                self.assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

                // Configure video input - optimized for smaller file sizes and faster loading
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 720,  // Reduced from 1080
                    AVVideoHeightKey: 1280, // Reduced from 1920
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 2500000, // Reduced from 6000000
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                        AVVideoMaxKeyFrameIntervalKey: 30, // Add keyframe interval for better compression
                        AVVideoQualityKey: 0.7 // Slightly reduce quality for smaller files
                    ]
                ]

                self.assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                self.assetWriterVideoInput?.expectsMediaDataInRealTime = true

                // Lock video to portrait orientation
                self.assetWriterVideoInput?.transform = CGAffineTransform(rotationAngle: 0)

                // Configure audio input with simpler settings
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100.0,
                    AVNumberOfChannelsKey: 1,  // Mono for simplicity
                    AVEncoderBitRateKey: 64000  // Lower bitrate
                ]

                self.assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                self.assetWriterAudioInput?.expectsMediaDataInRealTime = true

                // Create pixel buffer adaptor - updated for new resolution
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: self.assetWriterVideoInput!,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: 720,  // Match video settings
                        kCVPixelBufferHeightKey as String: 1280, // Match video settings
                    ]
                )
                self.assetWriterPixelBufferAdaptor = adaptor

                // Add inputs to writer
                if let videoInput = self.assetWriterVideoInput,
                   let writer = self.assetWriter,
                   writer.canAdd(videoInput) {
                    writer.add(videoInput)
                } else {
                    return
                }

                if let audioInput = self.assetWriterAudioInput,
                   let writer = self.assetWriter,
                   writer.canAdd(audioInput) {
                    writer.add(audioInput)
                } else {
                    return
                }

                // Start writing
                if let writer = self.assetWriter, writer.startWriting() {
                    self.recordingStartTime = CMTime.zero
                    self.frameCounter = 0
                    writer.startSession(atSourceTime: CMTime.zero)

                    // Keep AudioManager running for visual effects during recording

                    DispatchQueue.main.async {
                        self.isRecording = true
                    }
                } else {
                }
            } catch {
            }
        }
    }

    func stopRecording() {
        print("🎬 stopRecording() called")
        recordingQueue.async {
            guard self.isRecording else {
                print("🎬 Not recording, ignoring stopRecording()")
                return
            }

            DispatchQueue.main.async {
                self.isRecording = false
            }

            self.assetWriterVideoInput?.markAsFinished()
            self.assetWriterAudioInput?.markAsFinished()

            self.assetWriter?.finishWriting {

                // AudioManager continues running for visual effects

                DispatchQueue.main.async {
                    if let outputURL = self.recordingURL {
                        print("🎬 Recording finished, saving video: \(outputURL.lastPathComponent)")
                        self.saveVideoToPhotos(url: outputURL)
                    } else {
                        print("❌ Recording finished but recordingURL is nil!")
                    }
                }

                // Clean up
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.assetWriterAudioInput = nil
                self.assetWriterPixelBufferAdaptor = nil
                self.recordingStartTime = nil
                self.frameCounter = 0
            }
        }
    }

    func writeVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else {
            return
        }

        guard let assetWriter = assetWriter else {
            return
        }

        guard let videoInput = assetWriterVideoInput else {
            return
        }

        guard let adaptor = assetWriterPixelBufferAdaptor else {
            return
        }

        guard assetWriter.status == .writing else {
            return
        }

        recordingQueue.async {
            if videoInput.isReadyForMoreMediaData {
                // Use frame-based timing for consistent video playback (30 FPS)
                let presentationTime = CMTime(value: self.frameCounter, timescale: 30)

                let success = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                if !success {
                } else {
                    self.frameCounter += 1
                    // Log every 30 frames to avoid spam
                    if self.frameCounter % 30 == 0 {
                    }
                }
            } else {
            }
        }
    }

    func writeAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let assetWriter = assetWriter,
              let audioInput = assetWriterAudioInput,
              assetWriter.status == .writing else {
            return
        }

        recordingQueue.async {
            if audioInput.isReadyForMoreMediaData {
                let success = audioInput.append(sampleBuffer)
                if !success {
                }
                // Only log failures to reduce verbosity
            } else {
            }
        }
    }

    // MARK: - RecordingAudioDelegate
    func didReceiveAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writeAudioFrame(sampleBuffer)
    }

    private func saveVideoToPhotos(url: URL) {
        // Keep video in Documents directory for app gallery
        print("🎥 Video saved to Documents: \(url.lastPathComponent)")

        // Notify gallery to refresh
        NotificationCenter.default.post(name: .init("MediaCaptured"), object: nil)
    }

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async {
            guard let device = self.videoDeviceInput?.device else { return }

            do {
                try device.lockForConfiguration()

                let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clampedFactor

                DispatchQueue.main.async {
                    self.zoomFactor = clampedFactor
                }

                device.unlockForConfiguration()
            } catch {
            }
        }
    }

    func setFocusAndExposure(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.videoDeviceInput?.device else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }

                device.unlockForConfiguration()
            } catch {
            }
        }
    }

    func toggleTorch() {
        sessionQueue.async {
            guard let device = self.videoDeviceInput?.device else { return }

            guard device.hasTorch && device.isTorchAvailable else {
                print("🔦 Torch not available on this device")
                return
            }

            do {
                try device.lockForConfiguration()

                if self.isTorchOn {
                    device.torchMode = .off
                } else {
                    try device.setTorchModeOn(level: 1.0)
                }

                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.isTorchOn.toggle()
                    print("🔦 Torch turned \(self.isTorchOn ? "on" : "off")")
                }
            } catch {
                print("🔦 Error toggling torch: \(error.localizedDescription)")
            }
        }
    }

    func setTorchLevel(_ level: Float) {
        sessionQueue.async {
            guard let device = self.videoDeviceInput?.device else { return }

            guard device.hasTorch && device.isTorchAvailable else { return }

            do {
                try device.lockForConfiguration()

                let clampedLevel = max(0.0, min(level, 1.0))
                if clampedLevel > 0.0 {
                    try device.setTorchModeOn(level: clampedLevel)
                    DispatchQueue.main.async {
                        self.isTorchOn = true
                    }
                } else {
                    device.torchMode = .off
                    DispatchQueue.main.async {
                        self.isTorchOn = false
                    }
                }

                device.unlockForConfiguration()
            } catch {
                print("🔦 Error setting torch level: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        // Capture the current frame from the video output (which has effects applied)
        effectsProcessor.capturePhotoFrame()
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            return
        }

        guard let uiImage = UIImage(data: imageData) else {
            return
        }

        // Apply effects to the photo if desired
        let processedImage = applyEffectsToPhoto(uiImage)

        // Save to Photos
        savePhotoToLibrary(processedImage)
    }

    private func applyEffectsToPhoto(_ image: UIImage) -> UIImage {
        // For now, return the original image
        // In the future, you could apply psychedelic effects to photos too
        return image
    }

    private func savePhotoToLibrary(_ image: UIImage) {
        // Managed photos functionality disabled
        print("📸 Photo captured (not saved to photo library)")
    }
}

struct AlertError {
    var title: String = ""
    var message: String = ""
    var primaryButtonTitle: String = "Accept"
    var secondaryButtonTitle: String?
    var primaryAction: (() -> ())?
    var secondaryAction: (() -> ())?

    init(title: String = "", message: String = "", primaryButtonTitle: String = "Accept", secondaryButtonTitle: String? = nil, primaryAction: (() -> ())? = nil, secondaryAction: (() -> ())? = nil) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryAction = secondaryAction
    }
}