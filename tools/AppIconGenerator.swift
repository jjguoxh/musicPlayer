import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreImage

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func loadInputImage(base: URL) -> CGImage? {
    let cand1 = base.appendingPathComponent("musicPlayer").appendingPathComponent("guitar.jpeg")
    let cand2 = base.appendingPathComponent("musicPlayer").appendingPathComponent("guitar.png")
    let url = [cand1, cand2].first { FileManager.default.fileExists(atPath: $0.path) }
    guard let u = url, let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func makeMaskAndAverageColor(from image: CGImage) -> (CGImage?, (CGFloat, CGFloat, CGFloat)?) {
    guard let dataProvider = image.dataProvider, let data = dataProvider.data else { return (nil, nil) }
    let ptr = CFDataGetBytePtr(data)
    let width = image.width
    let height = image.height
    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow
    var alpha = Data(count: width * height)
    var sumR: Double = 0
    var sumG: Double = 0
    var sumB: Double = 0
    var count: Double = 0
    alpha.withUnsafeMutableBytes { buf in
        let a = buf.bindMemory(to: UInt8.self).baseAddress!
        for y in 0..<height {
            for x in 0..<width {
                let p = y * bytesPerRow + x * bytesPerPixel
                let r = ptr![p]
                let g = ptr![p+1]
                let b = ptr![p+2]
                let rf = Double(r) / 255.0
                let gf = Double(g) / 255.0
                let bf = Double(b) / 255.0
                let maxV = max(rf, max(gf, bf))
                let minV = min(rf, min(gf, bf))
                let sat = maxV > 0 ? (maxV - minV) / maxV : 0
                let val = maxV
                let nearWhite = (r > 240 && g > 240 && b > 240)
                let lowSatHighVal = (val > 0.92 && sat < 0.18)
                let isWhite = nearWhite || lowSatHighVal
                a[y * width + x] = isWhite ? 0 : 255
                if !isWhite {
                    sumR += Double(r)
                    sumG += Double(g)
                    sumB += Double(b)
                    count += 1
                }
            }
        }
    }
    guard let provider = CGDataProvider(data: alpha as CFData) else { return (nil, nil) }
    let mask = CGImage(maskWidth: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, provider: provider, decode: nil, shouldInterpolate: false)
    if count > 0 {
        let r = CGFloat(sumR / (255.0 * count))
        let g = CGFloat(sumG / (255.0 * count))
        let b = CGFloat(sumB / (255.0 * count))
        return (mask, (r, g, b))
    } else {
        return (mask, nil)
    }
}

func makeIcon(size: Int, base: URL) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    guard let src = loadInputImage(base: base) else { return nil }
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let maskAndColor = makeMaskAndAverageColor(from: src)
    let mask = maskAndColor.0
    if let avg = maskAndColor.1 {
        r = avg.0
        g = avg.1
        b = avg.2
    } else {
        r = 0.6
        g = 0.3
        b = 0.2
    }
    let top = color(max(r*0.5, 0), max(g*0.5, 0), max(b*0.5, 0))
    let bottom = color(min(r*1.2, 1), min(g*1.2, 1), min(b*1.2, 1))
    let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])
    guard let maskImg = mask else { return ctx.makeImage() }
    let srcW = CGFloat(src.width)
    let srcH = CGFloat(src.height)
    let scale = min(CGFloat(size) * 0.80 / srcW, CGFloat(size) * 0.80 / srcH)
    let w = srcW * scale
    let h = srcH * scale
    let rect = CGRect(x: (CGFloat(size)-w)/2, y: (CGFloat(size)-h)/2, width: w, height: h)
    ctx.saveGState()
    ctx.clip(to: rect, mask: maskImg)
    ctx.draw(src, in: rect)
    ctx.restoreGState()
    return ctx.makeImage()
}

func savePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let env = ProcessInfo.processInfo.environment
let projectDir = URL(fileURLWithPath: env["PROJECT_DIR"] ?? FileManager.default.currentDirectoryPath)
let candidates = [
    projectDir
        .appendingPathComponent("musicPlayer")
        .appendingPathComponent("Assets.xcassets")
        .appendingPathComponent("AppIconMain.appiconset"),
    projectDir
        .appendingPathComponent("musicPlayer")
        .appendingPathComponent("musicPlayer")
        .appendingPathComponent("Assets.xcassets")
        .appendingPathComponent("AppIconMain.appiconset")
]
let appIconPath = candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates.last!
let output = appIconPath.appendingPathComponent("AppIconMain-1024.png")
if let img = makeIcon(size: 1024, base: projectDir) {
    savePNG(img, to: output)
    print("Generated \(output.path)")
} else {
    print("Generation failed")
}
