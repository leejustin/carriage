// The launch film's title cards, the typed close-up and the soundtrack.
//
//   swift scripts/film/Film.swift <work folder> <timeline.txt> <duo audio.wav> [music file]
//   (scripts/film/make.sh runs it)
//
// The timeline is one segment per line, `kind | seconds | text`:
//   clip  | 5   | find               a shot from the clips folder, by name
//   card  | 1.2 | It made me slow down. | find    typed out letter by letter, then held; optionally over a
//                                                     shot from the clips folder, faded back behind the words
//   word  | 1.4 | Carriage           typed in close-up on the page, the carriage stepping with each key
//   duo   | 23.5 |                   the real Duo recording
//   shot  | 3.2 | 7.9 | raw | keys | Real recorded keys.
//         a stretch of the Duo recording (from seconds into duo-film.mp4), either the half-folded Duo (film) or
//         a crop of the raw screen (raw), with a caption over it
//   end   | 5   |                    the end card
//
// Every keystroke lands on a video frame, and its recorded sound starts on that same frame. Writes card and word
// frames into the work folder, <work>/soundtrack.wav, and prints the cut list make.sh follows.
import AppKit
import AVFoundation
import CoreImage
import CoreText

let args = CommandLine.arguments
let work = URL(fileURLWithPath: args[1])
let timelineFile = URL(fileURLWithPath: args[2])
let duoAudio = URL(fileURLWithPath: args[3])
let musicFile = args.count > 4 ? URL(fileURLWithPath: args[4]) : nil
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Carriage/Fonts/CourierPrime-Regular.ttf") as CFURL, .process, nil)

let size = CGSize(width: 1920, height: 1080)
let fps = 30.0
let rate = 48_000.0

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Rounded to whole frames, so the pictures and the sound never drift apart.
func frames(_ seconds: Double) -> Int { Int((seconds * fps).rounded()) }

// MARK: Timeline

enum Segment {
    case clip(String, Double)
    case card(String, hold: Double, behind: String?)
    case word(String, hold: Double)
    case duo(Double)
    case shot(Double, from: Double, source: String, crop: String, caption: String)
    case end(Double)
}

let timeline: [Segment] = try String(contentsOf: timelineFile, encoding: .utf8).split(separator: "\n").compactMap { line in
    let parts = line.split(separator: "|", maxSplits: 5).map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count >= 2, !parts[0].hasPrefix("#") else { return nil }
    let seconds = Double(parts[1]) ?? 0
    let text = parts.count > 2 ? parts[2] : ""
    switch parts[0] {
    case "clip": return .clip(text, seconds)
    case "card": return .card(text.replacingOccurrences(of: " / ", with: "\n"), hold: seconds, behind: parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil)
    case "word": return .word(text, hold: seconds)
    case "duo": return .duo(seconds)
    case "shot" where parts.count == 6: return .shot(seconds, from: Double(parts[2]) ?? 0, source: parts[3], crop: parts[4], caption: parts[5])
    case "end": return .end(seconds)
    default: return nil
    }
}

/// When each key is struck, in frames from the start of the segment: a person's unhurried rhythm, steady within a
/// word, a breath at a space, a pause after punctuation. Never the same gap twice in a row.
func strikes(_ text: String, lead: Double = 0.25, pace: Double = 0.62) -> [Int] {
    let rhythm = [0.16, 0.21, 0.14, 0.19, 0.24, 0.15, 0.2, 0.17]
    var t = lead
    var out: [Int] = []
    var previous: Character = " "
    for (i, character) in text.enumerated() {
        out.append(frames(t))
        var gap = rhythm[i % rhythm.count] * pace
        if character == " " { gap += 0.1 }
        if ",.'".contains(character) { gap += 0.22 }
        if character == "\n" { gap += 0.35 }       // the carriage going home between lines
        if previous == character { gap *= 0.8 }
        t += gap
        previous = character
    }
    return out
}

func length(_ segment: Segment) -> Int {
    switch segment {
    case let .clip(_, d), let .duo(d), let .end(d), let .shot(d, _, _, _, _): frames(d)
    case let .card(text, hold, _): (strikes(text).last ?? 0) + frames(hold)
    case let .word(text, hold): (strikes(text, lead: 0.4, pace: 1.1).last ?? 0) + frames(hold)
    }
}

// MARK: Sound

