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
    private var badTVPipelineState: MTLComputePipelineState?
    private var strobePipelineState: MTLComputePipelineState?
    private var convergencePipelineState: MTLComputePipelineState?
    private var tunnelPipelineState: MTLComputePipelineState?
    private var analogGlitchPipelineState: MTLComputePipelineState?
    private var kaleidoscopePipelineState: MTLComputePipelineState?

    private var textureCache: CVMetalTextureCache?
    private var outputTexture: MTLTexture?
    private var feedbackTexture: MTLTexture? // For feedback effect
    private var strobeStateTexture: MTLTexture? // For strobe state persistence

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

        // Set up Bad TV effect (Premium)
        guard let badTVFunction = library.makeFunction(name: "badTVEffect") else {
            print("⚠️ Bad TV effect not available")
            return
        }

        do {
            badTVPipelineState = try device.makeComputePipelineState(function: badTVFunction)
            print("✅ Bad TV pipeline created successfully")
        } catch {
            print("⚠️ Could not create Bad TV compute pipeline state: \\(error)")
        }

        // Set up Strobe effect (Premium)
        guard let strobeFunction = library.makeFunction(name: "strobeEffect") else {
            print("⚠️ Strobe effect not available")
            return
        }

        do {
            strobePipelineState = try device.makeComputePipelineState(function: strobeFunction)
            print("✅ Strobe pipeline created successfully")
        } catch {
            print("⚠️ Could not create Strobe compute pipeline state: \\(error)")
        }

        // Set up Convergence effect (Premium)
        guard let convergenceFunction = library.makeFunction(name: "convergenceEffect") else {
            print("⚠️ Convergence effect not available")
            return
        }

        do {
            convergencePipelineState = try device.makeComputePipelineState(function: convergenceFunction)
            print("✅ Convergence pipeline created successfully")
        } catch {
            print("⚠️ Could not create Convergence compute pipeline state: \\(error)")
        }

        // Set up Tunnel effect (Premium)
        guard let tunnelFunction = library.makeFunction(name: "tunnelEffect") else {
            print("⚠️ Tunnel effect not available")
            return
        }

        do {
            tunnelPipelineState = try device.makeComputePipelineState(function: tunnelFunction)
            print("✅ Tunnel pipeline created successfully")
        } catch {
            print("⚠️ Could not create Tunnel compute pipeline state: \\(error)")
        }

        // Set up Analog Glitch effect (Premium)
        guard let analogGlitchFunction = library.makeFunction(name: "analogGlitchEffect") else {
            print("⚠️ Analog Glitch effect not available")
            return
        }

        do {
            analogGlitchPipelineState = try device.makeComputePipelineState(function: analogGlitchFunction)
            print("✅ Analog Glitch pipeline created successfully")
        } catch {
            print("⚠️ Could not create Analog Glitch compute pipeline state: \\(error)")
        }

        // Set up Kaleidoscope effect (Premium)
        guard let kaleidoscopeFunction = library.makeFunction(name: "kaleidoscopeEffect") else {
            print("⚠️ Kaleidoscope effect not available")
            return
        }

        do {
            kaleidoscopePipelineState = try device.makeComputePipelineState(function: kaleidoscopeFunction)
            print("✅ Kaleidoscope pipeline created successfully")
        } catch {
            print("⚠️ Could not create Kaleidoscope compute pipeline state: \\(error)")
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
            case .badTV:
                selectedPipelineState = badTVPipelineState
                print("🎨 MetalRenderer: Selected Bad TV pipeline")
            case .strobe:
                selectedPipelineState = strobePipelineState
                print("🎨 MetalRenderer: Selected Strobe pipeline")
            case .convergence:
                selectedPipelineState = convergencePipelineState
                print("🎨 MetalRenderer: Selected Convergence pipeline")
            case .tunnel:
                selectedPipelineState = tunnelPipelineState
                print("🎨 MetalRenderer: Selected Tunnel pipeline")
            case .analogGlitch:
                selectedPipelineState = analogGlitchPipelineState
                print("🎨 MetalRenderer: Selected Analog Glitch pipeline")
            case .kaleidoscope:
                selectedPipelineState = kaleidoscopePipelineState
                print("🎨 MetalRenderer: Selected Kaleidoscope pipeline")
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

        // Create strobe state texture (1x1 for state persistence)
        if strobeStateTexture == nil {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 1,
                height: 1,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderWrite, .shaderRead]
            strobeStateTexture = device.makeTexture(descriptor: textureDescriptor)
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

        // For Bad TV effect, pass feedback texture as texture index 2
        if let premiumEffect = activePremiumEffect, premiumEffect == .badTV {
            computeEncoder.setTexture(feedbackTexture, index: 2)
        }

        // For Strobe effect, pass strobe state texture as texture index 2
        if let premiumEffect = activePremiumEffect, premiumEffect == .strobe {
            computeEncoder.setTexture(strobeStateTexture, index: 2)
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

        // Handle convergence effect parameters differently
        if let premiumEffect = activePremiumEffect, premiumEffect == .convergence {
            // Convergence effect uses separate buffer parameters
            var convergenceTime = time
            // Pure audio-reactive movement - no time-based oscillation
            var horizontalMagnitude = Float(0.2) + (audioLevel * 15.0)
            var verticalMagnitude = Float(0.2) + (bassLevel * 15.0)
            var colorMagnitude = Float(0.5) + (midLevel * 20.0)
            var convergenceMode = Int32(1) // Add mod mode for better color effects

            computeEncoder.setBytes(&convergenceTime, length: MemoryLayout<Float>.size, index: 0)
            computeEncoder.setBytes(&horizontalMagnitude, length: MemoryLayout<Float>.size, index: 1)
            computeEncoder.setBytes(&verticalMagnitude, length: MemoryLayout<Float>.size, index: 2)
            computeEncoder.setBytes(&colorMagnitude, length: MemoryLayout<Float>.size, index: 3)
            computeEncoder.setBytes(&convergenceMode, length: MemoryLayout<Int32>.size, index: 4)
        } else {
            // Use standard DiscoUniforms for other effects
            let uniformsSize = MemoryLayout<DiscoUniforms>.size
            computeEncoder.setBytes(&uniforms, length: uniformsSize, index: 0)
        }

        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )

        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.endEncoding()

        // For Bad TV effect, copy output to feedback texture for next frame
        if let premiumEffect = activePremiumEffect, premiumEffect == .badTV, let feedbackTexture = feedbackTexture {
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                commandBuffer.commit()
                time += 0.016
                return outputTexture
            }
            blitEncoder.copy(from: outputTexture, to: feedbackTexture)
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