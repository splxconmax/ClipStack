import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift <output-png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("unable to create graphics context\n", stderr)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high
context.translateBy(x: 0, y: canvasSize.height)
context.scaleBy(x: 1, y: -1)

let backgroundRect = NSRect(origin: .zero, size: canvasSize)
NSColor(calibratedWhite: 0.972, alpha: 1).setFill()
NSBezierPath(roundedRect: backgroundRect, xRadius: 72, yRadius: 72).fill()

let frameGradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.84, green: 0.85, blue: 0.87, alpha: 1),
        NSColor(calibratedRed: 0.77, green: 0.79, blue: 0.82, alpha: 1),
    ]
)!
let clipGradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.85, green: 0.86, blue: 0.89, alpha: 1),
    ]
)!
let strokeColor = NSColor(calibratedRed: 0.61, green: 0.62, blue: 0.65, alpha: 1)
let listColor = NSColor(calibratedRed: 0.77, green: 0.78, blue: 0.80, alpha: 1)

context.saveGState()
let outerShadow = NSShadow()
outerShadow.shadowOffset = NSSize(width: 0, height: -2)
outerShadow.shadowBlurRadius = 7
outerShadow.shadowColor = NSColor(calibratedWhite: 0.45, alpha: 0.18)
outerShadow.set()

let archRect = NSRect(x: 465, y: 223, width: 95, height: 95)
let archPath = NSBezierPath(ovalIn: archRect)
frameGradient.draw(in: archPath, angle: 90)
strokeColor.setStroke()
archPath.lineWidth = 8
archPath.stroke()

let bodyRect = NSRect(x: 285, y: 299, width: 434, height: 455)
let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 28, yRadius: 28)
frameGradient.draw(in: bodyPath, angle: 90)
strokeColor.setStroke()
bodyPath.lineWidth = 8
bodyPath.stroke()
context.restoreGState()

let clipRect = NSRect(x: 392, y: 299, width: 240, height: 70)
let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 18, yRadius: 18)
clipGradient.draw(in: clipPath, angle: 90)
strokeColor.setStroke()
clipPath.lineWidth = 8
clipPath.stroke()

let buttonGradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.80, green: 0.81, blue: 0.83, alpha: 1),
        NSColor(calibratedRed: 0.62, green: 0.64, blue: 0.67, alpha: 1),
    ]
)!
let buttonRect = NSRect(x: 494, y: 261, width: 36, height: 36)
let buttonPath = NSBezierPath(ovalIn: buttonRect)
buttonGradient.draw(in: buttonPath, relativeCenterPosition: .zero)
strokeColor.setStroke()
buttonPath.lineWidth = 4
buttonPath.stroke()

context.saveGState()
let paperShadow = NSShadow()
paperShadow.shadowOffset = NSSize(width: 0, height: -10)
paperShadow.shadowBlurRadius = 16
paperShadow.shadowColor = NSColor(calibratedRed: 0.56, green: 0.58, blue: 0.62, alpha: 0.24)
paperShadow.set()

NSColor.white.setFill()
let paperRect = NSRect(x: 336, y: 332, width: 348, height: 392)
let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: 34, yRadius: 34)
paperPath.fill()
context.restoreGState()

listColor.setFill()
for y in [411.0, 456.0, 501.0] {
    NSBezierPath(ovalIn: NSRect(x: 382, y: y - 13, width: 26, height: 26)).fill()
}

for rect in [
    NSRect(x: 429, y: 398, width: 145, height: 26),
    NSRect(x: 429, y: 443, width: 110, height: 26),
    NSRect(x: 429, y: 488, width: 100, height: 26),
] {
    NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
}

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("unable to encode png\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("failed to write icon png: \(error)\n", stderr)
    exit(1)
}