func read(_ url: URL) -> [Float] {
    let file = try! AVAudioFile(forReading: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: source)
    if file.processingFormat.sampleRate == rate, file.processingFormat.channelCount == 1 {
        return Array(UnsafeBufferPointer(start: source.floatChannelData![0], count: Int(source.frameLength)))
    }
    let converter = AVAudioConverter(from: file.processingFormat, to: format)!
    let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * rate / file.processingFormat.sampleRate) + 4096)!
    var fed = false
    converter.convert(to: out, error: nil) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return source
    }
    return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
}

let sounds = root.appendingPathComponent("Carriage/Sounds")
let keys = (1...14).map { read(sounds.appendingPathComponent("portable-key-\($0).wav")) }
let spaces = (1...4).map { read(sounds.appendingPathComponent("portable-space-\($0).wav")) }
let bell = read(sounds.appendingPathComponent("portable-bell-1.wav"))
let carriageReturn = read(sounds.appendingPathComponent("portable-carriageReturn-1.wav"))
let duo = read(duoAudio)

let totalFrames = timeline.map(length).reduce(0, +)
let total = Double(totalFrames) / fps
var effects = [Float](repeating: 0, count: Int(total * rate) + 1)
func add(_ samples: [Float], atFrame frame: Int, gain: Float = 1) {
    // Recorded keys start 3 ms before the strike; line that up with the frame the letter lands on.
    let start = max(0, Int(Double(frame) / fps * rate) - Int(0.003 * rate))
    for (i, v) in samples.enumerated() where start + i < effects.count { effects[start + i] += v * gain }
}
func typeSounds(_ text: String, _ hits: [Int], from start: Int, gain: Float) {
    for (i, (character, hit)) in zip(text, hits).enumerated() {
        if character == "\n" { add(carriageReturn, atFrame: start + hit, gain: gain * 0.45) }
        else if character == " " { add(spaces[i % spaces.count], atFrame: start + hit, gain: gain * 0.9) }
        else { add(keys[(i * 5 + 3) % keys.count], atFrame: start + hit, gain: gain) }
    }
}

// MARK: Pictures

let context = CIContext()
func save(_ draw: (CGRect) -> Void, blur: Bool = false, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    guard blur, let image = CIImage(bitmapImageRep: rep) else {
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        return
    }
    // A shallow depth of field: sharp along the typed line, softer above and below, like a lens up close.
    let mask = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: size.height * 0.36), "inputPoint1": CIVector(x: 0, y: size.height * 0.06),
                                                               "inputColor0": CIColor.black, "inputColor1": CIColor.white])!.outputImage!
    let mirrored = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: size.height * 0.68), "inputPoint1": CIVector(x: 0, y: size.height * 0.95),
                                                                   "inputColor0": CIColor.black, "inputColor1": CIColor.white])!.outputImage!
    let both = mask.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mirrored]).cropped(to: image.extent)
    let blurred = image.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": both, kCIInputRadiusKey: 14]).cropped(to: image.extent)
    try! context.writePNGRepresentation(of: blurred, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}

func paper(_ bounds: CGRect) {
    NSGradient(starting: color(0xF6F1E6), ending: color(0xE9DFCB))!.draw(in: bounds, angle: -90)
    NSGradient(colors: [color(0xFFF4D8, 0.8), color(0xFFF4D8, 0)])!
        .draw(fromCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: 0, toCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: bounds.height * 1.2, options: [])
}

let ink = color(0x24211E)
func typed(_ text: String, size: CGFloat = 96) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [.font: NSFont(name: "CourierPrime-Regular", size: size)!, .foregroundColor: ink, .strokeWidth: -1.4, .strokeColor: ink])
}

/// Paper grain, made once: faint fibres and speckle over the sheet.
let grain: NSImage = {
    let image = NSImage(size: size)
    image.lockFocus()
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for _ in 0..<26000 {
        color(next() > 0.5 ? 0x8A7A60 : 0xFFFFFF, 0.035 + next() * 0.05).setFill()
        NSRect(x: next() * size.width, y: next() * size.height, width: 1 + next() * 2.5, height: 1 + next() * 1.2).fill()
    }
    image.unlockFocus()
    return image
}()

