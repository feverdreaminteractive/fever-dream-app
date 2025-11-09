import Foundation
import MusicKit
import MediaPlayer

@available(iOS 15.0, *)
@MainActor
class MusicPlayerService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentSong: Song?
    @Published var volume: Float = 0.5 {
        didSet {
            updateVolume()
        }
    }

    private let player = ApplicationMusicPlayer.shared

    init() {
        // Set initial volume
        updateVolume()
    }

    func playSong(_ song: Song) async {
        do {
            currentSong = song

            // Create a queue with just this song
            let queue = ApplicationMusicPlayer.Queue(for: [song])
            player.queue = queue

            // Start playback
            try await player.play()
            isPlaying = true

            print("🎵 Started playing: \(song.title) by \(song.artistName)")
        } catch {
            print("❌ Failed to play song: \(error)")
            isPlaying = false
        }
    }

    func togglePlayback() async {
        do {
            if isPlaying {
                player.pause()
                isPlaying = false
                print("⏸️ Paused music")
            } else {
                try await player.play()
                isPlaying = true
                print("▶️ Resumed music")
            }
        } catch {
            print("❌ Failed to toggle playback: \(error)")
        }
    }

    func stopPlayback() {
        player.stop()
        isPlaying = false
        currentSong = nil
        print("⏹️ Stopped music")
    }

    private func updateVolume() {
        // Set system volume
        MPVolumeView.setVolume(volume)
        print("🔊 Volume set to: \(volume)")
    }
}

extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
            slider?.value = volume
        }
    }
}