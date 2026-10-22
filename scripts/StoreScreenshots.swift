// Frames the raw simulator screenshots for the App Store: a typed caption over a paper or night desk.
//
//   swift scripts/StoreScreenshots.swift   (from the repo root)
//
// Reads docs/screenshots/iPhone-18-Pro-Max and writes store-6.9 and store-6.3; reads docs/screenshots/iPhone-Duo
// (captured with -laptopPreview and turned upright) and writes store-duo, with the Duo drawn half-folded on the
// desk like a little laptop, the way it's held to type.
import AppKit
import CoreImage
import CoreText
import simd

struct Shot {
    var folder = "iPhone-18-Pro-Max"
    var source: String
    var title: String
    var line: String
    var night = false
}

// Every iPhone sees the Duo first, half-folded the way Carriage is meant to be used, then the single screen.
let shots = [
    Shot(folder: "iPhone-Duo", source: "01-typing", title: "Half-fold it.\nStart typing.", line: "THE PAGE ON TOP, A FULL TYPEWRITER BELOW."),
    Shot(folder: "iPhone-Duo", source: "03-cherry", title: "A beautiful\nlittle machine.", line: "CHROME KEYS, SOFT CLACKS, A BELL AT THE MARGIN."),
    Shot(source: "01-typing", title: "On any iPhone,\ntoo.", line: "THE PAGE AND THE KEYS ON ONE SCREEN."),
    Shot(source: "02-focus", title: "Just you\nand the page.", line: "TAP THE MOON AND EVERYTHING ELSE FADES AWAY."),
    Shot(folder: "iPhone-Duo", source: "04-night", title: "Write late,\nin peace.", line: "NIGHT DESK: LIGHT INK ON DARK PAPER.", night: true),
    Shot(source: "03-library", title: "Every page,\nkept safe.", line: "NOTEBOOKS, STREAKS, ICLOUD AND FILES."),
]

let duoShots = [
    Shot(folder: "iPhone-Duo", source: "01-typing", title: "Half-fold it.\nStart typing.", line: "THE PAGE ON TOP, A FULL TYPEWRITER BELOW."),
    Shot(folder: "iPhone-Duo", source: "02-focus", title: "Just you\nand the page.", line: "TAP THE MOON AND EVERYTHING ELSE FADES AWAY."),
    Shot(folder: "iPhone-Duo", source: "03-cherry", title: "A beautiful\nlittle machine.", line: "CHROME KEYS, SOFT CLACKS, A BELL AT THE MARGIN."),
    Shot(folder: "iPhone-Duo", source: "04-night", title: "Write late,\nin peace.", line: "NIGHT DESK: LIGHT INK ON DARK PAPER.", night: true),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Carriage/Fonts/CourierPrime-Regular.ttf") as CFURL, .process, nil)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ shot: Shot, size: CGSize, to url: URL) throws {
    let input = root.appendingPathComponent("docs/screenshots/\(shot.folder)")
    guard let screen = NSImage(contentsOf: input.appendingPathComponent(shot.source + ".png")) else {
        throw NSError(domain: "StoreScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(shot.source)"])
    }
    let duo = shot.folder == "iPhone-Duo"
    let scale = size.width / 1320
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = CGRect(origin: .zero, size: size)

    // The desk: warm paper by day, the night desk after dark.
    let top = shot.night ? color(0x23211F) : color(0xF6F1E6)
    let bottom = shot.night ? color(0x141312) : color(0xE6DCC8)
    NSGradient(starting: top, ending: bottom)!.draw(in: bounds, angle: -90)

    // Caption, set like a typed heading with a red rule under it.
    let ink = shot.night ? color(0xEDE6D8) : color(0x24211E)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.02
    let title = NSAttributedString(string: shot.title, attributes: [
        .font: NSFont(name: "CourierPrime-Regular", size: 104 * scale)!,
        .foregroundColor: ink,
        .paragraphStyle: paragraph,
        .strokeWidth: -1.2,
        .strokeColor: ink,
    ])
    let titleRect = CGRect(x: 60 * scale, y: size.height - 400 * scale, width: size.width - 120 * scale, height: 290 * scale)
    title.draw(with: titleRect, options: [.usesLineFragmentOrigin])

    color(0xA22D27).setFill()
    NSBezierPath(roundedRect: CGRect(x: size.width / 2 - 34 * scale, y: size.height - 440 * scale, width: 68 * scale, height: 6 * scale), xRadius: 3 * scale, yRadius: 3 * scale).fill()

    let line = NSAttributedString(string: shot.line, attributes: [
        .font: NSFont(name: "Futura-Medium", size: 30 * scale)!,
        .foregroundColor: ink.withAlphaComponent(0.7),
        .kern: 4 * scale,
        .paragraphStyle: paragraph,
    ])
    line.draw(with: CGRect(x: 60 * scale, y: size.height - 520 * scale, width: size.width - 120 * scale, height: 50 * scale), options: [.usesLineFragmentOrigin])

    if duo && size.width / size.height < 0.6 {
        // On a single-screen iPhone's canvas, the Duo sits in the middle with a note saying which phone it is.
        let device = drawLaptop(screen, in: CGRect(x: 24 * scale, y: 420 * scale, width: size.width - 48 * scale, height: size.height - 1100 * scale), night: shot.night)
        let note = NSAttributedString(string: "SHOWN ON IPHONE DUO", attributes: [
            .font: NSFont(name: "Futura-Medium", size: 26 * scale)!,
            .foregroundColor: ink.withAlphaComponent(0.45),
            .kern: 4 * scale,
            .paragraphStyle: paragraph,
        ])
        note.draw(with: CGRect(x: 60 * scale, y: device.minY - 150 * scale, width: size.width - 120 * scale, height: 44 * scale), options: [.usesLineFragmentOrigin])
    } else if duo {
        drawLaptop(screen, in: CGRect(x: 40 * scale, y: 70 * scale, width: size.width - 80 * scale, height: size.height - 640 * scale), night: shot.night)
    } else {
        drawPhone(screen, size: size, scale: scale, night: shot.night)
    }

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// The screen, a little smaller than life, running off the bottom edge.
func drawPhone(_ screen: NSImage, size: CGSize, scale: CGFloat, night: Bool) {
    let width = size.width * 0.84
    let height = width * screen.size.height / screen.size.width
    let frame = CGRect(x: (size.width - width) / 2, y: size.height - 580 * scale - height, width: width, height: height)
    let corner = 64 * scale
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(night ? 0.55 : 0.28)
    shadow.shadowBlurRadius = 60 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    shadow.set()
    color(0x111111).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -14 * scale, dy: -14 * scale), xRadius: corner + 14 * scale, yRadius: corner + 14 * scale).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
    screen.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: The Duo, half-folded

