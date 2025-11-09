import SwiftUI
import MusicKit

@available(iOS 15.0, *)
struct SimpleMusicSearch: View {
    @StateObject private var musicAPI = MusicAPIService()
    @State private var searchText = ""
    @State private var showingPermissionAlert = false
    @State private var searchTask: Task<Void, Never>?

    @Binding var isPresented: Bool
    var onSongSelected: (Song) -> Void

    var body: some View {
        ZStack {
            // Liquid glass background that shows camera effects behind
            liquidGlassBackground

            VStack(spacing: 0) {
                // Top bar with close button
                topBar

                // Search bar with glass effect
                searchBar

                // Search results
                if musicAPI.isLoading {
                    loadingView
                } else if let error = musicAPI.errorMessage {
                    errorView(message: error)
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
            Text("Enable Apple Music access in Settings to browse music.")
        }
    }

    // MARK: - Liquid Glass Background

    private var liquidGlassBackground: some View {
        Rectangle()
            .fill(.clear) // Transparent to show camera effects behind
            .background(.ultraThinMaterial, in: Rectangle())
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
                .background(Color.black.opacity(0.2))
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))

            TextField("Search Apple Music...", text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .onChange(of: searchText) { _, newValue in
                    // Cancel previous search task
                    searchTask?.cancel()

                    // Debounce search with 300ms delay
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)

                        if !Task.isCancelled {
                            await musicAPI.searchMusic(query: newValue)
                        }
                    }
                }
        }
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !searchText.isEmpty && !musicAPI.searchResults.isEmpty {
                    ForEach(musicAPI.searchResults, id: \.id) { song in
                        GlassSongRow(song: song) {
                            onSongSelected(song)
                            isPresented = false
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

                        Text("Find the perfect track for your video")
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

    // MARK: - Loading and Error Views

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

    private func requestMusicAccess() {
        Task {
            let granted = await musicAPI.requestMusicAuthorization()
            if !granted {
                showingPermissionAlert = true
            }
        }
    }
}