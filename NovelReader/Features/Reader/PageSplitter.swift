import UIKit

/// 用 TextKit 把章节正文切成"一屏一页"的若干段，供横向翻页使用。
///
/// 思路：让 NSLayoutManager 在「页面宽度、无限高」的容器里排版全文，
/// 逐行累加高度，超过页面可用高度即在该行前切页；用字符索引切出子串。
enum PageSplitter {
    static func split(
        _ text: String,
        font: UIFont,
        lineSpacing: CGFloat,
        pageSize: CGSize,
        contentInset: UIEdgeInsets
    ) -> [String] {
        let width  = pageSize.width  - contentInset.left - contentInset.right
        let height = pageSize.height - contentInset.top  - contentInset.bottom
        guard width > 50, height > 50, !text.isEmpty else { return [text] }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping

        let storage = NSTextStorage()
        storage.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph
        ]))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineBreakMode = .byWordWrapping
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        let totalGlyphs = layout.numberOfGlyphs
        guard totalGlyphs > 0 else { return [text] }

        let nsText = text as NSString
        var pages: [String] = []
        var pageTopMaxY: CGFloat = 0     // 当前页首行的顶（minY 基准）
        var pageStartChar = 0            // 当前页起始字符 index

        var glyph = 0
        while glyph < totalGlyphs {
            var lineRange = NSRange(location: 0, length: 0)
            let lineRect = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &lineRange)

            if lineRect.maxY - pageTopMaxY > height {
                // 本行放进当前页会超高，先封口上一页
                let endChar = layout.characterIndexForGlyph(at: glyph)
                if endChar > pageStartChar {
                    pages.append(nsText.substring(with: NSRange(location: pageStartChar, length: endChar - pageStartChar)))
                    pageStartChar = endChar
                    pageTopMaxY = lineRect.minY
                    continue                       // 本行作为新页首行，重新判断
                } else {
                    // 单行就超过一整页：强行让该行独占一页，避免死循环
                    let nextGlyph = NSMaxRange(lineRange)
                    let nextChar = nextGlyph < totalGlyphs
                        ? layout.characterIndexForGlyph(at: nextGlyph)
                        : nsText.length
                    pages.append(nsText.substring(with: NSRange(location: pageStartChar, length: nextChar - pageStartChar)))
                    pageStartChar = nextChar
                    pageTopMaxY = lineRect.maxY
                    glyph = nextGlyph
                    continue
                }
            }
            glyph = NSMaxRange(lineRange)
        }
        if pageStartChar < nsText.length {
            pages.append(nsText.substring(from: pageStartChar))
        }
        return pages.isEmpty ? [text] : pages
    }
}
