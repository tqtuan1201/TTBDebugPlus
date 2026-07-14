//
//  ColorPickerToolViewModel.swift
//  TTBDebugPlus
//
//  Orchestrates color state, formats, palette, WCAG, and clipboard for Color Picker.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ColorPickerToolViewModel {

    // MARK: - Defaults keys

    private enum DefaultsKey {
        static let history = "colorPicker.history"
        static let historyDay = "colorPicker.historyDay"
        static let selectedFormat = "colorPicker.selectedFormat"
    }

    private static let maxPalette = 50
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - State

    var hue: Double = ColorHSB.default.hue
    var saturation: Double = ColorHSB.default.saturation
    var brightness: Double = ColorHSB.default.brightness
    var alpha: Double = ColorHSB.default.alpha

    var hexInput: String = ""
    var hexInputError: String?

    var sessionPalette: [PaletteColorEntry] = []
    var selectedFormat: ColorFormat = .hex {
        didSet { persistSelectedFormat() }
    }

    var foregroundHSB: ColorHSB?
    var backgroundHSB: ColorHSB?

    var statusMessage: String?
    var samplerHint: String?
    var lastCopiedFormat: ColorFormat?
    var isSampling = false

    // MARK: - Dependencies

    @ObservationIgnored
    private let sampler: any ColorSamplerServing

    @ObservationIgnored
    private var statusClearTask: Task<Void, Never>?

    @ObservationIgnored
    private var copyFlashClearTask: Task<Void, Never>?

    // MARK: - Init

    init(sampler: (any ColorSamplerServing)? = nil) {
        self.sampler = sampler ?? ColorSamplerService()
        syncHexFromHSB()
        loadPersistedState()
    }

    deinit {
        statusClearTask?.cancel()
        copyFlashClearTask?.cancel()
    }

    // MARK: - Derived

    var currentHSB: ColorHSB {
        ColorHSB(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }

    var currentRGB: ColorFormatEngine.RGB {
        ColorFormatEngine.rgb(from: currentHSB)
    }

    var normalizedHex: String {
        ColorFormatEngine.normalizedHex(from: currentHSB)
    }

    var previewNSColor: NSColor {
        let c = currentRGB
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    func formatString(_ format: ColorFormat) -> String {
        ColorFormatEngine.string(for: format, hsb: currentHSB)
    }

    var wcagResult: WCAGResult? {
        guard let fg = foregroundHSB, let bg = backgroundHSB else { return nil }
        return WCAGContrastEngine.contrastRatio(fg: fg, bg: bg)
    }

    var designTokenMatches: [TokenMatch] {
        DesignTokenMatcher.matches(for: currentHSB)
    }

    var canExportPalette: Bool {
        !sessionPalette.isEmpty
    }

    // MARK: - Mutations

    func setHSB(_ hsb: ColorHSB, addToPalette: Bool = false) {
        hue = ColorFormatEngine.clamp01(hsb.hue)
        saturation = ColorFormatEngine.clamp01(hsb.saturation)
        brightness = ColorFormatEngine.clamp01(hsb.brightness)
        alpha = ColorFormatEngine.clamp01(hsb.alpha)
        hexInputError = nil
        syncHexFromHSB()
        if addToPalette {
            addCurrentToPalette()
        }
    }

    func applyHexInput() {
        let raw = hexInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rgb = ColorFormatEngine.parseHex(raw) else {
            hexInputError = "Invalid hex. Use #RGB, #RRGGBB, or #AARRGGBB."
            return
        }
        let hsb = ColorFormatEngine.hsb(from: rgb)
        setHSB(hsb)
        flashStatus("Applied \(normalizedHex)")
    }

    func pickFromScreen() async {
        guard !isSampling else { return }
        isSampling = true
        samplerHint = nil
        defer { isSampling = false }

        let color = await sampler.sampleScreenColor()
        guard let color else {
            flashStatus("Pick cancelled")
            return
        }

        guard let srgb = color.usingColorSpace(.sRGB) else {
            samplerHint = "Could not convert sampled color to sRGB. Try manual Hex input."
            flashStatus("Color conversion failed")
            return
        }

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hsb = ColorFormatEngine.hsb(
            from: ColorFormatEngine.RGB(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
        )
        setHSB(hsb, addToPalette: true)
        flashStatus("Picked \(normalizedHex)")
    }

    func copyFormat(_ format: ColorFormat) {
        let value = formatString(format)
        writePasteboard(value)
        selectedFormat = format
        lastCopiedFormat = format
        flashStatus("Copied \(format.displayName)")
        scheduleCopyFlashClear()
    }

    func copyAllFormats() {
        writePasteboard(ColorFormatEngine.allFormatsBlock(hsb: currentHSB))
        lastCopiedFormat = nil
        flashStatus("Copied all formats")
    }

    func addCurrentToPalette() {
        let hex = normalizedHex
        sessionPalette.removeAll { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
        let entry = PaletteColorEntry(
            hex: hex,
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: alpha
        )
        sessionPalette.insert(entry, at: 0)
        if sessionPalette.count > Self.maxPalette {
            sessionPalette = Array(sessionPalette.prefix(Self.maxPalette))
        }
        persistPalette()
    }

    func selectPaletteEntry(_ entry: PaletteColorEntry) {
        setHSB(
            ColorHSB(
                hue: entry.hue,
                saturation: entry.saturation,
                brightness: entry.brightness,
                alpha: entry.alpha
            )
        )
    }

    func clearPalette() {
        sessionPalette = []
        persistPalette()
        flashStatus("Palette cleared")
    }

    func exportPaletteJSON() -> String? {
        guard !sessionPalette.isEmpty else { return nil }
        let payload = sessionPalette.map { entry in
            [
                "hex": entry.hex,
                "hue": entry.hue,
                "saturation": entry.saturation,
                "brightness": entry.brightness,
                "alpha": entry.alpha
            ] as [String: Any]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        writePasteboard(text)
        flashStatus("Exported palette JSON")
        return text
    }

    func setAsForeground() {
        foregroundHSB = currentHSB
        flashStatus("Foreground set")
    }

    func setAsBackground() {
        backgroundHSB = currentHSB
        flashStatus("Background set")
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.selectedFormat),
           let format = ColorFormat(rawValue: raw) {
            selectedFormat = format
        }

        let today = Self.dayFormatter.string(from: Date())
        let storedDay = UserDefaults.standard.string(forKey: DefaultsKey.historyDay)
        if storedDay != today {
            sessionPalette = []
            UserDefaults.standard.set(today, forKey: DefaultsKey.historyDay)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.history)
            return
        }

        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.history) else { return }
        if let decoded = try? JSONDecoder().decode([PaletteColorEntry].self, from: data) {
            sessionPalette = Array(decoded.prefix(Self.maxPalette))
        }
    }

    private func persistPalette() {
        let today = Self.dayFormatter.string(from: Date())
        UserDefaults.standard.set(today, forKey: DefaultsKey.historyDay)
        if let data = try? JSONEncoder().encode(sessionPalette) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.history)
        }
    }

    private func persistSelectedFormat() {
        UserDefaults.standard.set(selectedFormat.rawValue, forKey: DefaultsKey.selectedFormat)
    }

    // MARK: - Helpers

    private func syncHexFromHSB() {
        hexInput = normalizedHex
    }

    private func writePasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func flashStatus(_ message: String) {
        statusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.statusMessage = nil
            }
        }
    }

    private func scheduleCopyFlashClear() {
        copyFlashClearTask?.cancel()
        copyFlashClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.lastCopiedFormat = nil
            }
        }
    }
}
