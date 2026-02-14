import Foundation
import Combine
import AVFoundation
import AppKit
import CoreFoundation

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

extension String {
    var hasChinese: Bool {
        range(of: "\\p{Han}", options: .regularExpression) != nil
    }
}

private func decodeBest(_ data: Data) -> String? {
    let encs: [CFStringEncoding] = [
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue),
        CFStringEncoding(CFStringEncodings.GBK_95.rawValue),
        CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue),
        CFStringEncoding(CFStringEncodings.big5.rawValue),
        CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
    ]
    for e in encs {
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(e)
        if let s = String(data: data, encoding: String.Encoding(rawValue: nsEnc)), s.hasChinese {
            return s
        }
    }
    if let s = String(data: data, encoding: .utf8), s.hasChinese { return s }
    return nil
}

private func hasMojibake(_ s: String) -> Bool {
    if s.hasChinese { return false }
    let indicators = ["Ã", "Â", "æ", "å", "ä", "ç", "é", "è", "ê", "ð", "œ", "¢", "£", "¥", "¿", "×"]
    return indicators.contains(where: { s.contains($0) })
}

private func fixMojibakeLatin1UTF8(_ s: String) -> String? {
    guard let d = s.data(using: .isoLatin1) else { return nil }
    if let r = String(data: d, encoding: .utf8), r.hasChinese { return r }
    return nil
}

private func parseFilename(_ url: URL) -> (artist: String?, title: String?) {
    let base = url.deletingPathExtension().lastPathComponent
    let seps: [Character] = ["-", "—", "–", "_"]
    for sep in seps {
        if base.contains(sep) {
            let parts = base.split(separator: sep, maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                return (artist: parts[0], title: parts[1])
            }
        }
    }
    return (artist: nil, title: base)
}

