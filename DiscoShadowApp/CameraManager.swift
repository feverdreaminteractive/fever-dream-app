import AVFoundation
import UIKit
import Combine
import Photos
import CoreVideo

class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var shouldShowAlertView = false
    @Published var alertError: AlertError = AlertError()
    @Published var isRecording = false
    @Published var warpMagnitude: Float = 1.0 {
        didSet {
            effectsProcessor.warpMagnitude = warpMagnitude
        }
    }

    let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "session queue")

    var videoDataOutputDelegate: AVCaptureVideoDataOutputSampleBufferDelegate? {
        didSet {
            print("🔄 Video data output delegate changed, updating...")
            updateVideoDataOutputDelegate()
        }
    }
    let effectsProcessor = VideoEffectsProcessor()

    // Recording components
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private let recordingQueue = DispatchQueue(label: "recording queue", qos: .userInitiated)

    override init() {
        super.init()
        self.checkPermissions()
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

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get the camera device")
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

        // Don't set delegate here - it will be set when videoDataOutputDelegate property is assigned
        print("📊 Video data output configured (delegate will be set later)")
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]

        guard session.canAddOutput(videoDataOutput) else {
            print("Couldn't add video data output to the session")
            return
        }
        session.addOutput(videoDataOutput)

        if let connection = videoDataOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
    }

    private func updateVideoDataOutputDelegate() {
        sessionQueue.async {
            print("🔗 Actually setting video data output delegate: \(self.videoDataOutputDelegate != nil)")
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

    func startRecording() {
        recordingQueue.async {
            guard !self.isRecording else { return }

            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let outputURL = documentsURL.appendingPathComponent("DiscoShadow_\(Date().timeIntervalSince1970).mov")
            self.recordingURL = outputURL

            do {
                // Create asset writer
                self.assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

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

                // Add input to writer
                if let videoInput = self.assetWriterVideoInput,
                   let writer = self.assetWriter,
                   writer.canAdd(videoInput) {
                    writer.add(videoInput)
                }

                // Start writing
                if let writer = self.assetWriter, writer.startWriting() {
                    writer.startSession(atSourceTime: CMTime.zero)

                    DispatchQueue.main.async {
                        self.isRecording = true
                    }
                }
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    func stopRecording() {
        recordingQueue.async {
            guard self.isRecording else { return }

            DispatchQueue.main.async {
                self.isRecording = false
            }

            self.assetWriterVideoInput?.markAsFinished()
            self.assetWriter?.finishWriting {
                DispatchQueue.main.async {
                    if let outputURL = self.recordingURL {
                        self.saveVideoToPhotos(url: outputURL)
                    }
                }

                // Clean up
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.assetWriterPixelBufferAdaptor = nil
            }
        }
    }

    func writeVideoFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording,
              let assetWriter = assetWriter,
              let videoInput = assetWriterVideoInput,
              let adaptor = assetWriterPixelBufferAdaptor,
              assetWriter.status == .writing else { return }

        recordingQueue.async {
            if videoInput.isReadyForMoreMediaData {
                let presentationTime = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
    }

    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("Photos access denied")
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to Photos successfully")
                    } else if let error = error {
                        print("Failed to save video: \(error.localizedDescription)")
                    }

                    // Clean up temporary file
                    try? FileManager.default.removeItem(at: url)
                }
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