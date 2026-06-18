import Foundation

/// 把整本小说的纯文本切成章节。
///
/// 规则：行首（去掉全角空格/制表符/BOM 后）以「楔子 / 第N章 / 番外」开头，
/// 且整行较短（≤ 40 字）才视为标题，避免正文段落里的同名词被误判。
enum ChapterParser {
    private static let maxTitleLength = 40

    static func parse(_ raw: String) -> [Chapter] {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var titleLines: [Int] = []
        for (i, line) in lines.enumerated() {
            let cleaned = clean(line)
            guard cleaned.count <= maxTitleLength,
                  cleaned.range(of: #"^(?:楔子|[第序终][0-9零一二三四五六七八九十百千]+[章节卷部集回]|Chapter\s*\d+|番外|序[章言文]?|后记|尾声|终章|引子|前言|尾声)"#, options: .regularExpression) != nil
            else { continue }
            titleLines.append(i)
        }
        guard !titleLines.isEmpty else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [Chapter(id: 0, title: "正文", content: trimmed)]
        }

        var chapters: [Chapter] = []
        for (idx, startLine) in titleLines.enumerated() {
            let bodyStart = startLine + 1
            let bodyEnd = idx + 1 < titleLines.count ? titleLines[idx + 1] - 1 : lines.count - 1
            let body = lines[bodyStart...max(bodyEnd, bodyStart)]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(Chapter(id: idx, title: clean(lines[startLine]), content: body))
        }
        return chapters
    }

    /// 去掉首尾空白、全角空格(U+3000)与 BOM(U+FEFF)。
    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = t.first, first == "\u{3000}" || first == "\u{FEFF}" { t.removeFirst() }
        while let last = t.last, last == "\u{3000}" { t.removeLast() }
        return t
    }
}
