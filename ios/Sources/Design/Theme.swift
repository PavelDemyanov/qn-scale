import SwiftUI

/// Палитра из прототипа. Значения — один в один CSS-переменные макета.
enum Palette {
    case dark, light

    private func c(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: opacity)
    }

    var bg: Color { self == .dark ? c(0x000000) : c(0xF2F2F7) }
    var card: Color { self == .dark ? c(0x1C1C1E) : c(0xFFFFFF) }
    var card2: Color { self == .dark ? c(0x2C2C2E) : c(0xEFEFF4) }
    var seg: Color { self == .dark ? c(0x767680, 0.24) : c(0x767680, 0.12) }
    var fg: Color { self == .dark ? c(0xFFFFFF) : c(0x000000) }
    var fg2: Color { self == .dark ? c(0xEBEBF5, 0.6) : c(0x3C3C43, 0.6) }
    var fg3: Color { self == .dark ? c(0xEBEBF5, 0.34) : c(0x3C3C43, 0.35) }
    var sep: Color { self == .dark ? c(0x545458, 0.5) : c(0x3C3C43, 0.13) }
    var blue: Color { self == .dark ? c(0x0A84FF) : c(0x007AFF) }
    var green: Color { self == .dark ? c(0x30D158) : c(0x34C759) }
    var orange: Color { self == .dark ? c(0xFF9F0A) : c(0xFF9500) }
    var red: Color { self == .dark ? c(0xFF453A) : c(0xFF3B30) }
    var tabBar: Color { self == .dark ? c(0x161618, 0.86) : c(0xF9F9F9, 0.88) }
    var tabIcon: Color { self == .dark ? c(0xEBEBF5, 0.38) : c(0x3C3C43, 0.42) }
    var sheet: Color { self == .dark ? c(0x1C1C1E) : c(0xF2F2F7) }

    /// Карточка на фоне шторки. В тёмной теме обычный цвет карточки совпадает
    /// с цветом шторки, и она пропадает, — там берём тон светлее.
    var cardOnSheet: Color { self == .dark ? card2 : card }

    /// Зелёный — вес ушёл, красный — пришёл.
    ///
    /// Красный, а не оранжевый: тем же красным набор веса показывают столбики
    /// недели и плашки на главном графике, и оранжевая дельта спорила с ними
    /// на одном экране — одно и то же число оказывалось двух цветов. Заодно
    /// оранжевый остаётся за одним смыслом: процент жира.
    func delta(_ v: Double) -> Color {
        v < -0.0049 ? green : v > 0.0049 ? red : fg2
    }

    func deltaTint(_ v: Double) -> Color {
        v < -0.0049 ? green.opacity(0.16) : v > 0.0049 ? red.opacity(0.16) : seg
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
