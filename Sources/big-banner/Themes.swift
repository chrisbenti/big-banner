import AppKit

/// A banner color scheme. Flashing themes alternate between the `a` and `b`
/// pairs; static themes only ever show `a`.
struct Theme {
    let flag: String
    let summary: String
    let bgA: NSColor
    let fgA: NSColor
    let bgB: NSColor
    let fgB: NSColor
    let flashes: Bool

    init(flag: String, summary: String,
         bgA: NSColor, fgA: NSColor, bgB: NSColor, fgB: NSColor) {
        self.flag = flag
        self.summary = summary
        self.bgA = bgA
        self.fgA = fgA
        self.bgB = bgB
        self.fgB = fgB
        self.flashes = true
    }

    /// Static (non-flashing) theme.
    init(flag: String, summary: String, bg: NSColor, fg: NSColor) {
        self.flag = flag
        self.summary = summary
        self.bgA = bg
        self.fgA = fg
        self.bgB = bg
        self.fgB = fg
        self.flashes = false
    }
}

/// Banner background alpha shared by the flashing themes.
private let flashBgAlpha: CGFloat = 0.92

enum Themes {
    // Calm blue, the default.
    static let primary = Theme(
        flag: "--primary",
        summary: "Flashing blue/sky (default)",
        bgA: NSColor(red: 0.10, green: 0.30, blue: 0.75, alpha: flashBgAlpha),
        fgA: .white,
        bgB: NSColor(red: 0.45, green: 0.75, blue: 0.97, alpha: flashBgAlpha),
        fgB: NSColor(red: 0.03, green: 0.10, blue: 0.22, alpha: 1.0)
    )

    // Purple
    static let secondary = Theme(
        flag: "--secondary",
        summary: "Flashing purple/lavender",
        bgA: NSColor(red: 0.35, green: 0.15, blue: 0.60, alpha: flashBgAlpha),
        fgA: .white,
        bgB: NSColor(red: 0.78, green: 0.65, blue: 0.96, alpha: flashBgAlpha),
        fgB: NSColor(red: 0.13, green: 0.05, blue: 0.25, alpha: 1.0)
    )

    // Green
    static let tertiary = Theme(
        flag: "--tertiary",
        summary: "Flashing green/lime",
        bgA: NSColor(red: 0.05, green: 0.45, blue: 0.25, alpha: flashBgAlpha),
        fgA: .white,
        bgB: NSColor(red: 0.62, green: 0.86, blue: 0.32, alpha: flashBgAlpha),
        fgB: NSColor(red: 0.04, green: 0.14, blue: 0.04, alpha: 1.0)
    )

    // Deep warning red and amber gold
    static let danger = Theme(
        flag: "--danger",
        summary: "Flashing red/yellow",
        bgA: NSColor(red: 0.68, green: 0.09, blue: 0.07, alpha: flashBgAlpha),
        fgA: .white,
        bgB: NSColor(red: 0.90, green: 0.68, blue: 0.03, alpha: flashBgAlpha),
        fgB: NSColor(red: 0.10, green: 0.07, blue: 0.01, alpha: 1.0)
    )

    static let monochrome = Theme(
        flag: "--monochrome",
        summary: "Static black/white",
        bg: NSColor.black.withAlphaComponent(0.85),
        fg: .white
    )

    static let all = [primary, secondary, tertiary, danger, monochrome]
    static let `default` = primary
}
