import Foundation
import MusicKit
import MediaPlayer

@available(iOS 15.0, *)
@MainActor
class MusicAPIService: ObservableObject {
    @Published var searchResults: [Song] = []
    @Published var trendingSongs: [Song] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Instagram-style music categories
    @Published var forYouSongs: [Song] = []
    @Published var trendingNowSongs: [Song] = []
    @Published var moodBasedSongs: [Song] = []

    private var musicAuthorizationStatus: MusicAuthorization.Status = .notDetermined

    init() {
        Task {
            await checkMusicAuthorization()
        }
    }

    // MARK: - Authorization

    func checkMusicAuthorization() async {
        musicAuthorizationStatus = MusicAuthorization.currentStatus
        print("🎵 MusicKit authorization status: \(musicAuthorizationStatus)")

        if musicAuthorizationStatus == .authorized {
            print("✅ MusicKit authorized - loading initial content")
            await loadInitialContent()
        } else {
            print("❌ MusicKit not authorized - status: \(musicAuthorizationStatus)")
        }
    }

    func requestMusicAuthorization() async -> Bool {
        print("🎵 Requesting MusicKit authorization...")
        print("🔍 Current status before request: \(musicAuthorizationStatus)")

        // Check current status first
        musicAuthorizationStatus = MusicAuthorization.currentStatus
        print("🔍 Updated current status: \(musicAuthorizationStatus)")

        if musicAuthorizationStatus == .authorized {
            print("✅ Already authorized!")
            await loadInitialContent()
            return true
        }

        // Request authorization
        let status = await MusicAuthorization.request()
        musicAuthorizationStatus = status
        print("🎵 Authorization result: \(status)")

        switch status {
        case .authorized:
            print("✅ Authorization granted - loading content")
            errorMessage = nil
            await loadInitialContent()
            return true
        case .denied:
            print("❌ Authorization denied by user")
            errorMessage = "Apple Music access denied. Please enable in Settings > Privacy & Security > Media & Apple Music."
            return false
        case .restricted:
            print("❌ Authorization restricted (parental controls?)")
            errorMessage = "Apple Music access is restricted. Check Screen Time or parental controls."
            return false
        case .notDetermined:
            print("❌ Authorization not determined - this shouldn't happen after request")
            errorMessage = "Unable to determine Apple Music permissions."
            return false
        @unknown default:
            print("❌ Unknown authorization status: \(status)")
            errorMessage = "Unknown Apple Music authorization status."
            return false
        }
    }

    // MARK: - Content Loading

    func loadInitialContent() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load trending content (like Instagram's "Trending" tab)
            await loadTrendingMusic()
            await loadForYouMusic()
            await loadMoodBasedMusic()
        } catch {
            errorMessage = "Failed to load music content: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func loadTrendingMusic() async {
        do {
            // Search for popular/trending songs with better terms
            let trendingTerms = ["viral", "trending", "popular", "top hits"]
            var allTrending: [Song] = []

            for term in trendingTerms {
                let request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                let response = try await request.response()
                allTrending.append(contentsOf: Array(response.songs.prefix(10)))
            }

            trendingSongs = Array(allTrending.shuffled().prefix(20))
            trendingNowSongs = trendingSongs
            print("🔥 Loaded \(trendingNowSongs.count) trending songs")
        } catch {
            print("Failed to load trending music: \(error)")
        }
    }

    private func loadForYouMusic() async {
        do {
            // Get personalized recommendations if user is signed in
            let request = MusicCatalogSearchRequest(term: "popular", types: [Song.self])
            let response = try await request.response()

            forYouSongs = Array(response.songs.prefix(15))
        } catch {
            print("Failed to load For You music: \(error)")
        }
    }

    private func loadMoodBasedMusic() async {
        do {
            // Load mood-based music (perfect for pairing with visual effects)
            let moodTerms = [
                "psychedelic rock", "electronic dance", "ambient music",
                "chill beats", "synthwave", "vaporwave", "experimental",
                "glitch hop", "future bass", "trap music"
            ]
            var allMoodSongs: [Song] = []

            for mood in moodTerms {
                let request = MusicCatalogSearchRequest(term: mood, types: [Song.self])
                let response = try await request.response()
                allMoodSongs.append(contentsOf: Array(response.songs.prefix(5)))
            }

            moodBasedSongs = Array(allMoodSongs.shuffled().prefix(25))
            print("🎨 Loaded \(moodBasedSongs.count) mood-based songs for visual effects")
        } catch {
            print("Failed to load mood-based music: \(error)")
        }
    }

    // MARK: - Search

    func searchMusic(query: String) async {
        guard !query.isEmpty else {
            print("🔍 Empty search query - clearing results")
            searchResults = []
            return
        }

        print("🔍 Searching for: '\(query)'")
        isLoading = true
        errorMessage = nil

        // Check authorization first
        print("🔍 Current authorization status: \(musicAuthorizationStatus)")
        print("🔍 MusicAuthorization.currentStatus: \(MusicAuthorization.currentStatus)")

        if musicAuthorizationStatus != .authorized {
            print("❌ Cannot search - MusicKit not authorized: \(musicAuthorizationStatus)")
            print("🔄 Attempting to re-request authorization...")

            let granted = await requestMusicAuthorization()
            if !granted {
                print("❌ Re-authorization failed")
                await loadDemoSearchResults(for: query)
                return
            }
            // If we get here, authorization was successful, continue with search
            print("✅ Re-authorization successful, proceeding with search")
        } else {
            print("✅ Already authorized, proceeding with search")
        }

        // Try actual MusicKit search first
        do {
            let request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            print("🔍 Making search request for term: '\(query)'")
            let response = try await request.response()

            print("🔍 Response songs count: \(response.songs.count)")
            searchResults = Array(response.songs.prefix(50))
            print("✅ Search successful - found \(searchResults.count) songs")

            if searchResults.isEmpty {
                print("⚠️ No songs found for query: '\(query)'")
                errorMessage = "No songs found for '\(query)'. Try a different search term."
            } else {
                print("🎵 First result: \(searchResults.first?.title ?? "Unknown") by \(searchResults.first?.artistName ?? "Unknown")")
                errorMessage = nil
            }
            isLoading = false
            return
        } catch {
            print("❌ MusicKit search failed: \(error)")

            // Try Web API as fallback
            if let developerToken = generateDeveloperToken() {
                print("🔄 Falling back to Apple Music Web API with developer token")
                await searchWithWebAPI(query: query, token: developerToken)
                return
            }

            // Show helpful error message
            errorMessage = "Unable to search Apple Music. Please check your internet connection and Apple Music subscription."
            searchResults = []
            isLoading = false
            return
        }


        isLoading = false
    }


