import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import os

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var vm = PlayerViewModel()
    @State private var showImporter = false
    @State private var isSidebarVisible = false
    @State private var showArtworkPicker = false
    @State private var artworkCandidates: [URL] = []
    @State private var isLoadingCandidates = false
    @State private var showLyricPicker = false
    @State private var lyricCandidates: [String] = []
    @State private var isLoadingLyricCandidates = false

    var body: some View {
        Group {
            HStack(spacing: 0) {
                SidebarView(vm: vm, isSidebarVisible: .constant(true), showImporter: $showImporter)
                    .frame(maxWidth: 360)
                    .frame(maxHeight: .infinity)
                Divider()
                playerView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
        }
        .sheet(isPresented: $showArtworkPicker) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("选择封面")
                        .font(.title3).fontWeight(.semibold)
                    Spacer()
                    Button("关闭") { showArtworkPicker = false }
                }
                if isLoadingCandidates {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if artworkCandidates.isEmpty {
                    Text("未找到候选封面").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(artworkCandidates, id: \.self) { url in
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .onTapGesture {
                                            Task {
                                                do {
                                                    let (data, _) = try await URLSession.shared.data(from: url)
                                                    if let _ = NSImage(data: data) {
                                                        await MainActor.run {
                                                            vm.replaceCurrentArtwork(with: data)
                                                            showArtworkPicker = false
                                                        }
                                                    }
                                                } catch {
                                                }
                                            }
                                        }
                                } placeholder: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1))
                                        ProgressView()
                                    }
                                    .frame(width: 110, height: 110)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(minWidth: 480, minHeight: 360)
                }
            }
            .padding(16)
            .onAppear {
                guard let track = vm.currentTrack else { return }
                isLoadingCandidates = true
                AlbumArtFetcher.candidates(for: track.title, artist: track.artist) { urls in
                    DispatchQueue.main.async {
                        self.artworkCandidates = urls
                        self.isLoadingCandidates = false
                    }
                }
            }
        }
        .sheet(isPresented: $showLyricPicker) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("选择歌词")
                        .font(.title3).fontWeight(.semibold)
                    Spacer()
                    Button("关闭") { showLyricPicker = false }
                }
                if isLoadingLyricCandidates {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if lyricCandidates.isEmpty {
                    Text("未找到候选歌词").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lyricCandidates.enumerated()), id: \.offset) { idx, text in
                                VStack(alignment: .leading, spacing: 6) {
                                    let preview = text
                                        .components(separatedBy: .newlines)
                                        .prefix(4)
                                        .joined(separator: "\n")
                                    Text(preview)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(nil)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
                                .onTapGesture {
                                    vm.replaceCurrentLyrics(with: text)
                                    showLyricPicker = false
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minWidth: 560, minHeight: 420)
                }
            }
            .padding(16)
            .onAppear {
                guard let track = vm.currentTrack else { return }
                isLoadingLyricCandidates = true
                LyricFetcher.candidates(for: track.title, artist: track.artist) { arr in
                    DispatchQueue.main.async {
                        self.lyricCandidates = arr
                        self.isLoadingLyricCandidates = false
                    }
                }
            }
        }
    }
    
    private var playerView: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    if let data = vm.currentTrack?.artworkData, let uiImage = NSImage(data: data) {
                        Image(nsImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: min(geo.size.width, 420))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .padding(40)
                            )
                            .frame(height: min(geo.size.width, 420))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Button {
                        if vm.currentTrack != nil {
                            artworkCandidates = []
                            isLoadingCandidates = true
                            showArtworkPicker = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.currentTrack?.title ?? "未选择曲目")
                        .font(.title3).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(vm.currentTrack?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                VStack(spacing: 8) {
                    Slider(value: Binding(get: {
                        vm.currentTime
                    }, set: { v in
                        vm.seek(to: v)
                    }), in: 0...(vm.duration > 0 ? vm.duration : 1))
                    HStack {
                        Text(formatTime(vm.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(vm.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: {
                        Double(vm.volume)
                    }, set: { v in
                        vm.volume = Float(v)
                    }), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
                HStack(spacing: 24) {
                    Button {
                        vm.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    Button {
                        vm.togglePlay()
                    } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    Button {
                        vm.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    Button {
                        if vm.currentTrack != nil {
                            lyricCandidates = []
                            isLoadingLyricCandidates = true
                            showLyricPicker = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
                
                if let lyrics = vm.currentTrack?.lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !vm.parsedLyrics.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(vm.parsedLyrics.enumerated()), id: \.element.id) { index, line in
                                        Text(line.text)
                                            .font(index == vm.currentLyricIndex ? .title2 : .title3)
                                            .foregroundStyle(index == vm.currentLyricIndex ? .primary : .secondary)
                                            .id(index)
                                            .onTapGesture { vm.seek(to: line.time) }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 24)
                            }
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                if let i = vm.currentLyricIndex {
                                    proxy.scrollTo(i, anchor: .top)
                                }
                            }
                            .onChange(of: vm.currentLyricIndex) { i in
                                if let i = i {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(i, anchor: .top)
                                    }
                                }
                            }
                        }
                    } else {
                        ScrollView {
                            Text(lyrics)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Spacer()
            }
            .padding()
        }
    }
}

func formatTime(_ time: Double) -> String {
    let total = Int(time.rounded())
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
