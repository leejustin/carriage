// Frames the raw simulator screenshots for the App Store: a typed caption over a paper or night desk.
//
//   swift scripts/StoreScreenshots.swift   (from the repo root)
//
// Reads docs/screenshots/iPhone-18-Pro-Max and writes store-6.9 and store-6.3; reads docs/screenshots/iPhone-Duo
// (captured with -laptopPreview and turned upright) and writes store-duo.
import AppKit
import CoreText

struct Shot {
    var folder = "iPhone-18-Pro-Max"
    var source: String
    var title: String
    var line: String
    var night = false
}

let shots = [
    Shot(source: "01-typing", title: "A quiet place\nto write.", line: "YOUR PHONE GOES QUIET. THE WORDS COME OUT."),
    Shot(source: "02-focus", title: "Just you\nand the page.", line: "TAP THE MOON AND EVERYTHING ELSE FADES AWAY."),
    Shot(source: "05-cherry", title: "A beautiful\nlittle machine.", line: "CHROME KEYS, SOFT CLACKS, A BELL AT THE MARGIN."),
    Shot(source: "04-night", title: "Write late,\nin peace.", line: "NIGHT DESK: LIGHT INK ON DARK PAPER.", night: true),
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

    // The screen, a little smaller than life, running off the bottom edge.
    // The Duo's screen is wider for its height; keep the keys on the canvas.
    let width = size.width * (duo ? 0.70 : 0.84)
    let height = width * screen.size.height / screen.size.width
    let frame = CGRect(x: (size.width - width) / 2, y: size.height - 580 * scale - height, width: width, height: height)
    let corner = 64 * scale
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(shot.night ? 0.55 : 0.28)
    shadow.shadowBlurRadius = 60 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    shadow.set()
    color(0x111111).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: -14 * scale, dy: -14 * scale), xRadius: corner + 14 * scale, yRadius: corner + 14 * scale).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
    screen.draw(in: frame)
    if duo {
        // The quarter-turned capture shows the home indicator as a sliver down the right edge, between the
        // keys and the screen's edge; cover it with the plain desk just beside it.
        let px = screen.size.width / frame.width
        let source = CGRect(x: screen.size.width - 22, y: screen.size.height * 0.25, width: 12, height: screen.size.height * 0.5)
        let target = CGRect(x: frame.maxX - 52 / px, y: frame.minY + frame.height * 0.25, width: 44 / px, height: frame.height * 0.5)
        screen.draw(in: target, from: source, operation: .copy, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for (folder, size, set) in [("store-6.9", CGSize(width: 1320, height: 2868), shots), ("store-6.3", CGSize(width: 1206, height: 2622), shots), ("store-duo", CGSize(width: 2007, height: 2853), duoShots)] {
    let out = root.appendingPathComponent("docs/screenshots/\(folder)")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (n, shot) in set.enumerated() {
        try render(shot, size: size, to: out.appendingPathComponent(String(format: "%02d-%@.png", n + 1, String(shot.source.dropFirst(3)))))
    }
    print("wrote \(folder)")
}
