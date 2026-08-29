// Renders the 1024px app icon PNG (rounded macOS squircle + shadow).
// usage: swift IconTool.swift output.png [input-artwork.png]
// With input artwork: masks it into the icon shape. Without: draws a procedural glowing ring.
import AppKit
import ImageIO

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: IconTool output.png [input.png]")
    exit(1)
}
let outPath = args[1]
let inPath: String? = args.count > 2 ? args[2] : nil

let S = 1024
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("no context"); exit(1)
}

// Apple icon grid: 824x824 rounded rect centered in 1024 canvas.
let box = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow under the icon plate.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 0.05, green: 0.04, blue: 0.10, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()

var drewArtwork = false
if let inPath,
   let img = NSImage(contentsOfFile: inPath),
   let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
    let scale = max(box.width / iw, box.height / ih)
    let dw = iw * scale, dh = ih * scale
    ctx.draw(cg, in: CGRect(x: box.midX - dw / 2, y: box.midY - dh / 2, width: dw, height: dh))
    drewArtwork = true
}

if !drewArtwork {
    // Procedural fallback: midnight gradient + glowing ember ring.
    let colors = [CGColor(red: 0.11, green: 0.08, blue: 0.24, alpha: 1),
                  CGColor(red: 0.02, green: 0.02, blue: 0.07, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: box.midX, y: box.maxY),
                           end: CGPoint(x: box.midX, y: box.minY),
                           options: [])
    let center = CGPoint(x: box.midX, y: box.midY)
    ctx.setShadow(offset: .zero, blur: 90, color: CGColor(red: 1, green: 0.5, blue: 0.25, alpha: 0.9))
    ctx.setStrokeColor(CGColor(red: 1, green: 0.55, blue: 0.28, alpha: 1))
    ctx.setLineWidth(58)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: 240, startAngle: .pi * 0.5, endAngle: .pi * 2.2, clockwise: false)
    ctx.strokePath()
}
ctx.restoreGState()

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 "public.png" as CFString, 1, nil) else {
    print("write failed"); exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
