import Foundation

enum LyricFetcher {
    private static let session = URLSession.shared
    
    static func fetch(for title: String, artist: String, completion: @escaping (String?) -> Void) {
        fetchFromLrcLib(title: title, artist: artist) { lrc in
            if let lrc = lrc, !lrc.isEmpty { completion(lrc) }
            else { fetchFromQQMusic(title: title, artist: artist, completion: completion) }
        }
    }
    
    private static func fetchFromLrcLib(title: String, artist: String, completion: @escaping (String?) -> Void) {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encodedTitle)%20\(encodedArtist)") else {
            completion(nil); return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let results = try? JSONDecoder().decode([LrcLibResponse].self, from: data),
                  !results.isEmpty else { completion(nil); return }
            let ranked = results.map { r -> (Int, String?) in
                var s = 0
                if let synced = r.syncedLyrics, !synced.isEmpty { s += 100; if synced.hasChinese { s += 10 } }
                if let plain = r.plainLyrics, !plain.isEmpty { s += 10; if plain.hasChinese { s += 5 } }
                return (s, r.syncedLyrics ?? r.plainLyrics)
            }.sorted { $0.0 > $1.0 }
            completion(ranked.first?.1)
        }.resume()
    }
    
    private static func fetchFromQQMusic(title: String, artist: String, completion: @escaping (String?) -> Void) {
        searchQQMusicCandidates(keyword: "\(title) \(artist)", targetTitle: title, targetArtist: artist) { mids in
            let candidates = mids.isEmpty ? [String]() : mids
            if candidates.isEmpty {
                searchQQMusicCandidates(keyword: title, targetTitle: title, targetArtist: artist) { mids2 in
                    tryFetchQQSequential(mids2, idx: 0, completion: completion)
                }
            } else {
                tryFetchQQSequential(candidates, idx: 0, completion: completion)
            }
        }
    }
    
    private static func searchQQMusicCandidates(keyword: String, targetTitle: String, targetArtist: String, completion: @escaping ([String]) -> Void) {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=\(encoded)&format=json") else {
            completion([]); return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let song = dataDict["song"] as? [String: Any],
                  let list = song["list"] as? [[String: Any]] else { completion([]); return }
            let ranked: [(Int, String)] = list.compactMap { item in
                guard let mid = item["songmid"] as? String else { return nil }
                let name = (item["songname"] as? String) ?? ""
                let singers = (item["singer"] as? [[String: Any]]) ?? []
                let artistNames = singers.compactMap { $0["name"] as? String }.joined(separator: " ")
                let s = scoreQQ(title: name, artists: artistNames, targetTitle: targetTitle, targetArtist: targetArtist)
                return (s, mid)
            }.sorted { $0.0 > $1.0 }
            completion(ranked.map { $0.1 })
        }.resume()
    }
    
    private static func fetchQQLyric(songMid: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songMid)&format=json&nobase64=1") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        session.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyric = json["lyric"] as? String else { completion(nil); return }
            completion(lyric)
        }.resume()
    }
    
    private static func tryFetchQQSequential(_ mids: [String], idx: Int, completion: @escaping (String?) -> Void) {
        if idx >= mids.count { completion(nil); return }
        fetchQQLyric(songMid: mids[idx]) { lyric in
            if let l = lyric, !l.isEmpty { completion(l) }
            else { tryFetchQQSequential(mids, idx: idx + 1, completion: completion) }
        }
    }
    
    private static func normalize(_ s: String) -> String {
        let filtered = s.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        let lowered = filtered.lowercased()
        let condensed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return condensed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func scoreQQ(title: String, artists: String, targetTitle: String, targetArtist: String) -> Int {
        let t = normalize(targetTitle)
        let a = normalize(targetArtist)
        let rt = normalize(title)
        let ra = normalize(artists)
        var s = 0
        if !t.isEmpty && !rt.isEmpty {
            if t == rt { s += 50 } else if rt.contains(t) || t.contains(rt) { s += 25 }
        }
        if !a.isEmpty && !ra.isEmpty {
            if a == ra { s += 50 } else if ra.contains(a) || a.contains(ra) { s += 25 }
        }
        if s == 0 && (!rt.isEmpty || !ra.isEmpty) { s = 1 }
        return s
    }
}

struct LrcLibResponse: Decodable {
    let plainLyrics: String?
    let syncedLyrics: String?
}
