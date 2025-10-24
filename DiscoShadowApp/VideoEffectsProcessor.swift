import CoreImage
import CoreVideo
import AVFoundation
import UIKit
import Metal
import MetalKit
import simd
import QuartzCore

class VideoEffectsProcessor: NSObject {
    // Metal rendering components
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var computePipelineState: MTLComputePipelineState?
    private var outputTexture: MTLTexture?

    // Add missing MetalRenderer instance
    var metalRenderer: MetalRenderer?

    // Audio manager for audio-reactive effects
    var audioManager: AudioManager?

    // Current selected effect
    var selectedEffect: PremiumEffect? {
        didSet {
            print("🎯 VideoEffectsProcessor: Selected effect changed to: \(selectedEffect?.rawValue ?? "nil")")
            metalRenderer?.activePremiumEffect = selectedEffect
        }
    }

    // Store manager for premium effects
    var storeManager: StoreManager? {
        didSet {
            metalRenderer?.storeManager = storeManager
        }
    }

    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              .cacheIntermediates: false])
    private var time: Float = 0.0
    private var frameCount: Int = 0
    private var textureCache: CVMetalTextureCache?

    // Psychedelic effect parameters - MEDIUM INTENSITY
    var intensity: Float = 2.5
    var glitchIntensityBase: Float = 1.5
    var warpAmountBase: Float = 2.0
    var chromaticAberrationBase: Float = 0.05

    // Adjustable warp magnitude (0.0 to 1.0)
    var warpMagnitude: Float = 1.0


    // Enhanced psychedelic parameters with automatic variation - never stops
    var colorVariation: Float {
        let currentTime = Float(CACurrentMediaTime())
        let sawtoothPeriod: Float = 6.0
        let sawtoothValue = (currentTime.truncatingRemainder(dividingBy: sawtoothPeriod)) / sawtoothPeriod
        let wave = sin(currentTime * 0.3) * 0.5 + 0.5
        return max(0.3, sawtoothValue * 0.7 + wave * 0.6) // Always at least 30% variation
    }

    var glitchIntensity: Float {
        let currentTime = Float(CACurrentMediaTime())
        let pulse = sin(currentTime * 2.0) * 0.5 + 0.5
        let fastFlicker = sin(currentTime * 8.0) * 0.2 + 0.8
        return 0.4 + pulse * 0.6 * fastFlicker // Never goes below 40%
    }

    var warpAmount: Float {
        let currentTime = Float(CACurrentMediaTime())
        let breathe = sin(currentTime * 0.8) * 0.5 + 0.5
        let shimmer = sin(currentTime * 3.0) * 0.3 + 0.7
        return 0.9 + breathe * 1.1 * shimmer // Continuous warping
    }

    var chromaticAberration: Float {
        let currentTime = Float(CACurrentMediaTime())
        let flicker = sin(currentTime * 5.0) * 0.5 + 0.5
        let drift = sin(currentTime * 0.7) * 0.4 + 0.6
        return 0.015 + flicker * 0.030 * drift // Continuous aberration
    }

    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not create default library")
        }

        self.device = device
        self.commandQueue = commandQueue
        self.library = library

        super.init()

        setupTextureCache()
        setupMetalRenderer()
        setupAudioManager()
    }

    private func setupMetalRenderer() {
        metalRenderer = MetalRenderer()
        metalRenderer?.activePremiumEffect = selectedEffect
        metalRenderer?.storeManager = storeManager
    }

    private func setupAudioManager() {
        print("🎵 VideoEffectsProcessor: Setting up AudioManager...")
        audioManager = AudioManager()
        audioManager?.startListening()
        print("🎵 VideoEffectsProcessor: AudioManager setup complete")
    }

    private func setupTextureCache() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        frameCount += 1
        time += 0.016

        // Get audio parameters
        let audioParams = audioManager?.getAudioParameters() ?? (0.0, 0.0, 0.0, 0.0)
        let totalAudio = audioParams.0 + audioParams.1 + audioParams.2 + audioParams.3

        // Debug audio values every 60 frames
        if frameCount % 60 == 0 {
            print("🎵 Audio Debug - Level: \(audioParams.0), Bass: \(audioParams.1), Mid: \(audioParams.2), Treble: \(audioParams.3), Total: \(totalAudio)")
        }

        // Audio threshold check
        let audioThreshold: Float = 0.01
        let audioBasedIntensity = totalAudio > audioThreshold ? intensity : intensity * 0.5

        // Use Metal renderer for disco shadow effects
        guard let metalRenderer = metalRenderer else {
            return pixelBuffer
        }

        // Update MetalRenderer properties with current values
        metalRenderer.intensity = audioBasedIntensity
        metalRenderer.colorVariation = colorVariation
        metalRenderer.glitchIntensity = glitchIntensity
        metalRenderer.warpAmount = warpAmount
        metalRenderer.chromaticAberration = chromaticAberration

        // Process frame with Metal renderer
        guard let outputTexture = metalRenderer.processFrame(
            pixelBuffer,
            audioLevel: audioParams.0,
            bassLevel: audioParams.1,
            midLevel: audioParams.2,
            trebleLevel: audioParams.3,
            warpMagnitude: warpMagnitude
        ) else {
            return pixelBuffer
        }

        // Convert Metal texture back to pixel buffer
        guard let outputBuffer = convertMetalTextureToPixelBuffer(outputTexture) else {
            return pixelBuffer
        }

        // Store the processed pixel buffer for photo capture
        currentProcessedPixelBuffer = outputBuffer

        return outputBuffer
    }

    private func convertMetalTextureToPixelBuffer(_ texture: MTLTexture) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard result == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)

        texture.getBytes(baseAddress!, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        return buffer
    }

    // MARK: - Photo Capture
    private var currentProcessedPixelBuffer: CVPixelBuffer?

    func capturePhotoFrame() {
        // Use the most recently processed pixel buffer (with effects applied)
        guard let pixelBuffer = currentProcessedPixelBuffer else {
            return
        }

        // Convert pixel buffer to UIImage
        guard let uiImage = pixelBufferToUIImage(pixelBuffer) else {
            return
        }

        // Save to Photos library
        savePhotoToLibrary(uiImage)
    }

    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func savePhotoToLibrary(_ image: UIImage) {
        // Save photo to Documents directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = Date().timeIntervalSince1970
        let formattedTimestamp = String(format: "%.3f", timestamp)
        let photoURL = documentsURL.appendingPathComponent("FeverDream_Photo_\(formattedTimestamp).jpg")

        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            print("📸 Failed to convert image to JPEG")
            return
        }

        do {
            try imageData.write(to: photoURL)
            print("📸 Photo saved to Documents: \(photoURL.lastPathComponent)")

            // Notify gallery to refresh
            NotificationCenter.default.post(name: .init("MediaCaptured"), object: nil)
        } catch {
            print("📸 Failed to save photo: \(error.localizedDescription)")
        }
    }

}
