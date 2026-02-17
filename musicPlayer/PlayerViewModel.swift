import Foundation
import Combine
import AVFoundation
import UniformTypeIdentifiers
import os
import UIKit
import SwiftUI
import MediaPlayer

struct Track: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let url: URL
    let artworkData: Data?
    let lyrics: String?
}

struct Playlist: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var tracks: [Track]
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

struct LrcLibResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
}

enum PlaybackMode: Int {
    case sequential = 0
    case shuffle = 1
}

extension String {
    var hasChinese: Bool {
        range(of: "\\p{Han}", options: .regularExpression) != nil
    }
}

final class PlayerViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var currentPlaylistId: UUID?
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var lastImportError: String?
    @Published var lastImportStage: String?
    @Published var parsedLyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int?
    @Published var playbackMode: PlaybackMode = .sequential {
        didSet {
            UserDefaults.standard.set(playbackMode.rawValue, forKey: "playbackMode")
        }
    }
    
    // Legacy support for single playlist view if needed, but we should migrate.
    // We'll use the first playlist as "Imported Music" by default.
    var currentPlaylist: Playlist? {
        guard let id = currentPlaylistId else { return playlists.first }
        return playlists.first(where: { $0.id == id })
    }
    
    private var player = AVPlayer()
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let fm = FileManager.default
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "musicPlayer", category: "Import")

    init() {
        // Configure Audio Session for background playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure AudioSession: \(error)")
        }

        setupRemoteTransportControls()
        
        // Initialize with default playlist
        self.playlists = [Playlist(name: "播放列表", tracks: [])]
        self.currentPlaylistId = self.playlists.first?.id
        addTimeObserver()
        setupNotifications()
        
        if let modeRaw = UserDefaults.standard.value(forKey: "playbackMode") as? Int,
           let mode = PlaybackMode(rawValue: modeRaw) {
            self.playbackMode = mode
        }
        
        loadLibrary()
    }

    private func setupNotifications() {
        // Track completion
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.next()
            }
            .store(in: &cancellables)
            
        // Audio Session Interruptions (e.g. phone call)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            // Pause playback when interrupted
            // We don't change isPlaying state if we want to resume later? 
            // Usually we just pause player but keep UI state or handle it.
            // For simplicity:
            player.pause()
            // We might want to keep track if we *were* playing to resume later
            
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && isPlaying {
                player.play()
            }
        @unknown default:
            break
        }
    }

    private func loadLibrary() {
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let destDir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
        if !fm.fileExists(atPath: destDir.path) { return }

        do {
            let fileURLs = try fm.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)
            let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff"]
            
            // Assuming we are loading into the first playlist "Imported Music"
            guard !playlists.isEmpty else { return }
            var tracks = playlists[0].tracks
            
            for url in fileURLs {
                if audioExtensions.contains(url.pathExtension.lowercased()) {
                    let track = createTrack(from: url)
                    if !tracks.contains(where: { $0.url.lastPathComponent == url.lastPathComponent }) {
                        tracks.append(track)
                    }
                }
            }
            playlists[0].tracks = tracks
        } catch {
            logger.error("Failed to load library: \(error.localizedDescription)")
        }
    }

    private func createTrack(from url: URL) -> Track {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = ""
        var artworkData: Data?
        var lyrics: String?
        for meta in asset.commonMetadata {
            if meta.commonKey == .commonKeyTitle, let v = meta.value as? String { title = v }
            if meta.commonKey == .commonKeyArtist, let v = meta.value as? String { artist = v }
        }
        let allMetadata = asset.commonMetadata
            + asset.metadata(forFormat: AVMetadataFormat.id3Metadata)
            + asset.metadata(forFormat: AVMetadataFormat.iTunesMetadata)
        for item in allMetadata {
            if artworkData == nil {
                if item.commonKey == .commonKeyArtwork || item.identifier == .id3MetadataAttachedPicture || item.identifier == .iTunesMetadataCoverArt {
                    if let data = item.dataValue {
                        artworkData = data
                    } else if let image = item.value as? UIImage {
                        artworkData = image.pngData()
                    }
                }
            }
            if lyrics == nil {
                if item.identifier == .id3MetadataUnsynchronizedLyric || item.identifier == .iTunesMetadataLyrics {
                    if let v = item.stringValue, !v.isEmpty { lyrics = v }
                }
            }
            if artworkData != nil && lyrics != nil { break }
        }
        
        // If no embedded lyrics, check for sidecar .lrc file
        if lyrics == nil {
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            // Check if we have security access or it's in our documents
            // Since url is likely from ImportedMusic (Documents), we can read it directly
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                lyrics = content
            }
        }
        
        // If no embedded artwork, check for sidecar .jpg file
        if artworkData == nil {
            let jpgURL = url.deletingPathExtension().appendingPathExtension("jpg")
            if let data = try? Data(contentsOf: jpgURL) {
                artworkData = data
            }
        }
        
        return Track(title: title, artist: artist, url: url, artworkData: artworkData, lyrics: lyrics)
    }

    deinit {
        if let o = timeObserver {
            player.removeTimeObserver(o)
        }
    }

    var currentTrack: Track? {
        guard let idx = currentIndex, let pl = currentPlaylist, pl.tracks.indices.contains(idx) else { return nil }
        return pl.tracks[idx]
    }

    func play(playlistId: UUID? = nil, index: Int) {
        // Activate session before playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }

        // If playlistId provided, switch to it
        if let pid = playlistId {
            currentPlaylistId = pid
        }
        
        guard let pl = currentPlaylist, pl.tracks.indices.contains(index) else { return }
        
        currentIndex = index
        let item = AVPlayerItem(url: pl.tracks[index].url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        updateDurationIfAvailable()
        updateNowPlayingInfo()
        parseCurrentLyrics()
        
        // If lyrics are missing or appear to be incorrect (e.g. Pinyin for Chinese song), try to fetch them
        let track = pl.tracks[index]
        let hasChineseTitle = track.title.hasChinese
        let currentLyrics = track.lyrics ?? ""
        let hasChineseLyrics = currentLyrics.hasChinese
        
        if currentLyrics.isEmpty || (hasChineseTitle && !hasChineseLyrics) {
            fetchLyrics(for: track, playlistId: pl.id, index: index)
        }
        
        // If artwork is missing, try to fetch it
        if track.artworkData == nil {
            fetchArtwork(for: track, playlistId: pl.id, index: index)
        }
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
            updateNowPlayingInfo()
        } else {
            if player.currentItem == nil {
                // Try to play first track of current playlist if available
                if let pl = currentPlaylist, !pl.tracks.isEmpty {
                    play(index: currentIndex ?? 0)
                    return
                }
            }
            // Ensure audio session is active before resuming
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            updateNowPlayingInfo()
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() {
        guard let idx = currentIndex, let pl = currentPlaylist else {
            // If no current index, try playing first
            if let pl = currentPlaylist, !pl.tracks.isEmpty { play(index: 0) }
            return
        }
        
        var nextIdx = 0
        if playbackMode == .shuffle {
            if pl.tracks.count > 1 {
                var newIdx = idx
                // Simple random: pick a different track
                while newIdx == idx {
                    newIdx = Int.random(in: 0..<pl.tracks.count)
                }
                nextIdx = newIdx
            } else {
                nextIdx = 0
            }
        } else {
            nextIdx = idx + 1
        }
        
        if pl.tracks.indices.contains(nextIdx) {
            play(index: nextIdx)
        } else if playbackMode == .sequential && nextIdx >= pl.tracks.count {
            // Loop back to start for sequential if at end
            play(index: 0)
        }
    }

    func previous() {
        guard let idx = currentIndex, let pl = currentPlaylist else { return }
        let prevIdx = idx - 1
        if pl.tracks.indices.contains(prevIdx) {
            play(index: prevIdx)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        guard duration > 0 else { return }
        let clamped = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.updateDurationIfAvailable()
            self.updateCurrentLyricIndex()
        }
    }

    private func updateDurationIfAvailable() {
        if let d = player.currentItem?.duration, d.isNumeric {
            duration = d.seconds
            updateNowPlayingInfo()
        }
    }

    func addLocalFile(from sourceURL: URL) {
        // ... (existing implementation details for file copying) ...
        // I need to be careful to retain the existing logic but update where the track is appended.
        // I will copy the file logic exactly but change the append part.
        
        lastImportStage = "start"
        logger.log("Import start: \(sourceURL.absoluteString, privacy: .public)")
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        if !accessed {
            lastImportError = "securityScopeDenied"
            logger.error("Security scope not granted for: \(sourceURL.absoluteString, privacy: .public)")
        }
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let destDir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
        if !fm.fileExists(atPath: destDir.path) {
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            logger.log("Created directory: \(destDir.path, privacy: .public)")
        }
        if let typeId = try? sourceURL.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            logger.log("Source typeIdentifier: \(typeId, privacy: .public)")
        }
        var dest = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            var i = 1
            while fm.fileExists(atPath: dest.path) {
                let newName = "\(base)-\(i)"
                dest = destDir.appendingPathComponent(newName).appendingPathExtension(ext)
                i += 1
            }
        }
        var readError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var copied = false
        lastImportStage = "forUploading"
        coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &readError) { url in
            logger.log("forUploading URL: \(url.absoluteString, privacy: .public)")
            let innerAccess = url.startAccessingSecurityScopedResource()
            defer { if innerAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.copyItem(at: url, to: dest)
                    copied = true
                    logger.log("Copied via forUploading file to: \(dest.path, privacy: .public)")
                } else {
                    let data = try Data(contentsOf: url)
                    try data.write(to: dest, options: .atomic)
                    copied = true
                    logger.log("Wrote data via forUploading to: \(dest.path, privacy: .public)")
                }
            } catch {
                logger.error("forUploading copy failed: \(String(describing: error), privacy: .public)")
                lastImportError = "forUploadingCopyFailed:\(error.localizedDescription)"
            }
        }
        if let e = readError {
            logger.error("NSFileCoordinator forUploading error: \(e.localizedDescription, privacy: .public)")
        }
        if !copied {
            lastImportStage = "fallbackCoordinate"
            coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &readError) { url in
                logger.log("Fallback coordinate read URL: \(url.absoluteString, privacy: .public)")
                let innerAccess = url.startAccessingSecurityScopedResource()
                defer { if innerAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    if fm.fileExists(atPath: url.path) {
                        try fm.copyItem(at: url, to: dest)
                        copied = true
                        logger.log("Copied file fallback to: \(dest.path, privacy: .public)")
                    } else {
                        let data = try Data(contentsOf: url)
                        try data.write(to: dest, options: .atomic)
                        copied = true
                        logger.log("Wrote data fallback to: \(dest.path, privacy: .public)")
                    }
                } catch {
                    logger.error("Fallback copy failed: \(String(describing: error), privacy: .public)")
                    lastImportError = "fallbackCopyFailed:\(error.localizedDescription)"
                }
            }
            if let e = readError {
                logger.error("NSFileCoordinator fallback error: \(e.localizedDescription, privacy: .public)")
            }
        }
        if !copied {
            lastImportStage = "directCopy"
            do {
                if fm.isReadableFile(atPath: sourceURL.path) {
                    try fm.copyItem(at: sourceURL, to: dest)
                    copied = true
                    logger.log("Direct copyItem succeeded to: \(dest.path, privacy: .public)")
                }
            } catch {
                logger.error("Direct copyItem failed: \(String(describing: error), privacy: .public)")
                lastImportError = "directCopyFailed:\(error.localizedDescription)"
            }
        }
        if !copied {
            logger.error("Import failed: no copy path succeeded for \(sourceURL.absoluteString, privacy: .public)")
            lastImportStage = "failed"
            return
        }
        lastImportStage = "assetMetadata"
        let track = createTrack(from: dest)
        
        // Append to first playlist (Imported Music)
        if !playlists.isEmpty {
            playlists[0].tracks.append(track)
        } else {
            playlists.append(Playlist(name: "播放列表", tracks: [track]))
        }
        
        logger.log("Import success: \(track.title, privacy: .public) -> \(dest.lastPathComponent, privacy: .public)")
        lastImportStage = "success"
    }

    func delete(atOffsets offsets: IndexSet, fromPlaylistId pid: UUID? = nil) {
        let targetId = pid ?? currentPlaylistId ?? playlists.first?.id
        guard let idx = playlists.firstIndex(where: { $0.id == targetId }) else { return }
        
        var tracks = playlists[idx].tracks
        let tracksToDelete: [Track] = offsets.compactMap { i in
            tracks.indices.contains(i) ? tracks[i] : nil
        }
        
        // If deleting from current playing playlist
        if targetId == currentPlaylistId {
            for i in offsets.sorted(by: >) {
                if currentIndex == i {
                    pause()
                    player.replaceCurrentItem(with: nil)
                    currentIndex = nil
                    currentTime = 0
                    duration = 0
                } else if let cur = currentIndex, i < cur {
                    currentIndex = cur - 1
                }
            }
        }
        
        tracks.remove(atOffsets: offsets)
        playlists[idx].tracks = tracks
        
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
            for t in tracksToDelete {
                let url = t.url.standardizedFileURL
                if url.isFileURL, url.path.hasPrefix(dir.path) {
                    try? fm.removeItem(at: url)
                    
                    // Also delete associated lrc file if it exists
                    let lrcUrl = url.deletingPathExtension().appendingPathExtension("lrc")
                    try? fm.removeItem(at: lrcUrl)
                }
            }
        }
    }

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlay()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
        
        if let data = track.artworkData, let image = UIImage(data: data) {
            // Check if we have a current lyric to display
            if let idx = currentLyricIndex, parsedLyrics.indices.contains(idx) {
                let currentLine = parsedLyrics[idx].text
                if let lyricImage = image.withLyricsOverlay(currentLine) {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: lyricImage.size) { _ in lyricImage }
                } else {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
            } else {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func fetchLyrics(for track: Track, playlistId: UUID, index: Int) {
        LyricFetcher.fetch(for: track.title, artist: track.artist) { [weak self] lyrics in
            guard let self = self, let lyrics = lyrics, !lyrics.isEmpty else { return }
            
            DispatchQueue.main.async {
                self.saveLyrics(lyrics, for: track, playlistId: playlistId, index: index)
            }
        }
    }

    private func fetchArtwork(for track: Track, playlistId: UUID, index: Int) {
        AlbumArtFetcher.fetch(for: track.title, artist: track.artist) { [weak self] data in
            guard let self = self, let data = data else { return }
            
            // Save to sidecar file
            let jpgURL = track.url.deletingPathExtension().appendingPathExtension("jpg")
            try? data.write(to: jpgURL)
            
            DispatchQueue.main.async {
                // Update track in playlist
                if let plIndex = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                    var tracks = self.playlists[plIndex].tracks
                    if tracks.indices.contains(index) {
                        let oldTrack = tracks[index]
                        // Only update if it's the same track (id check)
                        if oldTrack.id == track.id {
                            let newTrack = Track(
                                title: oldTrack.title,
                                artist: oldTrack.artist,
                                url: oldTrack.url,
                                artworkData: data,
                                lyrics: oldTrack.lyrics
                            )
                            tracks[index] = newTrack
                            self.playlists[plIndex].tracks = tracks
                            
                            // If currently playing this track, update info
                            if self.currentPlaylistId == playlistId && self.currentIndex == index {
                                self.updateNowPlayingInfo()
                            }
                        }
                    }
                }
            }
        }
    }
    
    func replaceCurrentArtwork(with data: Data) {
        guard let pid = currentPlaylistId, let idx = currentIndex else { return }
        guard let plIndex = playlists.firstIndex(where: { $0.id == pid }) else { return }
        var tracks = playlists[plIndex].tracks
        guard tracks.indices.contains(idx) else { return }
        let track = tracks[idx]
        let jpgURL = track.url.deletingPathExtension().appendingPathExtension("jpg")
        try? data.write(to: jpgURL)
        let newTrack = Track(title: track.title, artist: track.artist, url: track.url, artworkData: data, lyrics: track.lyrics)
        tracks[idx] = newTrack
        playlists[plIndex].tracks = tracks
        updateNowPlayingInfo()
    }
    
    func replaceCurrentLyrics(with text: String) {
        guard let pid = currentPlaylistId, let idx = currentIndex else { return }
        guard let plIndex = playlists.firstIndex(where: { $0.id == pid }) else { return }
        var tracks = playlists[plIndex].tracks
        guard tracks.indices.contains(idx) else { return }
        let track = tracks[idx]
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        try? text.write(to: lrcURL, atomically: true, encoding: .utf8)
        let newTrack = Track(title: track.title, artist: track.artist, url: track.url, artworkData: track.artworkData, lyrics: text)
        tracks[idx] = newTrack
        playlists[plIndex].tracks = tracks
        parseCurrentLyrics()
        updateNowPlayingInfo()
    }
    
    private func saveLyrics(_ lyrics: String, for track: Track, playlistId: UUID, index: Int) {
        // Save to .lrc file
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        do {
            try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
            print("Saved lyrics to \(lrcURL.path)")
        } catch {
            print("Failed to save lyrics file: \(error)")
        }
        
        // Update in memory
        if let pIdx = self.playlists.firstIndex(where: { $0.id == playlistId }) {
            var pl = self.playlists[pIdx]
            if pl.tracks.indices.contains(index) {
                // Create new track with lyrics
                let old = pl.tracks[index]
                let newTrack = Track(title: old.title, artist: old.artist, url: old.url, artworkData: old.artworkData, lyrics: lyrics)
                pl.tracks[index] = newTrack
                self.playlists[pIdx] = pl
                
                // If currently playing this track, re-parse
                if self.currentPlaylistId == playlistId && self.currentIndex == index {
                    self.parseCurrentLyrics()
                }
            }
        }
    }
    
    private func parseCurrentLyrics() {
        guard let lyrics = currentTrack?.lyrics, !lyrics.isEmpty else {
            parsedLyrics = []
            currentLyricIndex = nil
            return
        }
        
        var lines: [LyricLine] = []
        // Regex to match timestamps like [00:12.34] or [01:02]
        // Group 1: MM, Group 2: SS.xx
        let pattern = "\\[(\\d+):(\\d+(?:\\.\\d+)?)\\](.*)"
        
        // We iterate line by line
        let rawLines = lyrics.components(separatedBy: .newlines)
        
        // Pre-compile regex is better but string matching is okay for now
        let regex = try? NSRegularExpression(pattern: pattern)
        
        for line in rawLines {
            let nsString = line as NSString
            let range = NSRange(location: 0, length: nsString.length)
            
            if let match = regex?.firstMatch(in: line, options: [], range: range) {
                if match.numberOfRanges >= 4 {
                    let minStr = nsString.substring(with: match.range(at: 1))
                    let secStr = nsString.substring(with: match.range(at: 2))
                    let content = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if let min = Double(minStr), let sec = Double(secStr) {
                        let time = min * 60 + sec
                        lines.append(LyricLine(time: time, text: content))
                    }
                }
            } else {
                // Handle lines without timestamps if we want mixed content, 
                // but usually LRC is fully timestamped. 
                // For now, ignore lines without timestamps for sync mode, 
                // or treat them as comments.
            }
        }
        
        if lines.isEmpty {
            // If regex failed to find any timestamps, maybe it's plain text.
            // We can treat it as unsynced lyrics.
            // But parsedLyrics is specifically for synced lines.
            // We'll leave it empty so UI falls back to plain text scroll.
        } else {
            lines.sort { $0.time < $1.time }
        }
        
        parsedLyrics = lines
        currentLyricIndex = nil
    }
    
    private func updateCurrentLyricIndex() {
        guard !parsedLyrics.isEmpty else { return }
        
        // Find the last line that started before or at currentTime
        // We add a small offset (e.g. 0.2s) to make it feel snappier or match audio better if needed
        let time = currentTime + 0.2
        
        if let idx = parsedLyrics.lastIndex(where: { $0.time <= time }) {
            if currentLyricIndex != idx {
                currentLyricIndex = idx
                // Update lockscreen with new lyric line
                updateNowPlayingInfo()
            }
        } else {
            // Before first lyric
            if currentLyricIndex != nil {
                currentLyricIndex = nil
                updateNowPlayingInfo()
            }
        }
    }
}
