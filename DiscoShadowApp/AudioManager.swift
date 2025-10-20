import AVFoundation
import Accelerate
import Foundation
import CoreMedia

protocol AudioBufferDelegate: AnyObject {
    func didReceiveAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime)
}

protocol RecordingAudioDelegate: AnyObject {
    func didReceiveAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}

class AudioManager: NSObject, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: AVAudioPCMBuffer?

    @Published var audioLevel: Float = 0.0
    @Published var bassLevel: Float = 0.0
    @Published var midLevel: Float = 0.0
    @Published var trebleLevel: Float = 0.0
    @Published var isListening = false

    // Recording support - provide audio buffers to camera manager
    weak var audioBufferDelegate: AudioBufferDelegate?
    weak var recordingAudioDelegate: RecordingAudioDelegate?


    // FFT analysis
    private var fftSetup: FFTSetup?
    private let fftSize = 512  // Reduced for better performance
    private var fftSamples: [Float] = []
    private var fftMagnitudes: [Float] = []
    private var audioFrameCounter = 0

    override init() {
        super.init()
        setupFFT()
        setupAudio()
    }

    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
        stopListening()
    }

    private func setupFFT() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        fftSamples = Array(repeating: 0.0, count: fftSize)
        fftMagnitudes = Array(repeating: 0.0, count: fftSize / 2)
    }

    private func setupAudio() {
        #if targetEnvironment(simulator)
        // Skip audio setup on simulator to prevent crashes
        print("🎵 AudioManager: Skipping audio setup on simulator")
        return
        #endif

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use video recording mode to be compatible with video recording, allow mixing
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .allowAirPlay])
            try audioSession.setActive(true)

            // Add safety check before accessing inputNode
            guard audioEngine.inputNode.outputFormat(forBus: 0).sampleRate > 0 else {
                print("🎵 AudioManager: Invalid audio input format, skipping audio setup")
                return
            }

            inputNode = audioEngine.inputNode
            let inputFormat = inputNode?.outputFormat(forBus: 0)

            guard let inputNode = inputNode, let inputFormat = inputFormat else {
                return
            }

            // Install tap for audio analysis and recording with error handling
            do {
                inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: inputFormat) { [weak self] (buffer, time) in
                    self?.processAudioBuffer(buffer)
                    // Also provide buffer for recording
                    self?.audioBufferDelegate?.didReceiveAudioBuffer(buffer, at: time)

                    // Convert to CMSampleBuffer for recording
                    self?.convertAndSendToRecording(buffer: buffer, at: time)
                }
                print("🎵 AudioManager: Audio tap installed successfully")
            } catch {
                print("🎵 AudioManager: Failed to install audio tap: \(error)")
                return
            }

        } catch {
            print("🎵 AudioManager: Audio setup failed: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        audioFrameCounter += 1

        // Only do heavy FFT processing every 4th frame to improve performance
        let shouldProcessFFT = audioFrameCounter % 4 == 0

        if shouldProcessFFT {
            // Copy audio data for FFT analysis
            let sampleCount = min(frameCount, fftSize)
            for i in 0..<sampleCount {
                fftSamples[i] = channelData[i]
            }

            // Fill remaining with zeros if needed
            if sampleCount < fftSize {
                for i in sampleCount..<fftSize {
                    fftSamples[i] = 0.0
                }
            }

            // Perform FFT analysis
            performFFTAnalysis()
        }

        // Calculate overall audio level (RMS)
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))

        DispatchQueue.main.async {
            self.audioLevel = min(rms * 10.0, 1.0) // Scale and clamp

            // Debug audio every 120 frames (about every 2 seconds at 60fps)
            if self.audioFrameCounter % 120 == 0 {
                print("🎵 AudioManager: RMS=\(rms), Level=\(self.audioLevel), Bass=\(self.bassLevel), Mid=\(self.midLevel), Treble=\(self.trebleLevel)")
            }
        }
    }

    private func performFFTAnalysis() {
        guard let fftSetup = fftSetup else { return }

        let log2n = vDSP_Length(log2(Float(fftSize)))

        // Prepare input for FFT
        var realPart = [Float](repeating: 0.0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0.0, count: fftSize / 2)

        // Copy samples to real part (interleaved format)
        for i in 0..<(fftSize / 2) {
            realPart[i] = fftSamples[i * 2]
            imagPart[i] = i * 2 + 1 < fftSize ? fftSamples[i * 2 + 1] : 0.0
        }

        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                // Perform FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Calculate magnitudes
                for i in 0..<(fftSize / 2) {
                    let real = realPtr[i]
                    let imag = imagPtr[i]
                    fftMagnitudes[i] = sqrt(real * real + imag * imag)
                }
            }
        }

        // Analyze frequency bands
        analyzeFrequencyBands()
    }

    private func analyzeFrequencyBands() {
        let sampleRate: Float = 44100.0 // Assuming 44.1kHz
        let binSize = sampleRate / Float(fftSize)

        // Define frequency ranges (in Hz)
        let bassRange: ClosedRange<Float> = 20.0...250.0
        let midRange: ClosedRange<Float> = 250.0...4000.0
        let trebleRange: ClosedRange<Float> = 4000.0...20000.0

        var bassSum: Float = 0.0
        var midSum: Float = 0.0
        var trebleSum: Float = 0.0
        var bassCount = 0
        var midCount = 0
        var trebleCount = 0

        for i in 0..<fftMagnitudes.count {
            let frequency = Float(i) * binSize
            let magnitude = fftMagnitudes[i]

            if bassRange.contains(frequency) {
                bassSum += magnitude
                bassCount += 1
            } else if midRange.contains(frequency) {
                midSum += magnitude
                midCount += 1
            } else if trebleRange.contains(frequency) {
                trebleSum += magnitude
                trebleCount += 1
            }
        }

        // Calculate averages and normalize
        let bassAvg = bassCount > 0 ? (bassSum / Float(bassCount)) * 0.01 : 0.0
        let midAvg = midCount > 0 ? (midSum / Float(midCount)) * 0.01 : 0.0
        let trebleAvg = trebleCount > 0 ? (trebleSum / Float(trebleCount)) * 0.01 : 0.0

        DispatchQueue.main.async {
            self.bassLevel = min(bassAvg, 1.0)
            self.midLevel = min(midAvg, 1.0)
            self.trebleLevel = min(trebleAvg, 1.0)
        }
    }

    func startListening() {
        guard !audioEngine.isRunning else {
            print("🎵 AudioManager: Already running")
            return
        }

        print("🎵 AudioManager: Requesting microphone permission...")
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    print("🎵 AudioManager: Permission granted, starting audio engine...")
                    do {
                        try self?.audioEngine.start()
                        self?.isListening = true
                        print("🎵 AudioManager: Audio engine started successfully!")
                    } catch {
                        print("🎵 AudioManager: Failed to start audio engine: \(error)")
                    }
                } else {
                    print("🎵 AudioManager: Microphone permission denied")
                }
            }
        }
    }


    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            inputNode?.removeTap(onBus: 0)
        }
        isListening = false
    }

    // Get audio parameters for shader
    func getAudioParameters() -> (level: Float, bass: Float, mid: Float, treble: Float) {
        return (audioLevel, bassLevel, midLevel, trebleLevel)
    }

    // Convert AVAudioPCMBuffer to CMSampleBuffer for recording
    private func convertAndSendToRecording(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let recordingDelegate = recordingAudioDelegate else { return }

        // Use a simpler approach - create CMSampleBuffer with proper timing
        guard let channelData = buffer.floatChannelData?[0] else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        let channels = Int(buffer.format.channelCount)

        // Create audio format description for the buffer format
        var audioFormatDescription: CMFormatDescription?
        var audioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )

        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &audioStreamBasicDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &audioFormatDescription
        )

        guard formatStatus == noErr, let formatDescription = audioFormatDescription else {
            return
        }

        // Create block buffer with audio data
        var blockBuffer: CMBlockBuffer?
        let dataSize = frameCount * MemoryLayout<Float>.size

        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == noErr, let block = blockBuffer else {
            return
        }

        // Copy audio data to block buffer
        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: channelData,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        guard copyStatus == noErr else {
            return
        }

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sample = sampleBuffer else {
            return
        }

        // Send to recording delegate
        recordingDelegate.didReceiveAudioSampleBuffer(sample)
    }
}