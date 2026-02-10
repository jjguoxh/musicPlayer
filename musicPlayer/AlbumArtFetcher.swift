import Foundation
import Combine
import UIKit

class AlbumArtFetcher {
    private static let session = URLSession.shared
    
    static func fetch(for title: String, artist: String, completion: @escaping (Data?) -> Void) {
        let term = "\(title) \(artist)"
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&media=music&entity=song&limit=1") else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstResult = results.first,
                   let artworkUrlString = firstResult["artworkUrl100"] as? String {
                    
                    // Try to get a higher resolution image
                    let highResUrlString = artworkUrlString.replacingOccurrences(of: "100x100", with: "600x600")
                    if let highResUrl = URL(string: highResUrlString) {
                        downloadImage(from: highResUrl) { highResData in
                            if let data = highResData {
                                completion(data)
                            } else {
                                // Fallback to original URL
                                if let originalUrl = URL(string: artworkUrlString) {
                                    downloadImage(from: originalUrl, completion: completion)
                                } else {
                                    completion(nil)
                                }
                            }
                        }
                    } else if let originalUrl = URL(string: artworkUrlString) {
                        downloadImage(from: originalUrl, completion: completion)
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    private static func downloadImage(from url: URL, completion: @escaping (Data?) -> Void) {
        session.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let _ = UIImage(data: data) else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }
}
