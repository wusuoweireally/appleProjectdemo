import SwiftUI

struct Book: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let author: String
    var lastChapter: Int
    let isBuiltIn: Bool
    let fileName: String?
    let filePath: String?
    let coverColors: [String]
    let importedAt: Date?

    var colors: [Color] { coverColors.map { Color(hex: UInt32($0.dropFirst(), radix: 16) ?? 0xFC5B26) } }

    var progressTitle: String {
        lastChapter == 0 ? title : "第 \(lastChapter + 1) 章"
    }
}

extension Book {
    static let builtIn = Book(
        id: "builtin-001",
        title: "神御之权",
        author: "keyprca",
        lastChapter: 0,
        isBuiltIn: true,
        fileName: nil,
        filePath: nil,
        coverColors: ["#FC5B26", "#FF8C42"],
        importedAt: nil
    )

    private static let palette: [[String]] = [
        ["#3A5AAB", "#6FB1FC"],
        ["#2E8B57", "#66BB6A"],
        ["#6A1B9A", "#AB47BC"],
        ["#D4A017", "#F5D76E"],
        ["#C0392B", "#E74C3C"],
        ["#1ABC9C", "#16A085"],
    ]

    static func new(title: String, filePath: String, fileName: String) -> Book {
        let colors = palette[Int.random(in: 0..<palette.count)]
        return Book(
            id: UUID().uuidString,
            title: title,
            author: "未知作者",
            lastChapter: 0,
            isBuiltIn: false,
            fileName: fileName,
            filePath: filePath,
            coverColors: colors,
            importedAt: Date()
        )
    }
}
