import SwiftUI

/// 集中管理持久化的阅读偏好（UserDefaults / @AppStorage）。
/// 阅读位置按书 ID 独立记录，主题、字号、行距为全局偏好。
final class ReaderSettings: ObservableObject {
    @AppStorage("theme")        var theme: String = ReadingTheme.paper.rawValue
    @AppStorage("fontSize")     var fontSize: Double = 18
    @AppStorage("lineSpacing")  var lineSpacing: Double = 10
    @AppStorage("seamlessScroll") var seamlessScroll = false

    var readingTheme: ReadingTheme {
        get { ReadingTheme(rawValue: theme) ?? .paper }
        set { theme = newValue.rawValue }
    }

    func lastChapter(for bookId: String) -> Int {
        UserDefaults.standard.integer(forKey: "lastChapter_\(bookId)")
    }

    func setLastChapter(_ chapter: Int, for bookId: String) {
        UserDefaults.standard.set(chapter, forKey: "lastChapter_\(bookId)")
    }
}

/// 把正文里匹配的角色名替换为新名字（用户在「角色名替换」里配置）。
/// 写成全局函数，让滚动模式与翻页模式共用同一份逻辑。
func replacedNames(_ text: String) -> String {
    let defaults = UserDefaults.standard
    let from = (defaults.string(forKey: "nameFrom") ?? "陈晓")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let to = (defaults.string(forKey: "nameTo") ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !from.isEmpty, !to.isEmpty, from != to else { return text }
    return text.replacingOccurrences(of: from, with: to)
}
