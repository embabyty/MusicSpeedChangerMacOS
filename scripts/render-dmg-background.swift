// Renders the DMG background with pure CoreGraphics (no AppKit focus tricks):
// dark backdrop, centered arrow, "Drag to install" caption. Output 1320x880.
import CoreGraphics
import CoreText
import ImageIO
import Foundation

let W = 1320, H = 880
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }

// Work in 660x440 design points, top-left origin.
ctx.scaleBy(x: 2, y: 2)
ctx.translateBy(x: 0, y: 440)
ctx.scaleBy(x: 1, y: -1)

// backdrop (matches the app's dark theme)
ctx.setFillColor(red: 0.086, green: 0.086, blue: 0.11, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: 660, height: 440))

// arrow pointing right, centered between the two icons
ctx.setFillColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)
ctx.fill(CGRect(x: 250, y: 186, width: 130, height: 28))
ctx.beginPath()
ctx.move(to: CGPoint(x: 375, y: 158))
ctx.addLine(to: CGPoint(x: 375, y: 242))
ctx.addLine(to: CGPoint(x: 445, y: 200))
ctx.closePath()
ctx.fillPath()

// caption intentionally omitted: Finder icon labels already name both items,
// and text rendering is one more thing that can misalign across displays.

guard let image = ctx.makeImage() else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dmg_background.png"
guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                                "public.png" as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(out)")
