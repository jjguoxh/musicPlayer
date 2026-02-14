import UIKit

extension UIImage {
    func withLyricsOverlay(_ text: String) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: self.size)
        
        return renderer.image { context in
            // Draw original image
            self.draw(at: .zero)
            
            // Configure text attributes
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineBreakMode = .byWordWrapping
            
            let fontSize = self.size.width * 0.06 // Dynamic font size based on image width
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
                .strokeColor: UIColor.black,
                .strokeWidth: -3.0, // Negative for stroke + fill
                .shadow: NSShadow()
            ]
            
            if let shadow = attributes[.shadow] as? NSShadow {
                shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
                shadow.shadowOffset = CGSize(width: 1, height: 1)
                shadow.shadowBlurRadius = 4
            }
            
            // Calculate text rect (bottom 20% of image)
            let textHeight = self.size.height * 0.25
            let textRect = CGRect(
                x: 20,
                y: self.size.height - textHeight - 20,
                width: self.size.width - 40,
                height: textHeight
            )
            
            // Draw text
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
}
