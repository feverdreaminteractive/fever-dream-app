import AVFoundation
import UIKit
import Combine
import Photos
import CoreVideo

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
    @Published var zoomFactor: CGFloat = 1.0

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
            print("Failed to get the camera device for position: \(cameraPosition)")
            return
        }

        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Failed to create video device input: \(error)")
            return
        }

        guard session.canAddInput(videoDeviceInput) else {
            print("Couldn't add video device input to the session")
            return
        }
        session.addInput(videoDeviceInput)

        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]

        guard session.canAddOutput(videoDataOutput) else {
            print("Couldn't add video data output to the session")
            return
        }
        session.addOutput(videoDataOutput)

        // Add photo output
        guard session.canAddOutput(photoOutput) else {
            print("Couldn't add photo output to the session")
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
            guard !self.isRecording else {
                print("Cannot switch camera while recording")
                return
            }

            // Remove current input
            if let currentInput = self.videoDeviceInput {
                self.session.removeInput(currentInput)
            }

            // Toggle camera position
            DispatchQueue.main.async {
                self.isUsingFrontCamera.toggle()
            }

            // Get new camera
            let newPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
            guard let newVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                print("Failed to get camera for position: \(newPosition)")
                return
            }

            do {
                let newVideoInput = try AVCaptureDeviceInput(device: newVideoDevice)

                if self.session.canAddInput(newVideoInput) {
                    self.session.addInput(newVideoInput)
                    self.videoDeviceInput = newVideoInput

                    // Update video connection mirroring for front camera
                    if let connection = self.videoDataOutput.connection(with: .video) {
                        connection.videoOrientation = .portrait
                        connection.isVideoMirrored = (newPosition == .front)
                    }

                    print("✅ Switched to \(newPosition == .front ? "front" : "back") camera")
                } else {
                    print("❌ Cannot add new camera input")
                }
            } catch {
                print("❌ Error creating camera input: \(error)")
            }
        }
    }

    func startRecording() {
        print("🎬 Starting recording...")
        recordingQueue.async {
            guard !self.isRecording else {
                print("❌ Already recording, ignoring start request")
                return
            }

            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let outputURL = documentsURL.appendingPathComponent("DiscoShadow_\(Date().timeIntervalSince1970).mp4")
            self.recordingURL = outputURL
            print("📁 Recording to: \(outputURL)")

            do {
                // Create asset writer
                self.assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
                print("✅ Asset writer created")

                // Configure video input
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 1080,
                    AVVideoHeightKey: 1920,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 6000000,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    ]
                ]

                self.assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                self.assetWriterVideoInput?.expectsMediaDataInRealTime = true
                print("✅ Video input created")

                // Configure audio input with simpler settings
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100.0,
                    AVNumberOfChannelsKey: 1,  // Mono for simplicity
                    AVEncoderBitRateKey: 64000  // Lower bitrate
                ]

                self.assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                self.assetWriterAudioInput?.expectsMediaDataInRealTime = true
                print("✅ Audio input created")

                // Create pixel buffer adaptor
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: self.assetWriterVideoInput!,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: 1080,
                        kCVPixelBufferHeightKey as String: 1920,
                    ]
                )
                self.assetWriterPixelBufferAdaptor = adaptor
                print("✅ Pixel buffer adaptor created")

                // Add inputs to writer
                if let videoInput = self.assetWriterVideoInput,
                   let writer = self.assetWriter,
                   writer.canAdd(videoInput) {
                    writer.add(videoInput)
                    print("✅ Video input added to writer")
                } else {
                    print("❌ Cannot add video input to writer")
                    return
                }

                if let audioInput = self.assetWriterAudioInput,
                   let writer = self.assetWriter,
                   writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    print("✅ Audio input added to writer")
                } else {
                    print("❌ Cannot add audio input to writer")
                    return
                }

                // Start writing
                if let writer = self.assetWriter, writer.startWriting() {
                    self.recordingStartTime = CMTime.zero
                    self.frameCounter = 0
                    writer.startSession(atSourceTime: CMTime.zero)
                    print("✅ Asset writer started writing")

                    // Keep AudioManager running for visual effects during recording

                    DispatchQueue.main.async {
                        self.isRecording = true
                        print("✅ Recording started - visual effects should continue working")
                    }
                } else {
                    print("❌ Failed to start asset writer")
                }
            } catch {
                print("❌ Failed to start recording: \(error)")
            }
        }
    }

    func stopRecording() {
        print("🛑 Stopping recording...")
        recordingQueue.async {
            guard self.isRecording else {
                print("❌ Not recording, ignoring stop request")
                return
            }

            DispatchQueue.main.async {
                self.isRecording = false
                print("✅ Recording stopped - visual effects continue")
            }

            self.assetWriterVideoInput?.markAsFinished()
            self.assetWriterAudioInput?.markAsFinished()
            print("✅ Video and audio inputs marked as finished")

            self.assetWriter?.finishWriting {
                print("✅ Asset writer finished writing")

                // AudioManager continues running for visual effects

                DispatchQueue.main.async {
                    if let outputURL = self.recordingURL {
                        print("💾 Saving video to Photos: \(outputURL)")
                        self.saveVideoToPhotos(url: outputURL)
                    } else {
                        print("❌ No recording URL to save")
                    }
                }

                // Clean up
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.assetWriterAudioInput = nil
                self.assetWriterPixelBufferAdaptor = nil
                self.recordingStartTime = nil
                self.frameCounter = 0
                print("🧹 Recording cleanup completed")
            }
        }
    }

    func writeVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else {
            print("📹 Not recording, skipping frame")
            return
        }

        guard let assetWriter = assetWriter else {
            print("❌ Asset writer is nil")
            return
        }

        guard let videoInput = assetWriterVideoInput else {
            print("❌ Video input is nil")
            return
        }

        guard let adaptor = assetWriterPixelBufferAdaptor else {
            print("❌ Pixel buffer adaptor is nil")
            return
        }

        guard assetWriter.status == .writing else {
            print("❌ Asset writer status: \(assetWriter.status.rawValue)")
            return
        }

        recordingQueue.async {
            if videoInput.isReadyForMoreMediaData {
                // Use frame-based timing for consistent video playback (30 FPS)
                let presentationTime = CMTime(value: self.frameCounter, timescale: 30)

                let success = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                if !success {
                    print("❌ Failed to append video frame #\(self.frameCounter)")
                } else {
                    self.frameCounter += 1
                    // Log every 30 frames to avoid spam
                    if self.frameCounter % 30 == 0 {
                        print("✅ Video frame #\(self.frameCounter) written")
                    }
                }
            } else {
                print("⏸️ Video input not ready for more data")
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
                    print("❌ Failed to append audio sample buffer")
                }
                // Only log failures to reduce verbosity
            } else {
                print("⏸️ Audio input not ready for more data")
            }
        }
    }

    // MARK: - RecordingAudioDelegate
    func didReceiveAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writeAudioFrame(sampleBuffer)
    }

    private func saveVideoToPhotos(url: URL) {
        print("💾 Requesting Photos authorization...")
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            print("📸 Photos authorization status: \(status.rawValue)")
            switch status {
            case .authorized, .limited:
                print("✅ Photos access granted, saving video...")
                PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    print("📸 Created asset creation request")
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            print("✅ Video saved to Photos successfully!")
                            // Show user feedback
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                // Could add a success notification here
                            }
                        } else if let error = error {
                            print("❌ Failed to save video: \(error.localizedDescription)")
                        }

                        // Clean up temporary file
                        do {
                            try FileManager.default.removeItem(at: url)
                            print("🗑️ Temporary file cleaned up")
                        } catch {
                            print("⚠️ Failed to clean up temporary file: \(error)")
                        }
                    }
                }
            case .denied, .restricted:
                print("❌ Photos access denied or restricted")
            case .notDetermined:
                print("⚠️ Photos access not determined")
            @unknown default:
                print("⚠️ Unknown Photos authorization status")
            }
        }
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
                print("Error setting zoom: \(error)")
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
                print("Error setting focus and exposure: \(error)")
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
            print("❌ Photo capture error: \(String(describing: error))")
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            print("❌ Failed to get photo data")
            return
        }

        guard let uiImage = UIImage(data: imageData) else {
            print("❌ Failed to create UIImage from photo data")
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
        print("💾 Saving photo to library...")
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited:
                PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    print("📸 Created photo asset creation request")
                } completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            print("✅ Photo saved to library successfully!")
                        } else if let error = error {
                            print("❌ Failed to save photo: \(error.localizedDescription)")
                        }
                    }
                }
            case .denied, .restricted:
                print("❌ Photos access denied for photo saving")
            case .notDetermined:
                print("⚠️ Photos access not determined for photo saving")
            @unknown default:
                print("⚠️ Unknown Photos authorization status for photo saving")
            }
        }
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