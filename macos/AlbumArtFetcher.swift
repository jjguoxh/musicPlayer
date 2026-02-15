import Foundation
import AppKit

class AlbumArtFetcher {
    private static let session = URLSession.shared
    
    static func fetch(for title: String, artist: String, completion: @escaping (Data?) -> Void) {
        let term = "\(title) \(artist)"
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&media=music&entity=song&limit=10") else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  !results.isEmpty else {
                completion(nil)
                return
            }
            let ranked = results.compactMap { r -> (Int, String)? in
                guard let art = r["artworkUrl100"] as? String else { return nil }
                let s = score(result: r, title: title, artist: artist)
                return (s, art)
            }.sorted { $0.0 > $1.0 }
            let bestArt = ranked.first?.1 ?? (results.first?["artworkUrl100"] as? String ?? "")
            guard !bestArt.isEmpty else { completion(nil); return }
            let variants = imageVariants(from: bestArt)
            downloadImagesSequential(variants, index: 0, completion: completion)
        }.resume()
    }
    
    private static func normalize(_ s: String) -> String {
        let filtered = s.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        let lowered = filtered.lowercased()
        let condensed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return condensed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func score(result: [String: Any], title: String, artist: String) -> Int {
        let t = normalize(title)
        let a = normalize(artist)
        let rt = normalize((result["trackName"] as? String) ?? (result["trackCensoredName"] as? String) ?? "")
        let ra = normalize((result["artistName"] as? String) ?? "")
        let rc = normalize((result["collectionName"] as? String) ?? "")
        var s = 0
        if !t.isEmpty && !rt.isEmpty {
            if t == rt { s += 50 } else if rt.contains(t) || t.contains(rt) { s += 25 }
        }
        if !a.isEmpty && !ra.isEmpty {
            if a == ra { s += 50 } else if ra.contains(a) || a.contains(ra) { s += 25 }
        }
        if !rc.isEmpty && !t.isEmpty && rc.contains(t) { s += 10 }
        if s == 0 && (!(rt.isEmpty) || !(ra.isEmpty)) { s = 1 }
        return s
    }
    
    private static func imageVariants(from original: String) -> [URL] {
        let sizes = ["1200x1200", "600x600", "100x100"]
        var urls: [URL] = []
        for size in sizes {
            let s = original.replacingOccurrences(of: "100x100", with: size)
            if let u = URL(string: s) { urls.append(u) }
        }
        if let u = URL(string: original), !urls.contains(u) { urls.append(u) }
        return urls
    }
    
    private static func downloadImagesSequential(_ urls: [URL], index: Int, completion: @escaping (Data?) -> Void) {
        if index >= urls.count { completion(nil); return }
        session.dataTask(with: urls[index]) { data, _, _ in
            if let data = data, NSImage(data: data) != nil {
                completion(data)
            } else {
                downloadImagesSequential(urls, index: index + 1, completion: completion)
            }
        }.resume()
    }
}
