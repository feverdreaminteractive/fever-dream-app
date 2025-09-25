import Metal
import MetalKit
import AVFoundation
import CoreVideo


class MetalRenderer: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var renderPipelineState: MTLRenderPipelineState?
    private var discoComputePipelineState: MTLComputePipelineState?
    private var crtDitherPipelineState: MTLComputePipelineState?
    private var crtSlitScanPipelineState: MTLComputePipelineState?
    private var opArtPipelineState: MTLComputePipelineState?
    private var opArtTrianglesPipelineState: MTLComputePipelineState?
    private var tunnelVisionPipelineState: MTLComputePipelineState?
    private var gridRoomPipelineState: MTLComputePipelineState?
    private var basicFeedbackPipelineState: MTLComputePipelineState?

    private var textureCache: CVMetalTextureCache?
    private var outputTexture: MTLTexture?
    private var feedbackTexture: MTLTexture? // For feedback effect

    // Slit scan frame buffer for CRT effect
    private var frameBuffer: [MTLTexture] = []
    private let frameBufferSize = 8 // Store 8 previous frames
    private var frameIndex = 0

    var time: Float = 0.0
    var intensity: Float = 1.0
    var colorVariation: Float = 0.5
    var glitchIntensity: Float = 0.8
    var warpAmount: Float = 1.2
    var chromaticAberration: Float = 0.015

    // Premium effects
    var activePremiumEffect: PremiumEffect?
    var storeManager: StoreManager?

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

        setupPipeline()
        setupTextureCache()
    }

    private func setupPipeline() {
        // Set up Disco Shadow effect
        guard let discoFunction = library.makeFunction(name: "discoShadowEffect") else {
            fatalError("Could not create disco shadow compute function")
        }

        do {
            discoComputePipelineState = try device.makeComputePipelineState(function: discoFunction)
        } catch {
            fatalError("Could not create disco shadow compute pipeline state: \(error)")
        }

        // Set up CRT Dither Glitch effect (Premium)
        guard let crtFunction = library.makeFunction(name: "crtDitherGlitchEffect") else {
            print("⚠️ CRT Dither Glitch effect not available")
            return
        }

        do {
            crtDitherPipelineState = try device.makeComputePipelineState(function: crtFunction)
        } catch {
            print("⚠️ Could not create CRT Dither Glitch compute pipeline state: \(error)")
        }

        // Set up CRT Slit Scan effect (Premium Enhanced)
        guard let crtSlitScanFunction = library.makeFunction(name: "crtSlitScanEffect") else {
            print("⚠️ CRT Slit Scan effect not available")
            return
        }

        do {
            crtSlitScanPipelineState = try device.makeComputePipelineState(function: crtSlitScanFunction)
            print("✅ CRT Slit Scan pipeline created successfully")
        } catch {
            print("⚠️ Could not create CRT Slit Scan compute pipeline state: \(error)")
        }

        // Set up Atari 1977 Retro effect (Premium)
        guard let opArtFunction = library.makeFunction(name: "atari1977RetroEffect") else {
            print("⚠️ Atari 1977 Retro effect not available")
            return
        }

        do {
            opArtPipelineState = try device.makeComputePipelineState(function: opArtFunction)
            print("✅ Atari 1977 Retro pipeline created successfully")
        } catch {
            print("⚠️ Could not create Atari 1977 Retro compute pipeline state: \(error)")
        }

        // Set up Op-Art Triangles effect (Premium)
        guard let opArtTrianglesFunction = library.makeFunction(name: "opArtTrianglesEffect") else {
            print("⚠️ Op-Art Triangles effect not available")
            return
        }

        do {
            opArtTrianglesPipelineState = try device.makeComputePipelineState(function: opArtTrianglesFunction)
            print("✅ Op-Art Triangles pipeline created successfully")
        } catch {
            print("⚠️ Could not create Op-Art Triangles compute pipeline state: \(error)")
        }

        // Set up Grid Room effect (Premium)
        guard let gridRoomFunction = library.makeFunction(name: "gridRoomEffect") else {
            print("⚠️ Grid Room effect not available")
            return
        }

        do {
            gridRoomPipelineState = try device.makeComputePipelineState(function: gridRoomFunction)
            print("✅ Grid Room pipeline created successfully")
        } catch {
            print("⚠️ Could not create Grid Room compute pipeline state: \(error)")
        }

        // Set up Basic Feedback effect (Premium)
        guard let basicFeedbackFunction = library.makeFunction(name: "basicFeedbackEffect") else {
            print("⚠️ Basic Feedback effect not available")
            return
        }

        do {
            basicFeedbackPipelineState = try device.makeComputePipelineState(function: basicFeedbackFunction)
            print("✅ Basic Feedback pipeline created successfully")
        } catch {
            print("⚠️ Could not create Basic Feedback compute pipeline state: \(error)")
        }

        // Set up render pipeline for display
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Could not create vertex/fragment functions")
        }

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction = vertexFunction
        renderPipelineDescriptor.fragmentFunction = fragmentFunction
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("Could not create render pipeline state: \(error)")
        }
    }

    private func setupTextureCache() {
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if result != kCVReturnSuccess {
            fatalError("Could not create texture cache")
        }
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer, audioLevel: Float = 0.0, bassLevel: Float = 0.0, midLevel: Float = 0.0, trebleLevel: Float = 0.0, warpMagnitude: Float = 1.0) -> MTLTexture? {
        guard let textureCache = textureCache else {
            return nil
        }

        // Check for premium effects first
        var selectedPipelineState: MTLComputePipelineState?

        if let premiumEffect = activePremiumEffect {
            // Use premium effect if available - ownership check is done outside render loop
            print("🎨 MetalRenderer: Using premium effect: \(premiumEffect)")
            switch premiumEffect {
            case .crtDitherGlitch:
                selectedPipelineState = crtSlitScanPipelineState ?? crtDitherPipelineState
                print("🎨 MetalRenderer: Selected CRT Slit Scan pipeline")
            case .bridgetRileyOpArt:
                selectedPipelineState = opArtPipelineState
                print("🎨 MetalRenderer: Selected Atari 1977 Retro pipeline")
            case .opArtTriangles:
                selectedPipelineState = opArtTrianglesPipelineState
                print("🎨 MetalRenderer: Selected Op-Art Triangles pipeline")
            case .tunnelVision:
                selectedPipelineState = gridRoomPipelineState
                print("🎨 MetalRenderer: Selected Grid Room pipeline")
            case .basicFeedback:
                selectedPipelineState = basicFeedbackPipelineState
                print("🎨 MetalRenderer: Selected Basic Feedback pipeline")
            default:
                // Fall back to default effect for unimplemented premium effects
                selectedPipelineState = discoComputePipelineState
                print("🎨 MetalRenderer: Fallback to default for unimplemented effect: \(premiumEffect)")
            }
        } else {
            // Use default Disco Shadow effect
            selectedPipelineState = discoComputePipelineState
            print("🎨 MetalRenderer: Using default Disco Shadow effect")
        }

        guard let pipelineState = selectedPipelineState else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var inputTextureRef: CVMetalTexture?
        let inputResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &inputTextureRef
        )

        guard inputResult == kCVReturnSuccess else {
            return nil
        }

        guard let inputTexture = CVMetalTextureGetTexture(inputTextureRef!) else {
            return nil
        }


        if outputTexture == nil ||
           outputTexture!.width != width ||
           outputTexture!.height != height {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderWrite, .shaderRead]
            outputTexture = device.makeTexture(descriptor: textureDescriptor)
        }

        // Create feedback texture for feedback effects
        if feedbackTexture == nil ||
           feedbackTexture!.width != width ||
           feedbackTexture!.height != height {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderWrite, .shaderRead]
            feedbackTexture = device.makeTexture(descriptor: textureDescriptor)
        }

        guard let outputTexture = outputTexture else {
            return nil
        }


        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }


        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

        // Special handling for feedback effect - needs feedback texture at index 2
        if activePremiumEffect == .basicFeedback, let feedbackTexture = feedbackTexture {
            computeEncoder.setTexture(feedbackTexture, index: 2)
        }

        var uniforms = DiscoUniforms(
            time: time,
            intensity: intensity,
            colorVariation: colorVariation,
            resolutionX: Float(width),
            resolutionY: Float(height),
            audioLevel: audioLevel,
            bassLevel: bassLevel,
            midLevel: midLevel,
            trebleLevel: trebleLevel,
            warpMagnitude: warpAmount,
            glitchIntensity: glitchIntensity,
            chromaticAberration: chromaticAberration
        )

        // Debug: Log audio parameters every 30 frames
        if Int(time * 60) % 30 == 0 {
        }

        let uniformsSize = MemoryLayout<DiscoUniforms>.size
        computeEncoder.setBytes(&uniforms, length: uniformsSize, index: 0)

        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )

        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()

        // For feedback effect, copy output to feedback texture for next frame
        if activePremiumEffect == .basicFeedback, let feedbackTexture = feedbackTexture {
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                commandBuffer.commit()
                time += 0.016
                return outputTexture
            }

            blitEncoder.copy(from: outputTexture,
                           sourceSlice: 0,
                           sourceLevel: 0,
                           sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                           sourceSize: MTLSize(width: width, height: height, depth: 1),
                           to: feedbackTexture,
                           destinationSlice: 0,
                           destinationLevel: 0,
                           destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))

            blitEncoder.endEncoding()
        }

        commandBuffer.commit()

        // Don't wait for completion - this was blocking the main thread
        // The texture will be available asynchronously
        time += 0.016

        return outputTexture
    }

    private func updateFrameBuffer(with texture: MTLTexture) {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderWrite, .shaderRead]

        // Create new texture for this frame
        guard let newTexture = device.makeTexture(descriptor: textureDescriptor) else { return }

        // Copy current frame to new texture
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }

        blitEncoder.copy(from: texture, to: newTexture)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Add to frame buffer
        if frameBuffer.count >= frameBufferSize {
            frameBuffer[frameIndex] = newTexture
        } else {
            frameBuffer.append(newTexture)
        }

        frameIndex = (frameIndex + 1) % frameBufferSize
    }

    func getRenderPipelineState() -> MTLRenderPipelineState? {
        return renderPipelineState
    }
}

struct DiscoUniforms {
    let time: Float
    let intensity: Float
    let colorVariation: Float
    let resolutionX: Float
    let resolutionY: Float
    let audioLevel: Float
    let bassLevel: Float
    let midLevel: Float
    let trebleLevel: Float
    let warpMagnitude: Float
    let glitchIntensity: Float
    let chromaticAberration: Float
}