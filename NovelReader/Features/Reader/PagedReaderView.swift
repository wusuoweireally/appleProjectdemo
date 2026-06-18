import SwiftUI
import UIKit

/// 横向翻页阅读容器，包装 UIPageViewController。
/// 页内左右滑动翻页；到章节首/末页自动跨章。
struct PagedReaderView: UIViewControllerRepresentable {
    let chapterId: Int
    let chapterTitle: String
    let pages: [String]
    let targetPageIndex: Int
    let prevLastPage: String?
    let prevChapterTitle: String
    let nextFirstPage: String?
    let nextChapterTitle: String
    let theme: ReadingTheme
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let onTapCenter: () -> Void
    let pageTurnToken: Int
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        context.coordinator.parent = self
        context.coordinator.apply(to: pvc, force: true)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(to: pvc, force: false)
        context.coordinator.handlePageTurnIfNeeded(token: pageTurnToken, in: pvc)
    }

    private var signature: String {
        "\(chapterId)|\(pages.count)|\(Int(fontSize))|\(Int(lineSpacing))|\(theme.rawValue)|\(targetPageIndex)"
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReaderView!
        var lastSignature: String = ""
        var lastPageTurnToken: Int = 0

        func apply(to pvc: UIPageViewController, force: Bool) {
            guard force || lastSignature != parent.signature else { return }
            lastSignature = parent.signature
            let idx = min(max(0, parent.targetPageIndex), max(parent.pages.count - 1, 0))
            if let vc = pageController(for: idx) {
                pvc.setViewControllers([vc], direction: .forward, animated: false)
            }
        }

        func handlePageTurnIfNeeded(token: Int, in pvc: UIPageViewController) {
            guard token != lastPageTurnToken else { return }
            let isNext = token > lastPageTurnToken
            lastPageTurnToken = token
            guard let currentVC = pvc.viewControllers?.first else { return }
            let current = currentVC.view.tag

            if isNext {
                if current < parent.pages.count - 1, let vc = pageController(for: current + 1) {
                    pvc.setViewControllers([vc], direction: .forward, animated: true)
                } else if let page = parent.nextFirstPage {
                    let vc = boundaryController(tag: -2, title: parent.nextChapterTitle, text: page)
                    pvc.setViewControllers([vc], direction: .forward, animated: true)
                    DispatchQueue.main.async { self.parent.onNextChapter() }
                }
            } else {
                if current > 0, let vc = pageController(for: current - 1) {
                    pvc.setViewControllers([vc], direction: .reverse, animated: true)
                } else if let page = parent.prevLastPage {
                    let vc = boundaryController(tag: -1, title: parent.prevChapterTitle, text: page)
                    pvc.setViewControllers([vc], direction: .reverse, animated: true)
                    DispatchQueue.main.async { self.parent.onPrevChapter() }
                }
            }
        }

        // MARK: DataSource

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            let current = vc.view.tag
            if current > 0 { return pageController(for: current - 1) }
            if let page = parent.prevLastPage {
                return boundaryController(tag: -1, title: parent.prevChapterTitle, text: page)
            }
            return nil
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            let current = vc.view.tag
            if current < parent.pages.count - 1 { return pageController(for: current + 1) }
            if let page = parent.nextFirstPage {
                return boundaryController(tag: -2, title: parent.nextChapterTitle, text: page)
            }
            return nil
        }

        // MARK: Delegate

        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed else { return }
            let tag = pvc.viewControllers?.first?.view.tag ?? -1
            if tag == -1 { DispatchQueue.main.async { self.parent.onPrevChapter() } }
            if tag == -2 { DispatchQueue.main.async { self.parent.onNextChapter() } }
        }

        // MARK: Helpers

        private func pageController(for index: Int) -> UIViewController? {
            guard parent.pages.indices.contains(index) else { return nil }
            return controller(tag: index, title: parent.chapterTitle, text: parent.pages[index])
        }

        private func boundaryController(tag: Int, title: String, text: String) -> UIViewController {
            controller(tag: tag, title: title, text: text)
        }

        private func controller(tag: Int, title: String, text: String) -> UIViewController {
            let vc = UIHostingController(rootView:
                PageContent(
                    chapterTitle: title,
                    text: text,
                    theme: parent.theme,
                    fontSize: parent.fontSize,
                    lineSpacing: parent.lineSpacing,
                    onTapCenter: parent.onTapCenter
                )
            )
            vc.view.backgroundColor = .clear
            vc.view.tag = tag
            return vc
        }
    }
}

/// 单页内容：顶部页眉（章名）+ 正文，底部留白撑满。
private struct PageContent: View {
    let chapterTitle: String
    let text: String
    let theme: ReadingTheme
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let onTapCenter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(chapterTitle)
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .padding(.top, 4)
            TextKitPageTextView(
                text: text,
                font: UIFont.systemFont(ofSize: fontSize),
                lineSpacing: lineSpacing,
                textColor: UIColor(theme.text)
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onTapCenter() }
    }
}

// MARK: - TextKit 正文渲染

/// 使用 TextKit（UILabel, TextKit 1）渲染正文，与 PageSplitter 的布局完全一致，
/// 确保翻页时文本首尾衔接。
private struct TextKitPageTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let lineSpacing: CGFloat
    let textColor: UIColor

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        uiView.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0 else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
        return CGSize(width: w, height: fit.height)
    }
}
