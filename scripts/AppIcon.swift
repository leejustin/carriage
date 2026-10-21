// Draws Carriage's app icon (and its dark and tinted variants) in code.
//   swift scripts/AppIcon.swift <concept> <out-folder>     (from the repo root)
// Concepts: machine, key, sheet.
import AppKit
import CoreText

let args = CommandLine.arguments
let concept = args.count > 1 ? args[1] : "machine"
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Carriage/Fonts/CourierPrime-Regular.ttf") as CFURL, .process, nil)

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Variant { case light, dark, tinted }

struct Palette {
    var deskTop, deskBottom, enamel, enamelDark, paper, ink, legend, red: CGColor
    static func of(_ v: Variant) -> Palette {
        switch v {
        case .light: Palette(deskTop: c(0xB9D6C9), deskBottom: c(0x7FA898), enamel: c(0x9EC4B4), enamelDark: c(0x5E8676),
                             paper: c(0xFBF8F0), ink: c(0x24211E), legend: c(0xF1E7CF), red: c(0xA22D27))
        case .dark: Palette(deskTop: c(0x2A2826), deskBottom: c(0x121110), enamel: c(0x3C4A44), enamelDark: c(0x1D2420),
                            paper: c(0xEDE5D2), ink: c(0x24211E), legend: c(0xF1E7CF), red: c(0xC0443C))
        case .tinted: Palette(deskTop: c(0x000000, 0), deskBottom: c(0x000000, 0), enamel: c(0x8A8A8A), enamelDark: c(0x4A4A4A),
                              paper: c(0xFFFFFF), ink: c(0x3A3A3A), legend: c(0xFFFFFF), red: c(0xFFFFFF))
        }
    }
}

let size: CGFloat = 1024

func linear(_ cg: CGContext, _ colors: [CGColor], _ locations: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    cg.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ cg: CGContext, _ colors: [CGColor], _ locations: [CGFloat], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
}

/// Draws text with its baseline at `point` (CoreGraphics coordinates, y up).
func text(_ cg: CGContext, _ string: String, font: String, size: CGFloat, color: CGColor, at point: CGPoint, kern: CGFloat = 0, centered: Bool = false) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attr = NSAttributedString(string: string, attributes: [.font: f, .foregroundColor: color, .kern: kern])
    let line = CTLineCreateWithAttributedString(attr)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    cg.textPosition = CGPoint(x: centered ? point.x - CGFloat(width) / 2 : point.x, y: point.y)
    CTLineDraw(line, cg)
}

/// A typewriter key: chrome ring, black glass cap, a soft highlight, a cream legend.
func key(_ cg: CGContext, center p: CGPoint, radius r: CGFloat, legend: String, palette: Palette, tinted: Bool) {
    // Shadow on the desk.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -r * 0.12), blur: r * 0.35, color: c(0x000000, 0.45))
    cg.setFillColor(c(0x111111))
    cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    cg.restoreGState()
    // Chrome ring.
    cg.saveGState()
    cg.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    cg.clip()
    linear(cg, tinted ? [c(0xFFFFFF), c(0x8A8A8A), c(0xDDDDDD), c(0x5A5A5A)] : [c(0xF7F8F8), c(0x8E9496), c(0xDDE0E1), c(0x4E5356)],
           [0, 0.42, 0.62, 1], from: CGPoint(x: p.x, y: p.y + r), to: CGPoint(x: p.x, y: p.y - r))
    cg.restoreGState()
    // Glass cap.
    let ri = r * 0.8
    cg.saveGState()
    cg.addEllipse(in: CGRect(x: p.x - ri, y: p.y - ri, width: 2 * ri, height: 2 * ri))
    cg.clip()
    radial(cg, tinted ? [c(0x5A5A5A), c(0x1A1A1A)] : [c(0x3A3836), c(0x0B0A0A)], [0, 1], center: CGPoint(x: p.x, y: p.y + ri * 0.35), radius: ri * 1.3)
    // The highlight across the top of the cap.
    cg.setFillColor(c(0xFFFFFF, 0.13))
    cg.fillEllipse(in: CGRect(x: p.x - ri * 0.72, y: p.y + ri * 0.2, width: ri * 1.44, height: ri * 0.72))
    cg.restoreGState()
    text(cg, legend, font: "Futura-Medium", size: ri * 1.15, color: palette.legend, at: CGPoint(x: p.x, y: p.y - ri * 0.4), centered: true)
}

/// The platen: a black rubber roller between two ridged knobs.
func platen(_ cg: CGContext, rect: CGRect, tinted: Bool) {
    let knob = rect.height * 0.62
    let roller = CGRect(x: rect.minX + knob, y: rect.minY, width: rect.width - 2 * knob, height: rect.height)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: c(0x000000, 0.4))
    cg.addPath(CGPath(roundedRect: roller, cornerWidth: 10, cornerHeight: 10, transform: nil))
    cg.setFillColor(c(0x000000)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: roller, cornerWidth: 10, cornerHeight: 10, transform: nil))
    cg.clip()
    linear(cg, [c(0x050505), c(0x34312F), c(0x1A1918), c(0x000000)], [0, 0.3, 0.55, 1], from: CGPoint(x: 0, y: roller.maxY), to: CGPoint(x: 0, y: roller.minY))
    cg.setFillColor(c(0xFFFFFF, 0.12))
    cg.fill(CGRect(x: roller.minX, y: roller.maxY - roller.height * 0.28, width: roller.width, height: 4))
    cg.restoreGState()
    for left in [true, false] {
        let k = CGRect(x: left ? rect.minX : rect.maxX - knob, y: rect.minY - 10, width: knob, height: rect.height + 20)
        cg.saveGState()
        cg.addPath(CGPath(roundedRect: k, cornerWidth: knob * 0.3, cornerHeight: knob * 0.3, transform: nil))
        cg.clip()
        linear(cg, [c(0x3E3B39), c(0x0D0C0C), c(0x2A2826)], [0, 0.6, 1], from: CGPoint(x: k.minX, y: 0), to: CGPoint(x: k.maxX, y: 0))
        cg.setStrokeColor(c(0xFFFFFF, 0.08)); cg.setLineWidth(3)
        var y = k.minY + 8
        while y < k.maxY - 6 { cg.move(to: CGPoint(x: k.minX + 6, y: y)); cg.addLine(to: CGPoint(x: k.maxX - 6, y: y)); y += 9 }
        cg.strokePath()
        cg.restoreGState()
    }
    _ = tinted
}