var frameStart = 0
var cards = 0
var shots = 0
var cutList: [String] = []
for segment in timeline {
    let count = length(segment)
    switch segment {
    case let .card(text, _, behind):
        cards += 1
        let folder = work.appendingPathComponent("card-\(cards)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hits = strikes(text)
        // Big enough to read on a phone, broken over lines with " / " in the timeline. Each line is laid out for its
        // whole length, so the letters land where they'll stay instead of the line re-centring as it grows.
        let lines = text.components(separatedBy: "\n")
        let cardType: CGFloat = 150
        let lineHeight = typed("M", size: cardType).size().height * 1.05
        let blockTop = size.height / 2 + lineHeight * CGFloat(lines.count) / 2
        let origins = lines.enumerated().map { i, line in
            CGPoint(x: (size.width - typed(line, size: cardType).size().width) / 2, y: blockTop - lineHeight * CGFloat(i + 1))
        }
        for f in 0..<count {
            let shown = hits.filter { $0 <= f }.count
            save({ bounds in
                // Over footage, only the words are drawn; make.sh lays them on the faded shot.
                if behind == nil { paper(bounds) }
                var left = shown
                for (i, line) in lines.enumerated() where left > 0 {
                    typed(String(line.prefix(left)), size: cardType).draw(at: origins[i])
                    left -= line.count + 1
                }
                if shown == text.count {
                    color(0xA22D27).setFill()
                    NSBezierPath(roundedRect: CGRect(x: size.width / 2 - 50, y: (origins.last?.y ?? 0) - 44, width: 100, height: 10), xRadius: 5, yRadius: 5).fill()
                }
            }, to: folder.appendingPathComponent(String(format: "frame-%04d.png", f)))
        }
        typeSounds(text, hits, from: frameStart, gain: 0.85)
        cutList.append("card card-\(cards) \(count) \(behind ?? "-")")

    case let .word(text, _):
        // Up close on the sheet: the typing point stays put and the paper steps left a letter at a time, as the
        // carriage does; each strike jolts the page a hair.
        let folder = work.appendingPathComponent("word")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hits = strikes(text, lead: 0.4, pace: 1.1)
        let fontSize: CGFloat = 250
        let advance = typed("M", size: fontSize).size().width
        let lineY = size.height * 0.44
        var shades: [CGFloat] = []
        var seed: UInt64 = 42
        for _ in text { seed = seed &* 6364136223846793005 &+ 1; shades.append(0.86 + CGFloat(seed >> 40) / CGFloat(1 << 24) * 0.14) }
        for f in 0..<count {
            let shown = hits.filter { $0 <= f }.count
            // The carriage glides a letter left over two frames after each strike.
            var offset: CGFloat = 0
            for hit in hits where hit <= f { offset += advance * min(1, CGFloat(f - hit) / 2) }
            let jolt: CGFloat = hits.contains(f) ? 3 : (hits.contains(f - 1) ? 1 : 0)
            save({ bounds in
                paper(bounds)
                grain.draw(in: bounds)
                // The typing point sits right of centre, so the finished word ends up centred.
                let typingPoint = size.width / 2 + advance * CGFloat(text.count) / 2
                for (i, character) in text.prefix(shown).enumerated() {
                    let x = typingPoint - offset + advance * CGFloat(i)
                    let letter = NSAttributedString(string: String(character), attributes: [
                        .font: NSFont(name: "CourierPrime-Regular", size: fontSize)!, .foregroundColor: ink.withAlphaComponent(shades[i]),
                        .strokeWidth: -1.0, .strokeColor: ink.withAlphaComponent(shades[i] * 0.9),
                    ])
                    letter.draw(at: CGPoint(x: x, y: lineY - jolt + CGFloat(i % 3) * 0.8))
                }
                // The platen and ribbon guide, out of focus at the bottom of the frame.
                NSGradient(colors: [color(0x1E1B18, 0.92), color(0x1E1B18, 0.6), color(0x1E1B18, 0)])!
                    .draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.26), angle: 90)
            }, blur: true, to: folder.appendingPathComponent(String(format: "frame-%04d.png", f)))
        }
        typeSounds(text, hits, from: frameStart, gain: 1)
        cutList.append("word word \(count)")

    case let .clip(name, _):
        if name == "return" {
            add(bell, atFrame: frameStart + 4, gain: 0.6)
            add(carriageReturn, atFrame: frameStart + frames(0.6), gain: 0.9)
        }
        cutList.append("clip \(name) \(count)")

    case .duo:
        let from = Int((Double(ProcessInfo.processInfo.environment["DUO_FROM"] ?? "5.5") ?? 5.5) * rate)
        add(Array(duo[min(from, duo.count)..<min(duo.count, from + Int(Double(count) / fps * rate) + Int(rate))]), atFrame: frameStart)
        cutList.append("duo duo \(count)")

    case let .shot(_, from, source, crop, caption):
        shots += 1
        // Its own sound, from the same moment of the recording.
        let a = Int(from * rate), b = min(duo.count, a + Int(Double(count) / fps * rate))
        if a < b { add(Array(duo[a..<b]), atFrame: frameStart) }
        // The caption: a cream band across the top, the line set large enough to read on a phone, sound off.
        let url = work.appendingPathComponent("caption-\(shots).png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let line = typed(caption, size: 76)
        let w = line.size().width + 110, h: CGFloat = 132
        let band = CGRect(x: (size.width - w) / 2, y: size.height - h - 56, width: w, height: h)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        color(0xF6F1E6, 0.96).setFill()
        NSBezierPath(roundedRect: band, xRadius: 22, yRadius: 22).fill()
        NSGraphicsContext.restoreGraphicsState()
        line.draw(at: CGPoint(x: band.minX + 55, y: band.midY - line.size().height / 2))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        cutList.append("shot caption-\(shots) \(count) \(from) \(source) \(crop)")

    case .end:
        let folder = work.appendingPathComponent("card-end")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let icon = NSImage(contentsOf: root.appendingPathComponent("Carriage/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))!
        let tagline = ProcessInfo.processInfo.environment["TAGLINE"] ?? "Write with intent."
        save({ bounds in
            paper(bounds)
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            NSGraphicsContext.saveGraphicsState()
            let iconRect = CGRect(x: bounds.midX - 100, y: 660, width: 200, height: 200)
            NSBezierPath(roundedRect: iconRect, xRadius: 45, yRadius: 45).addClip()
            icon.draw(in: iconRect)
            NSGraphicsContext.restoreGraphicsState()
            NSAttributedString(string: "Carriage", attributes: [.font: NSFont(name: "CourierPrime-Regular", size: 132)!, .foregroundColor: ink, .strokeWidth: -1.4, .strokeColor: ink, .paragraphStyle: centred])
                .draw(with: CGRect(x: 0, y: 470, width: bounds.width, height: 170), options: [.usesLineFragmentOrigin])
            color(0xA22D27).setFill()
            NSBezierPath(roundedRect: CGRect(x: bounds.midX - 50, y: 452, width: 100, height: 10), xRadius: 5, yRadius: 5).fill()
            NSAttributedString(string: tagline, attributes: [.font: NSFont(name: "CourierPrime-Regular", size: 70)!, .foregroundColor: ink, .paragraphStyle: centred])
                .draw(with: CGRect(x: 0, y: 320, width: bounds.width, height: 100), options: [.usesLineFragmentOrigin])
            NSAttributedString(string: "FOR IPHONE DUO  ·  ON THE APP STORE  ·  CARRIAGE.PAGES.DEV", attributes: [.font: NSFont(name: "Futura-Medium", size: 34)!, .foregroundColor: ink.withAlphaComponent(0.7), .kern: 5, .paragraphStyle: centred])
                .draw(with: CGRect(x: 0, y: 220, width: bounds.width, height: 60), options: [.usesLineFragmentOrigin])
        }, to: folder.appendingPathComponent("frame.png"))
        cutList.append("end card-end \(count)")
    }
    frameStart += count
}

// MARK: Mix

// Music under everything, soft, faded in and out, and dipped a little while the Duo plays so its keys come through.
var mix = effects
if let musicFile {
    let music = read(musicFile)
    let duoStart = Double(timeline.prefix { if case .duo = $0 { false } else { true } }.map(length).reduce(0, +)) / fps
    let duoEnd = duoStart + Double(timeline.first { if case .duo = $0 { true } else { false } }.map(length) ?? 0) / fps
    for i in mix.indices where i < music.count {
        let s = Double(i) / rate
        var g = 0.75 * min(1, s / 2) * min(1, (total - s) / 3)
        if s > duoStart - 1, s < duoEnd + 1 { g *= 0.55 }
        mix[i] += music[i] * Float(g)
    }
}

let peak = max(1, mix.map(abs).max() ?? 1)
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mix.count))!
buffer.frameLength = AVAudioFrameCount(mix.count)
for i in mix.indices { buffer.floatChannelData![0][i] = mix[i] / peak * 0.95 }
let soundtrack = work.appendingPathComponent("soundtrack.wav")
try? FileManager.default.removeItem(at: soundtrack)
try AVAudioFile(forWriting: soundtrack, settings: format.settings).write(from: buffer)

// The cut list, for make.sh: kind, name, frames.
print(cutList.joined(separator: "\n"))
