// Prepares the DMG background from a source image (e.g. Resources/dmg-background.png):
// aspect-fill + center-crop to 1320x880 (660x440 @2x, matches Finder window).
import CoreGraphics
import ImageIO
import Foundation

let W = 1320, H = 880

guard CommandLine.arguments.count > 2 else {
    fputs("usage: prepare-dmg-background.swift <src> <dst>\n", stderr)
    exit(1)
}
let srcPath = CommandLine.arguments[1]
let dstPath = CommandLine.arguments[2]

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fputs("cannot load \(srcPath)\n", stderr)
    exit(1)
}

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }

// Aspect-fit (never crop: text near edges survives): scale so the whole
// image fits W×H, center it, and edge-extend the shortfall by stretching
// the source's outermost row/column (seamless for skies/gradients).
let sx = CGFloat(W) / CGFloat(img.width)
let sy = CGFloat(H) / CGFloat(img.height)
let s = min(sx, sy)
let dw = CGFloat(img.width) * s
let dh = CGFloat(img.height) * s
let dx = (CGFloat(W) - dw) / 2.0
let dy = (CGFloat(H) - dh) / 2.0
let iw = CGFloat(img.width), ih = CGFloat(img.height)
ctx.interpolationQuality = .high
func strip(_ r: CGRect) -> CGImage {
    guard let c = img.cropping(to: r) else {
        fputs("crop failed \(r)\n", stderr)
        exit(1)
    }
    return c
}
if dx > 0 {
    // pillarbox: stretch left/right columns full height
    ctx.draw(strip(CGRect(x: 0, y: 0, width: 1, height: ih)),
             in: CGRect(x: 0, y: 0, width: dx, height: CGFloat(H)))
    ctx.draw(strip(CGRect(x: iw - 1, y: 0, width: 1, height: ih)),
             in: CGRect(x: dx + dw, y: 0, width: dx, height: CGFloat(H)))
}
if dy > 0 {
    // letterbox: stretch top/bottom rows across the fitted width
    // (CGImage rows: y=0 is the top row.)
    ctx.draw(strip(CGRect(x: 0, y: 0, width: iw, height: 1)),
             in: CGRect(x: dx, y: dy + dh, width: dw, height: dy))
    ctx.draw(strip(CGRect(x: 0, y: ih - 1, width: iw, height: 1)),
             in: CGRect(x: dx, y: 0, width: dw, height: dy))
}
ctx.draw(img, in: CGRect(x: dx, y: dy, width: dw, height: dh))

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dstPath) as CFURL,
                                                 "public.png" as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(dstPath)")