func desk(_ cg: CGContext, _ pal: Palette, _ v: Variant) {
    guard v != .tinted else { return }
    linear(cg, [pal.deskTop, pal.deskBottom], [0, 1], from: CGPoint(x: 0, y: size), to: .zero)
    // A soft pool of light from above.
    radial(cg, [c(0xFFFFFF, v == .dark ? 0.06 : 0.18), c(0xFFFFFF, 0)], [0, 1], center: CGPoint(x: size / 2, y: size * 0.78), radius: size * 0.7)
}

/// A sheet with typed lines, a struck-out word and a red underline.
func sheet(_ cg: CGContext, rect: CGRect, pal: Palette, lines: [String], fontSize: CGFloat, struck: Int? = nil) {
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: c(0x000000, 0.28))
    cg.setFillColor(pal.paper); cg.fill(rect)
    cg.restoreGState()
    var y = rect.maxY - fontSize * 1.9
    for (i, line) in lines.enumerated() {
        text(cg, line, font: "CourierPrime-Regular", size: fontSize, color: pal.ink, at: CGPoint(x: rect.minX + fontSize * 1.2, y: y))
        if i == struck {
            text(cg, String(repeating: "x", count: 3), font: "CourierPrime-Regular", size: fontSize, color: pal.ink,
                 at: CGPoint(x: rect.minX + fontSize * 1.2 + CGFloat(line.count - 3) * fontSize * 0.6, y: y))
        }
        y -= fontSize * 1.55
    }
}

func render(_ v: Variant) -> CGImage {
    let pal = Palette.of(v)
    let cg = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    desk(cg, pal, v)
    switch concept {
    case "key":
        // One big key on the machine's enamel.
        key(cg, center: CGPoint(x: size / 2, y: size / 2 - 6), radius: size * 0.31, legend: "C", palette: pal, tinted: v == .tinted)
    case "sheet":
        // A sheet rising out of the platen, one word typed and underlined in red.
        let paper = CGRect(x: size * 0.2, y: size * 0.36, width: size * 0.6, height: size * 0.52)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: c(0x000000, 0.28))
        cg.setFillColor(pal.paper); cg.fill(paper)
        cg.restoreGState()
        text(cg, "Dear,", font: "CourierPrime-Regular", size: 120, color: pal.ink, at: CGPoint(x: paper.minX + 70, y: paper.maxY - 210))
        cg.setFillColor(pal.red)
        cg.fill(CGRect(x: paper.minX + 70, y: paper.maxY - 236, width: 290, height: 12))
        platen(cg, rect: CGRect(x: size * 0.1, y: size * 0.26, width: size * 0.8, height: size * 0.13), tinted: v == .tinted)
    default:
        // The machine itself: a page in the platen and a row of keys below.
        let paper = CGRect(x: size * 0.24, y: size * 0.5, width: size * 0.52, height: size * 0.36)
        sheet(cg, rect: paper, pal: pal, lines: ["Carriage", "the river", "forgot"], fontSize: 58)
        cg.setFillColor(pal.red)
        cg.fill(CGRect(x: paper.minX + 70, y: paper.maxY - 124, width: 280, height: 7))
        platen(cg, rect: CGRect(x: size * 0.12, y: size * 0.42, width: size * 0.76, height: size * 0.105), tinted: v == .tinted)
        // The deck: the machine's enamel body under the platen.
        let deck = CGRect(x: size * 0.08, y: size * 0.1, width: size * 0.84, height: size * 0.3)
        if v != .tinted {
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: deck, cornerWidth: 40, cornerHeight: 40, transform: nil))
            cg.clip()
            linear(cg, [pal.enamel, pal.enamelDark], [0, 1], from: CGPoint(x: 0, y: deck.maxY), to: CGPoint(x: 0, y: deck.minY))
            cg.restoreGState()
        }
        let r = size * 0.078
        for (i, letter) in ["Q", "W", "E"].enumerated() {
            key(cg, center: CGPoint(x: size * 0.28 + CGFloat(i) * size * 0.22, y: size * 0.245), radius: r, legend: letter, palette: pal, tinted: v == .tinted)
        }
    }
    return cg.makeImage()!
}

for (v, name) in [(Variant.light, "AppIcon.png"), (.dark, "AppIcon-Dark.png"), (.tinted, "AppIcon-Tinted.png")] {
    let rep = NSBitmapImageRep(cgImage: render(v))
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}
print("wrote \(concept) icons to \(out.path)")