    // Simplified token generation (CryptoKit causes build issues)
    private func generateDeveloperToken() -> String? {
        return nil
    }

    // Apple Music Web API search using developer token
    private func searchWithWebAPI(query: String, token: String) async {
        do {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let urlString = "https://api.music.apple.com/v1/catalog/us/search?term=\(encodedQuery)&types=songs&limit=50"

            guard let url = URL(string: urlString) else {
                errorMessage = "Invalid search URL"
                isLoading = false
                return
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            print("🌐 Making Apple Music Web API request to: \(urlString)")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 Response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode != 200 {
                    errorMessage = "Apple Music API error: \(httpResponse.statusCode)"
                    isLoading = false
                    return
                }
            }

            // Parse the JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [String: Any],
               let songs = results["songs"] as? [String: Any],
               let songData = songs["data"] as? [[String: Any]] {

                print("🎵 Found \(songData.count) songs via Web API")

                if songData.count > 0 {
                    errorMessage = "Unable to display search results. Please check your Apple Music subscription."
                } else {
                    errorMessage = "No songs found for '\(query)'"
                }

                searchResults = [] // Can't create Song objects from Web API data

            } else {
                errorMessage = "Failed to parse Apple Music Web API response"
            }

        } catch {
            print("❌ Web API search failed: \(error)")
            errorMessage = "Apple Music Web API search failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // Handle cases when MusicKit is unavailable
    private func loadDemoSearchResults(for query: String) async {
        // Provide specific error message based on authorization status
        switch musicAuthorizationStatus {
        case .notDetermined:
            errorMessage = "Apple Music access not yet requested. Please try again."
        case .denied:
            errorMessage = "Apple Music access denied. Enable in Settings > Privacy & Security > Media & Apple Music, then restart the app."
        case .restricted:
            errorMessage = "Apple Music access restricted. Check Screen Time or parental controls."
        case .authorized:
            errorMessage = "Apple Music search unavailable. Please check your internet connection and Apple Music subscription."
        @unknown default:
            errorMessage = "Apple Music access error. Please check your settings and try again."
        }

        searchResults = []
        isLoading = false
    }

    // MARK: - Preview & Selection

    func getPreviewURL(for song: Song) -> URL? {
        return song.previewAssets?.first?.url
    }

    func getSongArtwork(for song: Song, size: CGSize = CGSize(width: 300, height: 300)) -> URL? {
        return song.artwork?.url(width: Int(size.width), height: Int(size.height))
    }

    // Convert MusicKit Song to something our existing MusicManager can use
    func convertToMPMediaItem(_ song: Song) async -> MPMediaItem? {
        // This would require additional implementation to bridge MusicKit -> MediaPlayer
        // For now, we'll work directly with MusicKit songs
        return nil
    }
}

// MARK: - Instagram-Style Categories

@available(iOS 15.0, *)
extension MusicAPIService {

    func loadCategoryMusic(category: MusicCategory) async {
        isLoading = true
        errorMessage = nil

        do {
            let searchTerms: [String]

            switch category {
            case .trending:
                searchTerms = ["viral", "trending", "popular", "top hits"]
            case .forYou:
                searchTerms = ["popular", "recommended", "chart toppers"]
            case .electronic:
                searchTerms = ["electronic", "EDM", "techno", "house music", "trance"]
            case .psychedelic:
                searchTerms = ["psychedelic", "trippy", "experimental", "shoegaze"]
            case .chill:
                searchTerms = ["chill", "lofi", "ambient", "downtempo", "chill beats"]
            case .energetic:
                searchTerms = ["energetic", "upbeat", "high energy", "pump up", "workout"]
            case .ambient:
                searchTerms = ["ambient", "atmospheric", "soundscape", "drone", "meditation"]
            }

            var allResults: [Song] = []
            for term in searchTerms {
                let request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                let response = try await request.response()
                allResults.append(contentsOf: Array(response.songs.prefix(10)))
            }

            searchResults = Array(allResults.shuffled().prefix(50))
            print("🎵 Loaded \(searchResults.count) songs for category: \(category.rawValue)")

        } catch {
            errorMessage = "Failed to load \(category.rawValue) music: \(error.localizedDescription)"
            searchResults = []
        }

        isLoading = false
    }
}


enum MusicCategory: String, CaseIterable {
    case trending = "Trending"
    case forYou = "For You"
    case electronic = "Electronic"
    case psychedelic = "Psychedelic"
    case chill = "Chill"
    case energetic = "Energetic"
    case ambient = "Ambient"

    var emoji: String {
        switch self {
        case .trending: return "🔥"
        case .forYou: return "✨"
        case .electronic: return "🎛️"
        case .psychedelic: return "🌈"
        case .chill: return "😌"
        case .energetic: return "⚡"
        case .ambient: return "🌙"
        }
    }
}