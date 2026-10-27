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
func drawLaptop(_ screen: NSImage, in area: CGRect, night: Bool, glass report: ((_ top: [CGPoint], _ bottom: [CGPoint]) -> Void)? = nil) -> CGRect {
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

    // Where each screen's glass lands, corners in reading order (top left, top right, bottom left, bottom right),
    // for laying video over it.
    if let report {
        let across = pageHinge[1] - pageHinge[0]
        func onPage(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            place(pageHinge[0] + across * Double(u / halfSize.width) + (pageTop[0] - pageHinge[0]) * Double(v / halfSize.height))
        }
        func onKeys(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            place(keysNear[0] + across * Double(u / halfSize.width) + (pageHinge[0] - keysNear[0]) * Double(v / halfSize.height))
        }
        report([onPage(bezel, hinge + fold), onPage(bezel + w, hinge + fold), onPage(bezel, hinge), onPage(bezel + w, hinge)],
               [onKeys(bezel, bezel + fold), onKeys(bezel + w, bezel + fold), onKeys(bezel, bezel), onKeys(bezel + w, bezel)])
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

// MARK: Creative assets

// The product page header (21:9) and the search results card (3:2), saved as PNG without an alpha channel.
func creative(size: CGSize, to url: URL, draw: (CGRect) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    // Copied into a bitmap with no alpha channel at all, as App Store Connect requires.
    let context = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
    try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
}

/// The paper desk, lit warm from the upper left like the desk lamp.
func desk(_ bounds: CGRect) {
    NSGradient(starting: color(0xF6F1E6), ending: color(0xE3D8C2))!.draw(in: bounds, angle: -90)
    let glow = NSGradient(colors: [color(0xFFF4D8, 0.85), color(0xFFF4D8, 0)])!
    let r = bounds.height * 1.1
    glow.draw(fromCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: 0, toCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: r, options: [])
}

let duoTyping = NSImage(contentsOf: root.appendingPathComponent("docs/screenshots/iPhone-Duo/01-typing.png"))!
let creativeOut = root.appendingPathComponent("docs/screenshots/creative")
try FileManager.default.createDirectory(at: creativeOut, withIntermediateDirectories: true)

// Header: one clear idea, the Duo half-folded on the desk, in the middle where every crop keeps it.
try creative(size: CGSize(width: 3840, height: 1646), to: creativeOut.appendingPathComponent("header.png")) { bounds in
    desk(bounds)
    // Kept below the top fifth, where the status bar and back button sit over it on iPhone.
    drawLaptop(duoTyping, in: CGRect(x: bounds.midX - 800, y: 70, width: 1600, height: 1180), night: false)
}

// Search results: say what it is at a glance, and show it.
try creative(size: CGSize(width: 3840, height: 2560), to: creativeOut.appendingPathComponent("search.png")) { bounds in
    desk(bounds)
    let ink = color(0x24211E)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineHeightMultiple = 1.0
    NSAttributedString(string: "A typewriter\nfor your\niPhone.", attributes: [
        .font: NSFont(name: "CourierPrime-Regular", size: 205)!, .foregroundColor: ink, .paragraphStyle: paragraph,
        .strokeWidth: -1.2, .strokeColor: ink,
    ]).draw(with: CGRect(x: 230, y: bounds.midY - 330, width: 1640, height: 900), options: [.usesLineFragmentOrigin])
    color(0xA22D27).setFill()
    NSBezierPath(roundedRect: CGRect(x: 240, y: bounds.midY - 420, width: 150, height: 14), xRadius: 7, yRadius: 7).fill()
    NSAttributedString(string: "REAL CLACKS. NO DISTRACTIONS.", attributes: [
        .font: NSFont(name: "Futura-Medium", size: 70)!, .foregroundColor: ink.withAlphaComponent(0.7), .kern: 9,
    ]).draw(at: CGPoint(x: 236, y: bounds.midY - 580))
    drawLaptop(duoTyping, in: CGRect(x: 1850, y: 160, width: 1880, height: bounds.height - 320), night: false)
}
print("wrote creative")

// MARK: Product Hunt gallery

// Product Hunt's gallery is 1270 x 760; drawn at twice that. A typed headline over the desk, and the machine.
let launchOut = root.appendingPathComponent("docs/launch/product-hunt")
try FileManager.default.createDirectory(at: launchOut, withIntermediateDirectories: true)
let launchSize = CGSize(width: 2540, height: 1520)

func duoCapture(_ name: String) -> NSImage { NSImage(contentsOf: root.appendingPathComponent("docs/screenshots/iPhone-Duo/\(name).png"))! }
func phoneCapture(_ name: String) -> NSImage { NSImage(contentsOf: root.appendingPathComponent("docs/screenshots/iPhone-18-Pro-Max/\(name).png"))! }

/// A single-screen iPhone, upright in `rect` (fitted by height), with its bezel and shadow.
func drawPhone(_ screen: NSImage, fitting rect: CGRect, night: Bool) {
    let height = rect.height, width = height * screen.size.width / screen.size.height
    let frame = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
    let corner = width * 0.13, bezel = width * 0.025
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(night ? 0.6 : 0.3)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    color(0x111111).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -bezel, dy: -bezel), xRadius: corner + bezel, yRadius: corner + bezel).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
    screen.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
}

