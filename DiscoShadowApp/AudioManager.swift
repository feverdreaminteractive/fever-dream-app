import AVFoundation
import Accelerate
import Foundation

class AudioManager: NSObject, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: AVAudioPCMBuffer?

    @Published var audioLevel: Float = 0.0
    @Published var bassLevel: Float = 0.0
    @Published var midLevel: Float = 0.0
    @Published var trebleLevel: Float = 0.0
    @Published var isListening = false

    // FFT analysis
    private var fftSetup: FFTSetup?
    private let fftSize = 1024
    private var fftSamples: [Float] = []
    private var fftMagnitudes: [Float] = []

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
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)

            inputNode = audioEngine.inputNode
            let inputFormat = inputNode?.outputFormat(forBus: 0)

            guard let inputNode = inputNode, let inputFormat = inputFormat else {
                print("Failed to get input node or format")
                return
            }

            // Install tap for audio analysis
            inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: inputFormat) { [weak self] (buffer, time) in
                self?.processAudioBuffer(buffer)
            }

        } catch {
            print("Audio setup failed: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

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

        // Calculate overall audio level (RMS)
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))

        DispatchQueue.main.async {
            self.audioLevel = min(rms * 10.0, 1.0) // Scale and clamp
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
        guard !audioEngine.isRunning else { return }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    do {
                        try self?.audioEngine.start()
                        self?.isListening = true
                    } catch {
                        print("Failed to start audio engine: \(error)")
                    }
                } else {
                    print("Microphone permission denied")
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
}