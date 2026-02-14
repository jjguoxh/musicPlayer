import Foundation
import AppKit

class AlbumArtFetcher {
    private static let session = URLSession.shared
    
    static func fetch(for title: String, artist: String, completion: @escaping (Data?) -> Void) {
        let term = "\(title) \(artist)"
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&media=music&entity=song&limit=1") else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artworkUrlString = first["artworkUrl100"] as? String else {
                completion(nil)
                return
            }
            
            let highResUrlString = artworkUrlString.replacingOccurrences(of: "100x100", with: "600x600")
            let firstUrl = URL(string: highResUrlString) ?? URL(string: artworkUrlString)
            guard let imgUrl = firstUrl else { completion(nil); return }
            
            session.dataTask(with: imgUrl) { imgData, _, _ in
                guard let imgData = imgData, NSImage(data: imgData) != nil else {
                    completion(nil)
                    return
                }
                completion(imgData)
            }.resume()
        }.resume()
    }
}