final class PlayerViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var currentPlaylistId: UUID?
    @Published var currentIndex: Int?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var parsedLyrics: [LyricLine] = []
    @Published var currentLyricIndex: Int?
    @Published var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }
    
    private var player = AVPlayer()
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let fm = FileManager.default
    
    init() {
        self.playlists = [Playlist(name: "播放列表", tracks: [])]
        self.currentPlaylistId = self.playlists.first?.id
        addTimeObserver()
        loadLibrary()
        player.volume = volume
    }
    
    deinit {
        if let o = timeObserver { player.removeTimeObserver(o) }
    }
    
    var currentPlaylist: Playlist? {
        guard let id = currentPlaylistId else { return playlists.first }
        return playlists.first(where: { $0.id == id })
    }
    
    var currentTrack: Track? {
        guard let idx = currentIndex, let pl = currentPlaylist, pl.tracks.indices.contains(idx) else { return nil }
        return pl.tracks[idx]
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
        }
    }
    
    func play(playlistId: UUID? = nil, index: Int) {
        if let pid = playlistId { currentPlaylistId = pid }
        guard let pl = currentPlaylist, pl.tracks.indices.contains(index) else { return }
        currentIndex = index
        let item = AVPlayerItem(url: pl.tracks[index].url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        parseCurrentLyrics()
        
        let track = pl.tracks[index]
        let currentLyrics = track.lyrics ?? ""
        if currentLyrics.isEmpty {
            fetchLyrics(for: track, playlistId: pl.id, index: index)
        }
        if track.artworkData == nil {
            fetchArtwork(for: track, playlistId: pl.id, index: index)
        }
    }
    
    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    func pause() {
        player.pause()
        isPlaying = false
    }
    
    func next() {
        guard let idx = currentIndex, let pl = currentPlaylist else {
            if let pl = currentPlaylist, !pl.tracks.isEmpty { play(index: 0) }
            return
        }
        let nextIdx = idx + 1
        if pl.tracks.indices.contains(nextIdx) {
            play(index: nextIdx)
        } else {
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
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }
    
    private func updateCurrentLyricIndex() {
        guard !parsedLyrics.isEmpty else { return }
        let time = currentTime + 0.2
        if let idx = parsedLyrics.lastIndex(where: { $0.time <= time }) {
            if currentLyricIndex != idx { currentLyricIndex = idx }
        } else {
            currentLyricIndex = nil
        }
    }
    
    private func loadLibrary() {
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let destDir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
        if !fm.fileExists(atPath: destDir.path) { return }
        do {
            let fileURLs = try fm.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)
            let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff"]
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
        } catch {}
    }
    
    func addLocalFiles(urls: [URL]) {
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let destDir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
        if !fm.fileExists(atPath: destDir.path) {
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }
        var appended: [Track] = []
        for sourceURL in urls {
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
            do {
                try fm.copyItem(at: sourceURL, to: dest)
                let track = createTrack(from: dest)
                appended.append(track)
            } catch {
            }
        }
        if !appended.isEmpty {
            if playlists.isEmpty {
                playlists = [Playlist(name: "播放列表", tracks: appended)]
            } else {
                playlists[0].tracks.append(contentsOf: appended)
            }
        }
    }
    
    func clearLibrary() {
        pause()
        player.replaceCurrentItem(with: nil)
        currentIndex = nil
        currentTime = 0
        duration = 0
        if !playlists.isEmpty {
            let toDelete = playlists[0].tracks
            playlists[0].tracks = []
            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let dir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
                for t in toDelete {
                    let url = t.url.standardizedFileURL
                    if url.isFileURL, url.path.hasPrefix(dir.path) {
                        try? fm.removeItem(at: url)
                        let lrcUrl = url.deletingPathExtension().appendingPathExtension("lrc")
                        try? fm.removeItem(at: lrcUrl)
                        let jpgUrl = url.deletingPathExtension().appendingPathExtension("jpg")
                        try? fm.removeItem(at: jpgUrl)
                    }
                }
            }
        }
    }
    
    private func createTrack(from url: URL) -> Track {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = ""
        var artworkData: Data?
        var lyrics: String?
        var titleRaw: Data?
        var artistRaw: Data?
        for meta in asset.commonMetadata {
            if meta.commonKey == .commonKeyTitle {
                if let v = meta.value as? String { title = v } else if let d = meta.dataValue { titleRaw = d }
            }
            if meta.commonKey == .commonKeyArtist {
                if let v = meta.value as? String { artist = v } else if let d = meta.dataValue { artistRaw = d }
            }
        }
        if !title.hasChinese, let d = titleRaw, let s = decodeBest(d) { title = s }
        if !artist.hasChinese, let d = artistRaw, let s = decodeBest(d) { artist = s }
        if !title.hasChinese, hasMojibake(title), let fixed = fixMojibakeLatin1UTF8(title) { title = fixed }
        if !artist.hasChinese, hasMojibake(artist), let fixed = fixMojibakeLatin1UTF8(artist) { artist = fixed }
        let parsed = parseFilename(url)
        if (artist.isEmpty || !artist.hasChinese), let a = parsed.artist, a.hasChinese { artist = a }
        if (!title.hasChinese), let t = parsed.title, t.hasChinese { title = t }
        let allMetadata = asset.commonMetadata
            + asset.metadata(forFormat: AVMetadataFormat.id3Metadata)
            + asset.metadata(forFormat: AVMetadataFormat.iTunesMetadata)
        for item in allMetadata {
            if artworkData == nil {
                if item.commonKey == .commonKeyArtwork || item.identifier == .id3MetadataAttachedPicture || item.identifier == .iTunesMetadataCoverArt {
                    if let data = item.dataValue {
                        artworkData = data
                    } else if let image = item.value as? NSImage {
                        artworkData = image.tiffRepresentation
                    }
                }
            }
            if lyrics == nil {
                if item.identifier == .id3MetadataUnsynchronizedLyric || item.identifier == .iTunesMetadataLyrics {
                    if let v = item.stringValue, !v.isEmpty {
                        if v.hasChinese {
                            lyrics = v
                        } else if let d = item.dataValue, let s = decodeBest(d) {
                            lyrics = s
                        } else {
                            lyrics = v
                        }
                    }
                }
            }
            if artworkData != nil && lyrics != nil { break }
        }
        if lyrics == nil {
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                lyrics = content
            } else if let data = try? Data(contentsOf: lrcURL), let s = decodeBest(data) {
                lyrics = s
            }
        }
        if artworkData == nil {
            let jpgURL = url.deletingPathExtension().appendingPathExtension("jpg")
            if let data = try? Data(contentsOf: jpgURL) { artworkData = data }
        }
        return Track(title: title, artist: artist, url: url, artworkData: artworkData, lyrics: lyrics)
    }
    
    private func fetchLyrics(for track: Track, playlistId: UUID, index: Int) {
        LyricFetcher.fetch(for: track.title, artist: track.artist) { [weak self] lyrics in
            guard let self = self, let lyrics = lyrics, !lyrics.isEmpty else { return }
            DispatchQueue.main.async { self.saveLyrics(lyrics, for: track, playlistId: playlistId, index: index) }
        }
    }
    
    private func saveLyrics(_ lyrics: String, for track: Track, playlistId: UUID, index: Int) {
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
        try? lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        if let pIdx = self.playlists.firstIndex(where: { $0.id == playlistId }) {
            var pl = self.playlists[pIdx]
            if pl.tracks.indices.contains(index) {
                let old = pl.tracks[index]
                let newTrack = Track(title: old.title, artist: old.artist, url: old.url, artworkData: old.artworkData, lyrics: lyrics)
                pl.tracks[index] = newTrack
                self.playlists[pIdx] = pl
                if self.currentPlaylistId == playlistId && self.currentIndex == index {
                    self.parseCurrentLyrics()
                }
            }
        }
    }
    
    private func fetchArtwork(for track: Track, playlistId: UUID, index: Int) {
        AlbumArtFetcher.fetch(for: track.title, artist: track.artist) { [weak self] data in
            guard let self = self, let data = data else { return }
            let jpgURL = track.url.deletingPathExtension().appendingPathExtension("jpg")
            try? data.write(to: jpgURL)
            DispatchQueue.main.async {
                if let plIndex = self.playlists.firstIndex(where: { $0.id == playlistId }) {
                    var tracks = self.playlists[plIndex].tracks
                    if tracks.indices.contains(index) {
                        let oldTrack = tracks[index]
                        if oldTrack.id == track.id {
                            let newTrack = Track(title: oldTrack.title, artist: oldTrack.artist, url: oldTrack.url, artworkData: data, lyrics: oldTrack.lyrics)
                            tracks[index] = newTrack
                            self.playlists[plIndex].tracks = tracks
                        }
                    }
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
        let pattern = "\\[(\\d+):(\\d+(?:\\.\\d+)?)\\](.*)"
        let rawLines = lyrics.components(separatedBy: .newlines)
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
            }
        }
        lines.sort { $0.time < $1.time }
        parsedLyrics = lines
        currentLyricIndex = nil
    }
    
    func delete(atOffsets offsets: IndexSet, fromPlaylistId pid: UUID? = nil) {
        let targetId = pid ?? currentPlaylistId ?? playlists.first?.id
        guard let idx = playlists.firstIndex(where: { $0.id == targetId }) else { return }
        var tracks = playlists[idx].tracks
        let tracksToDelete: [Track] = offsets.compactMap { i in
            tracks.indices.contains(i) ? tracks[i] : nil
        }
        tracks.remove(atOffsets: offsets)
        playlists[idx].tracks = tracks
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = docs.appendingPathComponent("ImportedMusic", isDirectory: true)
            for t in tracksToDelete {
                let url = t.url.standardizedFileURL
                if url.isFileURL, url.path.hasPrefix(dir.path) {
                    try? fm.removeItem(at: url)
                    let lrcUrl = url.deletingPathExtension().appendingPathExtension("lrc")
                    try? fm.removeItem(at: lrcUrl)
                }
            }
        }
    }
}
