import Foundation

struct LyricFetcher {
    private static let session = URLSession.shared
    
    /// Try to fetch lyrics from multiple sources (LrcLib -> QQMusic)
    static func fetch(for title: String, artist: String, completion: @escaping (String?) -> Void) {
        // 1. Try LrcLib first
        fetchFromLrcLib(title: title, artist: artist) { lrcLibResult in
            if let lrc = lrcLibResult, lrc.hasChinese {
                print("[LyricFetcher] Found Chinese lyrics from LrcLib")
                completion(lrc)
                return
            }
            
            // 2. If LrcLib failed or returned non-Chinese (e.g. Pinyin), try QQMusic
            print("[LyricFetcher] LrcLib missing or non-Chinese. Trying QQMusic...")
            fetchFromQQMusic(title: title, artist: artist) { qqResult in
                if let qq = qqResult {
                    print("[LyricFetcher] Found lyrics from QQMusic")
                    completion(qq)
                } else {
                    // 3. Fallback to LrcLib result even if Pinyin (better than nothing)
                    // or return nil if strict
                    print("[LyricFetcher] QQMusic failed. Returning LrcLib result (if any)")
                    completion(lrcLibResult)
                }
            }
        }
    }
    
    // MARK: - LrcLib
    
    private struct LrcLibResponse: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
    }
    
    private static func fetchFromLrcLib(title: String, artist: String, completion: @escaping (String?) -> Void) {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encodedTitle)%20\(encodedArtist)") else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let results = try? JSONDecoder().decode([LrcLibResponse].self, from: data),
                  let first = results.first else {
                completion(nil)
                return
            }
            completion(first.syncedLyrics ?? first.plainLyrics)
        }.resume()
    }
    
    // MARK: - QQ Music
    
    private static func fetchFromQQMusic(title: String, artist: String, completion: @escaping (String?) -> Void) {
        // Search first
        searchQQMusic(keyword: "\(title) \(artist)") { songMid in
            guard let mid = songMid else {
                // Try searching just title if artist search fails
                searchQQMusic(keyword: title) { mid2 in
                    guard let m2 = mid2 else { completion(nil); return }
                    fetchQQLyric(songMid: m2, completion: completion)
                }
                return
            }
            fetchQQLyric(songMid: mid, completion: completion)
        }
    }
    
    private static func searchQQMusic(keyword: String, completion: @escaping (String?) -> Void) {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=\(encoded)&format=json") else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let song = dataDict["song"] as? [String: Any],
                  let list = song["list"] as? [[String: Any]],
                  let first = list.first,
                  let songmid = first["songmid"] as? String else {
                completion(nil)
                return
            }
            completion(songmid)
        }.resume()
    }
    
    private static func fetchQQLyric(songMid: String, completion: @escaping (String?) -> Void) {
        let urlStr = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songMid)&format=json&nobase64=1"
        guard let url = URL(string: urlStr) else { completion(nil); return }
        
        var request = URLRequest(url: url)
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        
        session.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyric = json["lyric"] as? String else {
                completion(nil)
                return
            }
            // QQ Music lyrics might need simple cleanup if any (usually standard LRC)
            completion(lyric)
        }.resume()
    }
}