/// A headline and a small line under it, centred near the top, set like the store screenshots.
func headline(_ title: String, _ line: String, in bounds: CGRect, night: Bool, top: CGFloat = 120, size: CGFloat = 132) {
    let ink = night ? color(0xEDE6D8) : color(0x24211E)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSAttributedString(string: title, attributes: [
        .font: NSFont(name: "CourierPrime-Regular", size: size)!, .foregroundColor: ink, .paragraphStyle: paragraph,
        .strokeWidth: -1.2, .strokeColor: ink,
    ]).draw(with: CGRect(x: 80, y: bounds.maxY - top - size * 1.3, width: bounds.width - 160, height: size * 1.4), options: [.usesLineFragmentOrigin])
    color(0xA22D27).setFill()
    NSBezierPath(roundedRect: CGRect(x: bounds.midX - 50, y: bounds.maxY - top - size * 1.62, width: 100, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
    NSAttributedString(string: line, attributes: [
        .font: NSFont(name: "Futura-Medium", size: 40)!, .foregroundColor: ink.withAlphaComponent(0.7), .kern: 6, .paragraphStyle: paragraph,
    ]).draw(with: CGRect(x: 80, y: bounds.maxY - top - size * 1.62 - 90, width: bounds.width - 160, height: 60), options: [.usesLineFragmentOrigin])
}

func nightDesk(_ bounds: CGRect) {
    NSGradient(starting: color(0x23211F), ending: color(0x141312))!.draw(in: bounds, angle: -90)
    NSGradient(colors: [color(0xFFC878, 0.16), color(0xFFC878, 0)])!
        .draw(fromCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: 0, toCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: bounds.height * 1.1, options: [])
}

// 1. What it is.
try creative(size: launchSize, to: launchOut.appendingPathComponent("1-typewriter.png")) { bounds in
    desk(bounds)
    let ink = color(0x24211E)
    let paragraph = NSMutableParagraphStyle()
    NSAttributedString(string: "A typewriter\nfor your\niPhone Duo.", attributes: [
        .font: NSFont(name: "CourierPrime-Regular", size: 150)!, .foregroundColor: ink, .paragraphStyle: paragraph,
        .strokeWidth: -1.2, .strokeColor: ink,
    ]).draw(with: CGRect(x: 150, y: bounds.midY - 200, width: 1150, height: 600), options: [.usesLineFragmentOrigin])
    color(0xA22D27).setFill()
    NSBezierPath(roundedRect: CGRect(x: 158, y: bounds.midY - 280, width: 110, height: 10), xRadius: 5, yRadius: 5).fill()
    NSAttributedString(string: "REAL CLACKS. NO DISTRACTIONS.", attributes: [
        .font: NSFont(name: "Futura-Medium", size: 46)!, .foregroundColor: ink.withAlphaComponent(0.7), .kern: 6,
    ]).draw(at: CGPoint(x: 154, y: bounds.midY - 390))
    drawLaptop(duoCapture("01-typing"), in: CGRect(x: 1240, y: 110, width: 1220, height: bounds.height - 220), night: false)
}

// 2. The fold.
try creative(size: launchSize, to: launchOut.appendingPathComponent("2-half-fold.png")) { bounds in
    desk(bounds)
    headline("Half-fold it like a laptop.", "THE PAGE STANDS UP. A FULL TYPEWRITER WAITS BELOW.", in: bounds, night: false)
    drawLaptop(duoCapture("03-cherry"), in: CGRect(x: 200, y: 70, width: bounds.width - 400, height: bounds.height - 520), night: false)
}

// 3. Intent.
try creative(size: launchSize, to: launchOut.appendingPathComponent("3-intent.png")) { bounds in
    desk(bounds)
    headline("Every word, on purpose.", "ONE PAGE. NO FEED. TYPOS STAY, STRUCK THROUGH.", in: bounds, night: false)
    drawLaptop(duoCapture("02-focus"), in: CGRect(x: 200, y: 70, width: bounds.width - 400, height: bounds.height - 520), night: false)
}

// 4. The machines.
try creative(size: launchSize, to: launchOut.appendingPathComponent("4-real-typewriters.png")) { bounds in
    desk(bounds)
    headline("Real typewriters, recorded.", "EVERY KEY, THE BELL AT THE MARGIN, THE CARRIAGE SLIDING HOME.", in: bounds, night: false)
    let w = (bounds.width - 300) / 3
    for (i, name) in ["01-typing", "03-cherry", "04-night"].enumerated() {
        drawLaptop(duoCapture(name), in: CGRect(x: 110 + CGFloat(i) * (w + 40), y: 150, width: w, height: bounds.height - 650), night: false)
    }
}

// 5. Night.
try creative(size: launchSize, to: launchOut.appendingPathComponent("5-write-late.png")) { bounds in
    nightDesk(bounds)
    headline("Write late, in peace.", "YOUR PHONE GOES QUIET. JUST THE PAGE AND THE KEYS.", in: bounds, night: true)
    drawLaptop(duoCapture("04-night"), in: CGRect(x: 200, y: 70, width: bounds.width - 400, height: bounds.height - 520), night: true)
}

// Thumbnail: the app icon at Product Hunt's 240 x 240.
try creative(size: CGSize(width: 240, height: 240), to: launchOut.appendingPathComponent("thumbnail.png")) { bounds in
    NSImage(contentsOf: root.appendingPathComponent("Carriage/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))!.draw(in: bounds)
}
print("wrote product hunt gallery")

// MARK: Website

// The landing page's art: the machine on a clear background, so it sits on the page's own paper, plus the card
// shown when the link is shared. Converted to WebP for the web by scripts/web/build.sh.
let webOut = root.appendingPathComponent("docs/web-art")
try FileManager.default.createDirectory(at: webOut, withIntermediateDirectories: true)

func clear(size: CGSize, to url: URL, draw: (CGRect) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for (name, capture, night) in [("laptop-seafoam", "01-typing", false), ("laptop-cherry", "03-cherry", false), ("laptop-night", "04-night", true)] {
    try clear(size: CGSize(width: 2000, height: 1640), to: webOut.appendingPathComponent("\(name).png")) { bounds in
        drawLaptop(duoCapture(capture), in: bounds.insetBy(dx: 60, dy: 90), night: night)
    }
}
try clear(size: CGSize(width: 1700, height: 3212), to: webOut.appendingPathComponent("phone.png")) { bounds in
    drawPhone(phoneCapture("01-typing"), fitting: bounds.insetBy(dx: 230, dy: 170), night: false)
}
try creative(size: CGSize(width: 2400, height: 1260), to: webOut.appendingPathComponent("og.png")) { bounds in
    desk(bounds)
    let ink = color(0x24211E)
    NSAttributedString(string: "A typewriter\nfor your\niPhone.", attributes: [
        .font: NSFont(name: "CourierPrime-Regular", size: 140)!, .foregroundColor: ink, .strokeWidth: -1.2, .strokeColor: ink,
    ]).draw(with: CGRect(x: 140, y: bounds.midY - 180, width: 1100, height: 560), options: [.usesLineFragmentOrigin])
    color(0xA22D27).setFill()
    NSBezierPath(roundedRect: CGRect(x: 148, y: bounds.midY - 250, width: 100, height: 10), xRadius: 5, yRadius: 5).fill()
    NSAttributedString(string: "CARRIAGE", attributes: [
        .font: NSFont(name: "Futura-Medium", size: 44)!, .foregroundColor: ink.withAlphaComponent(0.7), .kern: 12,
    ]).draw(at: CGPoint(x: 144, y: bounds.midY - 350))
    drawLaptop(duoCapture("01-typing"), in: CGRect(x: 1150, y: 90, width: 1180, height: bounds.height - 180), night: false)
}
print("wrote web art")

// MARK: Duo video

// The pieces for laying a Duo screen recording over the half-folded Duo (scripts/preview/duo.sh): the desk and the
// machine, a mask for each screen, and where each screen's corners land.
func solid(_ c: NSColor, _ size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    c.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}
func halves(top: NSColor, bottom: NSColor) -> NSImage {
    let size = CGSize(width: 2007, height: 2853)
    let image = NSImage(size: size)
    image.lockFocus()
    bottom.setFill()
    NSRect(x: 0, y: 0, width: size.width, height: size.height / 2).fill()
    top.setFill()
    NSRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2).fill()
    image.unlockFocus()
    return image
}
for (name, size, background) in [("web", CGSize(width: 1920, height: 1200), color(0xEBE2CF)), ("film", CGSize(width: 1920, height: 1080), color(0xF3ECDD))] {
    let out = root.appendingPathComponent("docs/web-art/duo-video/\(name)")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let area = CGRect(x: 100, y: 50, width: size.width - 200, height: size.height - 100)
    var corners: [String: [[Double]]] = [:]
    try creative(size: size, to: out.appendingPathComponent("background.png")) { bounds in
        background.setFill()
        bounds.fill()
        drawLaptop(halves(top: .black, bottom: .black), in: area, night: false) { top, bottom in
            // Video frames count down from the top.
            corners["top"] = top.map { [Double($0.x), Double(size.height - $0.y)] }
            corners["bottom"] = bottom.map { [Double($0.x), Double(size.height - $0.y)] }
        }
    }
    for (mask, image) in [("mask-top", halves(top: .white, bottom: .black)), ("mask-bottom", halves(top: .black, bottom: .white))] {
        try creative(size: size, to: out.appendingPathComponent("\(mask).png")) { bounds in
            NSColor.black.setFill()
            bounds.fill()
            drawLaptop(image, in: area, night: true)
        }
    }
    try JSONSerialization.data(withJSONObject: corners, options: [.prettyPrinted]).write(to: out.appendingPathComponent("corners.json"))
}
print("wrote duo video pieces")
