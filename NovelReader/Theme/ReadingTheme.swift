import SwiftUI

/// 阅读背景主题。配色参考主流阅读 App 的几种纸张/夜间风格。
enum ReadingTheme: String, CaseIterable, Identifiable {
    case paper, cream, mint, sepia, night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper:  "白"
        case .cream:  "黄"
        case .mint:   "绿"
        case .sepia:  "褐"
        case .night:  "夜"
        }
    }

    var background: Color {
        switch self {
        case .paper:  Color(hex: 0xF6F4EE)
        case .cream:  Color(hex: 0xF3EAD3)
        case .mint:   Color(hex: 0xCCDFCC)
        case .sepia:  Color(hex: 0xE3D2B7)
        case .night:  Color(hex: 0x141414)
        }
    }

    var text: Color {
        switch self {
        case .paper:  Color(hex: 0x2C2A26)
        case .cream:  Color(hex: 0x4A3C24)
        case .mint:   Color(hex: 0x244024)
        case .sepia:  Color(hex: 0x3D2A18)
        case .night:  Color(hex: 0x909090)
        }
    }

    var secondaryText: Color { text.opacity(0.55) }

    var isDark: Bool { self == .night }
}
