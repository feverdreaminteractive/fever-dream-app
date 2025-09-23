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

    private var textureCache: CVMetalTextureCache?
    private var outputTexture: MTLTexture?
    var time: Float = 0.0
    var intensity: Float = 1.0
    var colorVariation: Float = 0.5
    var glitchIntensity: Float = 0.8
    var warpAmount: Float = 1.2
    var chromaticAberration: Float = 0.015

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
        print("🔧 Setting up Metal pipeline...")

        // Set up Disco Shadow effect
        guard let discoFunction = library.makeFunction(name: "discoShadowEffect") else {
            print("❌ Failed to create compute function 'discoShadowEffect'")
            fatalError("Could not create disco shadow compute function")
        }
        print("✅ Created compute function 'discoShadowEffect'")

        do {
            discoComputePipelineState = try device.makeComputePipelineState(function: discoFunction)
            print("✅ Created disco shadow compute pipeline state")
        } catch {
            print("❌ Failed to create disco shadow compute pipeline state: \(error)")
            fatalError("Could not create disco shadow compute pipeline state: \(error)")
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
        print("🔧 MetalRenderer.processFrame called! Audio: \(audioLevel), Bass: \(bassLevel), Mid: \(midLevel), Treble: \(trebleLevel), WarpMag: \(warpMagnitude)")

        guard let textureCache = textureCache else {
            print("❌ Texture cache is nil!")
            return nil
        }

        // Use Disco Shadow effect (beta version)
        guard let selectedPipelineState = discoComputePipelineState else {
            print("❌ Disco Shadow compute pipeline state is nil!")
            return nil
        }

        print("✅ Metal renderer setup OK")

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
            print("❌ Failed to create input texture from pixel buffer: \(inputResult)")
            return nil
        }

        guard let inputTexture = CVMetalTextureGetTexture(inputTextureRef!) else {
            print("❌ Failed to get Metal texture from CVMetalTexture")
            return nil
        }

        print("✅ Input texture created: \(width)x\(height)")

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

        guard let outputTexture = outputTexture else {
            print("❌ Failed to create output texture")
            return nil
        }

        print("✅ Output texture ready: \(outputTexture.width)x\(outputTexture.height)")

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            return nil
        }

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("❌ Failed to create compute encoder")
            return nil
        }

        print("✅ Command buffer and encoder created")

        computeEncoder.setComputePipelineState(selectedPipelineState)
        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)

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
            warpMagnitude: warpAmount
        )

        // Debug: Log audio parameters every 30 frames
        if Int(time * 60) % 30 == 0 {
            print("🎨 MetalRenderer audio: Level=\(audioLevel), Bass=\(bassLevel), Mid=\(midLevel), Treble=\(trebleLevel), Warp=\(warpAmount)")
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

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.status == .error {
            print("❌ Command buffer execution failed!")
            return nil
        }
        time += 0.016

        return outputTexture
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
}