import Foundation
import Observation

/// The writer's preferences, kept in UserDefaults.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var finish: MachineFinish { didSet { save(finish.rawValue, "finish") } }
    var machineSound: MachineSound { didSet { save(machineSound.rawValue, "machineSound") } }
    var typeface: Typeface { didSet { save(typeface.rawValue, "typeface") } }
    var carriage: CarriageTravel { didSet { save(carriage.rawValue, "carriage") } }
    var lineWidth: LineWidth { didSet { save(lineWidth.rawValue, "lineWidth") } }
    var lineSpacing: LineSpacing { didSet { save(lineSpacing.rawValue, "lineSpacing") } }
    /// The mode, paper and ink a new sheet starts with.
    var defaultMode: TypingMode { didSet { save(defaultMode.rawValue, "defaultMode") } }
    var defaultPaper: PaperStyle { didSet { save(defaultPaper.rawValue, "defaultPaper") } }
    var defaultInk: InkStyle { didSet { save(defaultInk.rawValue, "defaultInk") } }

    var soundsOn: Bool { didSet { save(soundsOn, "soundsOn") } }
    var volume: Double { didSet { save(volume, "volume") } }
    var playsInSilentMode: Bool { didSet { save(playsInSilentMode, "playsInSilentMode") } }
    var hapticsOn: Bool { didSet { save(hapticsOn, "hapticsOn") } }
    var typebarsOn: Bool { didSet { save(typebarsOn, "typebarsOn") } }
    /// Off, like a real machine: at the right margin the keys stop until the carriage is returned. On, a line
    /// that runs past the margin wraps and the carriage returns by itself.
    var autoReturn: Bool { didSet { save(autoReturn, "autoReturn") } }
    /// Ring the bell a few characters before the right margin.
    var marginBell: Bool { didSet { save(marginBell, "marginBell") } }
    var bellOnReturn: Bool { didSet { save(bellOnReturn, "bellOnReturn") } }
    /// Underline misspellings. Nothing is ever corrected.
    var spellCheck: Bool { didSet { save(spellCheck, "spellCheck") } }
    /// Use the system keyboard instead of the typewriter keys, for dictation, other languages and assistive input.
    var useSystemKeyboard: Bool { didSet { save(useSystemKeyboard, "useSystemKeyboard") } }
    var autoHideControls: Bool { didSet { save(autoHideControls, "autoHideControls") } }
    /// Shift lights up by itself at the start of a sentence. Nothing typed is ever changed afterwards.
    var autoCapitalize: Bool { didSet { save(autoCapitalize, "autoCapitalize") } }
    var keyboardStyle: KeyboardStyle { didSet { save(keyboardStyle.rawValue, "keyboardStyle") } }
    /// Keep a Markdown copy of every page in the Files app.
    var mirrorToFiles: Bool { didSet { save(mirrorToFiles, "mirrorToFiles") } }
    /// Dark paper with light ink.
    var nightDesk: NightDesk { didSet { save(nightDesk.rawValue, "nightDesk") } }

    /// A name engraved on the machine's brass plate, beside CARRIAGE. Empty for a plain plate.
    var engraving: String { didSet { save(engraving, "engraving") } }
    /// This machine's serial number, stamped once on first launch.
    let serialNumber: Int
    /// The ambient sound under the keys.
    var ambience: Ambience { didSet { save(ambience.rawValue, "ambience") } }
    /// A warm lamp over the desk that follows the time of day.
    var deskLamp: Bool { didSet { save(deskLamp, "deskLamp") } }

    /// Daily word goal; 0 means no goal.
    var dailyGoal: Int { didSet { save(dailyGoal, "dailyGoal") } }
    var focusMinutes: Int { didSet { save(focusMinutes, "focusMinutes") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T {
            (defaults.object(forKey: key) as? T.RawValue).flatMap { T(rawValue: $0) } ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        finish = value("finish", .seafoam)
        machineSound = value("machineSound", .portable)
        let face: Typeface = value("typeface", Typeface.preferred)
        typeface = face.isAvailable ? face : .preferred
        carriage = value("carriage", .gentle)
        lineWidth = value("lineWidth", .standard)
        lineSpacing = value("lineSpacing", .single)
        // As real as possible by default: no delete, and the keys stop at the margin. Both are a setting away.
        defaultMode = value("defaultMode", .typewriter)
        defaultPaper = value("defaultPaper", .bond)
        defaultInk = value("defaultInk", .black)
        soundsOn = bool("soundsOn", true)
        volume = defaults.object(forKey: "volume") as? Double ?? 0.85
        playsInSilentMode = bool("playsInSilentMode", false)
        hapticsOn = bool("hapticsOn", true)
        typebarsOn = bool("typebarsOn", true)
        autoReturn = bool("autoReturn", false)
        marginBell = bool("marginBell", true)
        bellOnReturn = bool("bellOnReturn", true)
        spellCheck = bool("spellCheck", false)
        useSystemKeyboard = bool("useSystemKeyboard", false)
        autoHideControls = bool("autoHideControls", true)
        autoCapitalize = bool("autoCapitalize", true)
        keyboardStyle = value("keyboardStyle", .full)
        mirrorToFiles = bool("mirrorToFiles", true)
        nightDesk = value("nightDesk", .system)
        engraving = defaults.string(forKey: "engraving") ?? ""
        if let serial = defaults.object(forKey: "serialNumber") as? Int {
            serialNumber = serial
        } else {
            serialNumber = Int.random(in: 1_000...99_999)
            defaults.set(serialNumber, forKey: "serialNumber")
        }
        ambience = value("ambience", .off)
        deskLamp = bool("deskLamp", true)
        dailyGoal = defaults.object(forKey: "dailyGoal") as? Int ?? 500
        focusMinutes = defaults.object(forKey: "focusMinutes") as? Int ?? 25
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
