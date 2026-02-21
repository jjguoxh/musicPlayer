
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
    @State private var showArtworkPicker = false
    @State private var artworkCandidates: [URL] = []
    @State private var isLoadingArtworkCandidates = false
    @State private var showLyricPicker = false
    @State private var lyricCandidates: [String] = []
    @State private var isLoadingLyricCandidates = false
    @State private var showImportResult = false
    @State private var importMessage: String = ""

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
        .sheet(isPresented: $showArtworkPicker) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("选择封面").font(.title3).fontWeight(.semibold)
                    Spacer()
                    Button("关闭") { showArtworkPicker = false }
                }
                if isLoadingArtworkCandidates {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if artworkCandidates.isEmpty {
                    Text("未找到候选封面").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        let cols = [GridItem(.adaptive(minimum: 90), spacing: 10)]
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(artworkCandidates, id: \.self) { url in
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 90, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .onTapGesture {
                                            Task {
                                                do {
                                                    let (data, _) = try await URLSession.shared.data(from: url)
                                                    if let _ = UIImage(data: data) {
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
                                    .frame(width: 90, height: 90)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: 360)
                }
            }
            .padding(16)
            .frame(maxWidth: 360)
            .presentationDetents([.medium])
            .onAppear {
                guard let track = vm.currentTrack else { return }
                isLoadingArtworkCandidates = true
                AlbumArtFetcher.candidates(for: track.title, artist: track.artist) { urls in
                    DispatchQueue.main.async {
                        self.artworkCandidates = urls
                        self.isLoadingArtworkCandidates = false
                    }
                }
            }
        }
        .sheet(isPresented: $showLyricPicker) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("选择歌词").font(.title3).fontWeight(.semibold)
                    Spacer()
                    Button("关闭") { showLyricPicker = false }
                }
                if isLoadingLyricCandidates {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if lyricCandidates.isEmpty {
                    Text("未找到候选歌词").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lyricCandidates.enumerated()), id: \.offset) { idx, text in
                                VStack(alignment: .leading, spacing: 6) {
                                    let preview = text.components(separatedBy: .newlines).prefix(4).joined(separator: "\n")
                                    Text(preview)
                                        .font(.system(.body, design: .monospaced))
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
                    .frame(maxWidth: 420)
                }
            }
            .padding(16)
            .frame(maxWidth: 420)
            .presentationDetents([.medium])
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
        .onChange(of: vm.lastImportStage) { s in
            if s == "success" {
                importMessage = "导入成功"
                showImportResult = true
            } else if s == "failed" {
                importMessage = "导入失败"
                showImportResult = true
            }
        }
        .onChange(of: vm.lastImportError) { e in
            guard let e = e, !e.isEmpty else { return }
            importMessage = "导入失败：\(e)"
            showImportResult = true
        }
        .alert("导入结果", isPresented: $showImportResult) {
            Button("确定") { showImportResult = false }
        } message: {
            Text(importMessage)
        }
    }

    private var playerView: some View {
        GeometryReader { geo in
            VStack(spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    if let data = vm.currentTrack?.artworkData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: min(geo.size.width, 420) * 0.75)
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
                            .frame(height: min(geo.size.width, 420) * 0.75)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Button {
                        if vm.currentTrack != nil {
                            artworkCandidates = []
                            isLoadingArtworkCandidates = true
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
                    .frame(width: min(geo.size.width * 0.92, 700))
                    HStack {
                        Text(formatTime(vm.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(vm.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: min(geo.size.width * 0.92, 700))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                HStack(spacing: 28) {
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
                .frame(width: min(geo.size.width * 0.92, 700), alignment: .center)
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
                        .frame(width: min(geo.size.width * 0.92, 700), height: 160)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, alignment: .center)
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
                        .frame(width: min(geo.size.width * 0.92, 700), height: 160)
                        .padding(.horizontal, 4)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, alignment: .center)
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
