import Foundation

enum LyricFetcher {
    private static let session = URLSession.shared
    
    static func fetch(for title: String, artist: String, completion: @escaping (String?) -> Void) {
        fetchFromLrcLib(title: title, artist: artist) { lrc in
            if let lrc = lrc, !lrc.isEmpty {
                completion(lrc)
            } else {
                fetchFromQQMusic(title: title, artist: artist, completion: completion)
            }
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
                  let first = results.first else { completion(nil); return }
            completion(first.syncedLyrics ?? first.plainLyrics)
        }.resume()
    }
    
    private static func fetchFromQQMusic(title: String, artist: String, completion: @escaping (String?) -> Void) {
        searchQQMusic(keyword: "\(title) \(artist)") { mid in
            guard let mid = mid else {
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
            completion(nil); return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let song = dataDict["song"] as? [String: Any],
                  let list = song["list"] as? [[String: Any]],
                  let first = list.first,
                  let songmid = first["songmid"] as? String else { completion(nil); return }
            completion(songmid)
        }.resume()
    }
    
    private static func fetchQQLyric(songMid: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songMid)&format=json") else {
            completion(nil); return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyric = json["lyric"] as? String else { completion(nil); return }
            completion(lyric)
        }.resume()
    }
}

struct LrcLibResponse: Decodable {
    let plainLyrics: String?
    let syncedLyrics: String?
}
