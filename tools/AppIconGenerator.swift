import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func makeIcon(size: Int) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let bgTop = color(0.18, 0.08, 0.06)
    let bgBottom = color(0.35, 0.18, 0.12)
    let gradColors = [bgTop, bgBottom] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0,1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

    ctx.saveGState()
    ctx.translateBy(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.56)
    ctx.rotate(by: CGFloat(20.0 * CGFloat.pi / 180.0))
    let body = CGMutablePath()
    body.addEllipse(in: CGRect(x: -CGFloat(size)*0.27, y: -CGFloat(size)*0.31, width: CGFloat(size)*0.54, height: CGFloat(size)*0.62))
    ctx.addPath(body)
    ctx.setFillColor(color(0.60, 0.20, 0.15))
    ctx.fillPath()

    let hole = CGMutablePath()
    hole.addEllipse(in: CGRect(x: -CGFloat(size)*0.06, y: -CGFloat(size)*0.06, width: CGFloat(size)*0.12, height: CGFloat(size)*0.12))
    ctx.addPath(hole)
    ctx.setFillColor(color(0.10, 0.05, 0.04))
    ctx.fillPath()

    let neck = CGMutablePath()
    neck.addRoundedRect(in: CGRect(x: CGFloat(size)*0.10, y: -CGFloat(size)*0.05, width: CGFloat(size)*0.35, height: CGFloat(size)*0.10), cornerWidth: CGFloat(size)*0.02, cornerHeight: CGFloat(size)*0.02)
    ctx.addPath(neck)
    ctx.setFillColor(color(0.45, 0.25, 0.18))
    ctx.fillPath()

    ctx.setStrokeColor(color(0.90, 0.90, 0.90))
    ctx.setLineWidth(CGFloat(size) * 0.004)
    for i in 0..<6 {
        let y = CGFloat(i) * CGFloat(size) * 0.012
        ctx.move(to: CGPoint(x: -CGFloat(size)*0.20, y: y))
        ctx.addLine(to: CGPoint(x: CGFloat(size)*0.28, y: y))
        ctx.strokePath()
    }
    ctx.restoreGState()

    ctx.setStrokeColor(color(1, 1, 1, 0.9))
    ctx.setLineWidth(CGFloat(size) * 0.01)
    let staffY = CGFloat(size) * 0.28
    for i in 0..<5 {
        let y = staffY + CGFloat(i) * CGFloat(size) * 0.02
        ctx.move(to: CGPoint(x: CGFloat(size) * 0.60, y: y))
        ctx.addLine(to: CGPoint(x: CGFloat(size) * 0.92, y: y))
        ctx.strokePath()
    }
    let noteRect = CGRect(x: CGFloat(size)*0.72, y: staffY + CGFloat(size)*0.035, width: CGFloat(size)*0.04, height: CGFloat(size)*0.04)
    let note = CGMutablePath()
    note.addEllipse(in: noteRect)
    ctx.addPath(note)
    ctx.setFillColor(color(1, 1, 1, 0.95))
    ctx.fillPath()
    ctx.move(to: CGPoint(x: noteRect.maxX, y: noteRect.midY))
    ctx.addLine(to: CGPoint(x: noteRect.maxX, y: noteRect.midY - CGFloat(size)*0.10))
    ctx.strokePath()

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
if let img = makeIcon(size: 1024) {
    savePNG(img, to: output)
    print("Generated \(output.path)")
} else {
    print("Generation failed")
}