/// The Duo as it's really used: half-folded on the desk like a little laptop, the page standing up on the top half
/// and the keys lying flat on the bottom half, seen from in front and a little above. Fills `area` as wide as fits,
/// centred in it, and returns where it landed.
@discardableResult
func drawLaptop(_ screen: NSImage, in area: CGRect, night: Bool) -> CGRect {
    guard let cg = screen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .zero }
    let w = CGFloat(cg.width), fold = CGFloat(cg.height / 2)
    let bezel: CGFloat = 46, hinge: CGFloat = 8
    let halfSize = CGSize(width: w + 2 * bezel, height: fold + bezel + hinge)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Each half drawn flat in its bezel, rounded only at its outer corners.
    func half(top: Bool) -> CIImage {
        let ctx = CGContext(data: nil, width: Int(halfSize.width), height: Int(halfSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bounds = CGRect(origin: .zero, size: halfSize)
        // Rounded rects that run past the hinge edge, so only the outer corners show round.
        let outer = top ? CGRect(x: 0, y: -200, width: halfSize.width, height: halfSize.height + 200) : CGRect(x: 0, y: 0, width: halfSize.width, height: halfSize.height + 200)
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: 150, cornerHeight: 150, transform: nil))
        ctx.clip()
        ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.075, alpha: 1))
        ctx.fill(bounds)
        let glass = CGRect(x: bezel, y: top ? hinge : bezel, width: w, height: fold)
        let corners = top ? CGRect(x: glass.minX, y: glass.minY - 200, width: w, height: fold + 200) : CGRect(x: glass.minX, y: glass.minY, width: w, height: fold + 200)
        ctx.addPath(CGPath(roundedRect: corners, cornerWidth: 104, cornerHeight: 104, transform: nil))
        ctx.clip()
        let part = cg.cropping(to: CGRect(x: 0, y: top ? 0 : Int(fold), width: Int(w), height: Int(fold)))!
        ctx.draw(part, in: glass)
        return CIImage(cgImage: ctx.makeImage()!)
    }

    // The device in the world, in screen pixels: the hinge along x, the keys flat towards the camera (+z), the page
    // opened back to 108 degrees.
    let halfW = Double(halfSize.width) / 2, depth = Double(halfSize.height), thick = 80.0
    let open = 108.0 * .pi / 180
    let up = SIMD3(0, sin(.pi - open), -cos(.pi - open))
    let back = SIMD3(0, cos(.pi - open), sin(.pi - open)) * -1
    let eye = SIMD3(0.0, 3900, 6200), target = SIMD3(0.0, 420, 380)
    let forward = simd_normalize(target - eye)
    let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
    let camUp = simd_cross(right, forward)
    func project(_ p: SIMD3<Double>) -> CGPoint {
        let d = p - eye
        let z = simd_dot(d, forward)
        return CGPoint(x: simd_dot(d, right) / z, y: simd_dot(d, camUp) / z)
    }
    let pageHinge = [SIMD3(-halfW, 0, 0), SIMD3(halfW, 0, 0)]
    let pageTop = pageHinge.map { $0 + up * depth }
    let keysNear = pageHinge.map { $0 + SIMD3(0, 0, depth) }
    let keysUnder = keysNear.map { $0 + SIMD3(0, -thick, 0) }
    let pageBack = pageTop.map { $0 + back * thick }

    // Fit everything into the area: as wide as allowed, centred, resting on the bottom.
    let raw = (pageTop + pageBack + keysUnder + keysNear + pageHinge).map(project)
    let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!, minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
    let fit = min(area.width / (maxX - minX), area.height / (maxY - minY))
    let ox = area.midX - (minX + maxX) / 2 * fit, oy = area.midY - (minY + maxY) / 2 * fit
    func place(_ p: SIMD3<Double>) -> CGPoint {
        let q = project(p)
        return CGPoint(x: ox + q.x * fit, y: oy + q.y * fit)
    }
    func quad(_ points: [SIMD3<Double>]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: place(points[0]))
        for p in points.dropFirst() { path.line(to: place(p)) }
        path.close()
        return path
    }

    // Its shadow on the desk.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(night ? 0.7 : 0.38)
    shadow.shadowBlurRadius = 90
    // Cast from a shape drawn off the canvas, so only the soft shadow lands.
    let away: CGFloat = 20_000
    shadow.shadowOffset = NSSize(width: away, height: -36)
    shadow.set()
    let footprint = quad([keysUnder[0] + SIMD3(60, 0, -20), keysUnder[1] + SIMD3(-60, 0, -20), pageHinge[1] + SIMD3(-60, -thick, -40), pageHinge[0] + SIMD3(60, -thick, -40)])
    footprint.transform(using: AffineTransform(translationByX: -away, byY: 0))
    NSColor.black.setFill()
    footprint.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Each half's glass bent into place, over its own body stacked behind it, so the device's thickness follows
    // its rounded corners: the keys half shows its front edge, the page half its top edge.
    let ci = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
    let canvas = NSGraphicsContext.current!.cgContext
    func warp(_ image: CIImage, _ tl: SIMD3<Double>, _ tr: SIMD3<Double>, _ bl: SIMD3<Double>, _ br: SIMD3<Double>) {
        let out = CIFilter(name: "CIPerspectiveTransform", parameters: [
            kCIInputImageKey: image,
            "inputTopLeft": CIVector(cgPoint: place(tl)), "inputTopRight": CIVector(cgPoint: place(tr)),
            "inputBottomLeft": CIVector(cgPoint: place(bl)), "inputBottomRight": CIVector(cgPoint: place(br)),
        ])!.outputImage!
        let extent = out.extent.integral
        canvas.draw(ci.createCGImage(out, from: extent)!, in: extent)
    }
    func body(_ image: CIImage, shade: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: shade, green: shade * 0.98, blue: shade * 0.96)).cropped(to: image.extent)
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: image])
    }
    let keys = half(top: false), page = half(top: true)
    let steps = 12
    for i in stride(from: steps, through: 1, by: -1) {
        let down = SIMD3(0, -thick * Double(i) / Double(steps), 0)
        warp(body(keys, shade: 0.24 + 0.2 * CGFloat(steps - i) / CGFloat(steps)), pageHinge[0] + down, pageHinge[1] + down, keysNear[0] + down, keysNear[1] + down)
    }
    warp(keys, pageHinge[0], pageHinge[1], keysNear[0], keysNear[1])
    for i in stride(from: steps, through: 1, by: -1) {
        let away = back * thick * Double(i) / Double(steps)
        warp(body(page, shade: 0.4 + 0.25 * CGFloat(steps - i) / CGFloat(steps)), pageTop[0] + away, pageTop[1] + away, pageHinge[0] + away, pageHinge[1] + away)
    }
    warp(page, pageTop[0], pageTop[1], pageHinge[0], pageHinge[1])

    // A little light across the standing glass, and the hinge's shadow where the halves meet.
    NSGraphicsContext.saveGraphicsState()
    quad([pageTop[0], pageTop[1], pageHinge[1], pageHinge[0]]).addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.0), NSColor.white.withAlphaComponent(night ? 0.04 : 0.07), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: quad([pageTop[0], pageTop[1], pageHinge[1], pageHinge[0]]).bounds, angle: -60)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    quad([pageHinge[0], pageHinge[1], pageHinge[1] + SIMD3(0, 0, 70), pageHinge[0] + SIMD3(0, 0, 70)]).addClip()
    let band = quad([pageHinge[0], pageHinge[1], pageHinge[1] + SIMD3(0, 0, 70), pageHinge[0] + SIMD3(0, 0, 70)]).bounds
    NSGradient(starting: NSColor.black.withAlphaComponent(0.35), ending: NSColor.black.withAlphaComponent(0))!.draw(in: band, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    return CGRect(x: ox + minX * fit, y: oy + minY * fit, width: (maxX - minX) * fit, height: (maxY - minY) * fit)
}

for (folder, size, set) in [("store-6.9", CGSize(width: 1320, height: 2868), shots), ("store-6.3", CGSize(width: 1206, height: 2622), shots), ("store-duo", CGSize(width: 2007, height: 2853), duoShots)] {
    let out = root.appendingPathComponent("docs/screenshots/\(folder)")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (n, shot) in set.enumerated() {
        try render(shot, size: size, to: out.appendingPathComponent(String(format: "%02d-%@.png", n + 1, String(shot.source.dropFirst(3)))))
    }
    print("wrote \(folder)")
}
