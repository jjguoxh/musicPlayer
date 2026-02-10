
//
//  ContentView.swift
//  musicPlayer
//
//  Created by jjguoxh@gmail.com on 2026/2/9.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import os

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var vm = PlayerViewModel()
    @State private var showImporter = false
    @State private var isSidebarVisible = false

    var body: some View {
        Group {
            if hSize == .regular {
                HStack(spacing: 0) {
                    SidebarView(vm: vm, isSidebarVisible: .constant(true), showImporter: $showImporter)
                        .frame(maxWidth: 360)
                        .frame(maxHeight: .infinity)
                    Divider()
                    playerView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            } else {
                NavigationStack {
                    ZStack(alignment: .leading) {
                        playerView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                            // Add Hamburger Button
                            .overlay(alignment: .topLeading) {
                                Button {
                                    withAnimation {
                                        isSidebarVisible.toggle()
                                    }
                                } label: {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.title)
                                        .padding()
                                        .background(Color(UIColor.systemBackground).opacity(0.5))
                                        .clipShape(Circle())
                                }
                            }
                        
                        if isSidebarVisible {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation {
                                        isSidebarVisible = false
                                    }
                                }
                            
                            SidebarView(vm: vm, isSidebarVisible: $isSidebarVisible, showImporter: $showImporter)
                                .frame(width: 280)
                                .background(Color(UIColor.systemBackground))
                                .transition(.move(edge: .leading))
                                .zIndex(1)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { urls in
                urls.forEach { url in
                    vm.addLocalFile(from: url)
                }
                showImporter = false
            }
        }
    }

    private var playerView: some View {
        GeometryReader { geo in
            VStack(spacing: 16) {
                if let data = vm.currentTrack?.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image)
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
                HStack(spacing: 40) {
                    Button {
                        vm.playbackMode = (vm.playbackMode == .sequential) ? .shuffle : .sequential
                    } label: {
                        Image(systemName: vm.playbackMode == .shuffle ? "shuffle" : "arrow.forward")
                            .font(.title3)
                            .foregroundStyle(vm.playbackMode == .shuffle ? .blue : .primary)
                    }
                    
                    Button {
                        vm.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    Button {
                        vm.togglePlay()
                    } label: {
                        Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    Button {
                        vm.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    
                    // Spacer for symmetry if needed, or just leave it
                    Button {
                        // Placeholder for symmetry or repeat mode later
                    } label: {
                        Image(systemName: "repeat")
                            .font(.title3)
                            .opacity(0) // Hidden for now to maintain layout balance or use Spacer
                    }
                }
                .padding(.top, 4)
                
                // Lyrics View
                if let lyrics = vm.currentTrack?.lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !vm.parsedLyrics.isEmpty {
                        // Synchronized Lyrics
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(vm.parsedLyrics.enumerated()), id: \.element.id) { index, line in
                                        Text(line.text)
                                            .font(index == vm.currentLyricIndex ? .headline : .subheadline)
                                            .foregroundStyle(index == vm.currentLyricIndex ? .primary : .secondary)
                                            .scaleEffect(index == vm.currentLyricIndex ? 1.05 : 1.0)
                                            .animation(.spring(duration: 0.3), value: vm.currentLyricIndex)
                                            .id(index)
                                            .onTapGesture {
                                                // Optional: seek to this line
                                                vm.seek(to: line.time)
                                            }
                                    }
                                }
                                .padding(.vertical, 20)
                                .padding(.horizontal, 20) // Added padding to prevent clipping
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onChange(of: vm.currentLyricIndex) { newIndex in
                                if let idx = newIndex {
                                    withAnimation {
                                        proxy.scrollTo(idx, anchor: .center)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        // Unsynchronized Lyrics (Legacy Text)
                        ScrollView {
                            Text(lyrics)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20) // Added padding to prevent clipping
                        }
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .padding(.horizontal, 4)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.top, 40) // Padding for hamburger menu
        }
    }

    private func formatTime(_ s: Double) -> String {
        if s.isNaN || s.isInfinite || s <= 0 { return "0:00" }
        let total = Int(s.rounded())
        let m = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", m, sec)
    }
}

#Preview {
    ContentView()
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "musicPlayer", category: "Import")

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio, UTType.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        logger.log("DocumentPicker presented")
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "musicPlayer", category: "Import")
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            for u in urls {
                logger.log("Picked URL: \(u.absoluteString, privacy: .public)")
                if let typeId = try? u.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
                    logger.log("Picked typeIdentifier: \(typeId, privacy: .public)")
                }
            }
            onPick(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            logger.log("DocumentPicker cancelled")
        }
    }
}
