import SwiftUI

extension Color {
    /// 用 `Color(hex: 0xFC5B26)` 这样的十六进制整数构造颜色。
    init(hex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
