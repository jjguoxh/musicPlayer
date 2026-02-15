import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import os

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var vm = PlayerViewModel()
    @State private var showImporter = false
    @State private var isSidebarVisible = false

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
    }
    
    private var playerView: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
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
