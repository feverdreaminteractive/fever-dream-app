import SwiftUI
import MusicKit

@available(iOS 15.0, *)
struct InstagramStyleMusicBrowser: View {
    @StateObject private var musicAPI = MusicAPIService()
    @State private var selectedCategory: MusicCategory = .trending
    @State private var searchText = ""
    @State private var showingPermissionAlert = false
    @State private var selectedSong: Song?
    @State private var isPlaying = false
    @State private var searchTask: Task<Void, Never>?

    @Binding var isPresented: Bool
    var onSongSelected: (Song) -> Void

    var body: some View {
        ZStack {
            // Background with liquid glass effect
            liquidGlassBackground

            VStack(spacing: 0) {
                // Top bar with close button
                topBar

                // Search bar
                searchBar

                // Search results with glass effect
                if musicAPI.isLoading {
                    loadingView
                } else if let errorMessage = musicAPI.errorMessage {
                    errorView(message: errorMessage)
                } else {
                    searchResultsList
                }

                Spacer()
            }
        }
        .onAppear {
            requestMusicAccess()
        }
        .alert("Music Access Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enable Apple Music access in Settings to browse and select music for your videos.")
        }
    }

    // MARK: - Liquid Glass Background

    private var liquidGlassBackground: some View {
        ZStack {
            // Transparent base to let effects show through
            Color.clear

            // Blurred overlay for glass effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.8) // Make it more transparent
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .medium))

            Spacer()

            Text("Add Music")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Button("Done") {
                isPresented = false
            }
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(Color.black.opacity(0.3))
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search songs, artists, albums...", text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.white.opacity(0.1))
                        )
                )
                .onChange(of: searchText) { _, newValue in
                    // Cancel previous search task
                    searchTask?.cancel()

                    // Debounce search with 300ms delay for real device
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)

                        if !Task.isCancelled {
                            await musicAPI.searchMusic(query: newValue)
                        }
                    }
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.clear)
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !searchText.isEmpty && !musicAPI.searchResults.isEmpty {
                    ForEach(musicAPI.searchResults, id: \.id) { song in
                        GlassSongRow(song: song) {
                            print("🎵 Song tapped: \(song.title) by \(song.artistName)")
                            onSongSelected(song)
                            print("🎵 Calling onSongSelected callback")
                            isPresented = false
                            print("🎵 Dismissing music browser")
                        }
                    }
                } else if !searchText.isEmpty {
                    // Show empty state for search
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))

                        Text("No songs found for '\(searchText)'")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 60)
                } else {
                    // Show search prompt
                    VStack(spacing: 20) {
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.4))

                        Text("Search Apple Music")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Add your favorite track to enhance your content")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 80)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color.clear)
    }

    // MARK: - Glass Song Row

    private struct GlassSongRow: View {
        let song: Song
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Album artwork
                    AsyncImage(url: song.artwork?.url(width: 60, height: 60)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Song info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Text(song.artistName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)

                        if let duration = song.duration {
                            Text(formatDuration(duration))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()

                    // Add button
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }

        private func formatDuration(_ duration: TimeInterval) -> String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }


    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("Searching Apple Music...")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.6))

            Text("Music Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Request Apple Music Access") {
                requestMusicAccess()
            }
            .padding()
            .background(Color.white.opacity(0.2))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Functions

    private func requestMusicAccess() {
        Task {
            let granted = await musicAPI.requestMusicAuthorization()
            if !granted {
                showingPermissionAlert = true
            }
        }
    }
}

// MARK: - Category Tab

@available(iOS 15.0, *)
struct CategoryTab: View {
    let category: MusicCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(category.emoji)
                    .font(.title2)
                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .purple : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.purple.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Song Row

@available(iOS 15.0, *)
struct SongRow: View {
    let song: Song
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Album artwork
                AsyncImage(url: song.artwork?.url(width: 50, height: 50)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(song.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let duration = song.duration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Play indicator or preview button
                if isPlaying {
                    Image(systemName: "pause.fill")
                        .foregroundColor(.purple)
                        .font(.title3)
                } else {
                    Image(systemName: "play.fill")
                        .foregroundColor(.purple)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    InstagramStyleMusicBrowser(isPresented: .constant(true)) { song in
        print("Selected song: \(song.title)")
    }
}