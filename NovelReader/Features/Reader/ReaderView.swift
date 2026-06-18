import SwiftUI
import UIKit

private struct ScrollAnchor: Hashable {
    let chapter: Int
    let block: Int
}

private struct ScrollBlock: Identifiable {
    let id: ScrollAnchor
    let text: String
}

private struct ScrollAnchorOffset: Equatable {
    let anchor: ScrollAnchor
    let minY: CGFloat
}

private struct ScrollAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [ScrollAnchorOffset] = []

    static func reduce(value: inout [ScrollAnchorOffset], nextValue: () -> [ScrollAnchorOffset]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ScrollJump: Equatable {
    let anchor: ScrollAnchor
    let animated: Bool
    let token: Int
}

private enum ChapterLanding {
    case top
    case saved
    case end
}

/// 小说阅读主体。
///
/// 交互要点：
/// - 两种翻页方式：上下滚动 / 左右翻页（设置里切换）。
/// - 正文两端对齐（justified），左右边距一致。
/// - 左右翻页模式下，左右各 56pt 边缘为翻页热区；滚动模式只响应正文滚动。
/// - 工具栏（顶栏 + 底栏 + 章节滑块）通过 safeAreaInset 插入，
///   显示时滚动模式自动避让，隐藏时全屏沉浸。
/// - 章节切换在同一个视图内完成（@State currentIndex），不向导航栈 push，
///   避免栈无限堆积；返回即回到书架。
struct ReaderView: View {
    @EnvironmentObject private var vm: ReaderViewModel
    @EnvironmentObject private var settings: ReaderSettings
    @EnvironmentObject private var bookStore: BookStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("pageMode") private var pageMode = "scroll"
    @AppStorage("nameFrom") private var nameFrom = "陈晓"
    @AppStorage("nameTo")   private var nameTo = ""

    @State private var chromeVisible = false
    @State private var showCatalog = false
    @State private var showSettings = false
    @State private var hideTask: Task<Void, Never>?
    @State private var visibleScrollAnchor: ScrollAnchor?
    @State private var pendingScrollAnchor: ScrollAnchor?
    @State private var scrollJump: ScrollJump?
    @State private var scrollJumpToken = 0
    @State private var activeScrollJumpToken = 0
    @State private var isProgrammaticScroll = false

    @State private var brightnessOverride: Double?
    @State private var systemBrightnessOnEnter: Double = 0.6

    // 翻页模式专用
    @State private var pagedPages: [String] = []
    @State private var pagedTargetPage: Int = 0
    @State private var pagedCurrentPage: Int = 0
    @State private var pageSize: CGSize = .zero
    @State private var lastSplitChapterId: Int = -1
    @State private var pageTurnToken = 0
    @State private var prevChapterTitle = ""
    @State private var prevLastPage: String?
    @State private var nextChapterTitle = ""
    @State private var nextFirstPage: String?
    @State private var chapterSliderValue: Double = 0
    @State private var isChapterSliderEditing = false

    private let autoHideDelay: TimeInterval = 6
    private let scrollSpaceName = "reader-scroll-space"
    private var theme: ReadingTheme { settings.readingTheme }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            if pageMode == "paged" {
                if vm.loadState == .loaded, let chapter = vm.currentChapter {
                    pagedReader(chapter: chapter)
                } else {
                    Color.clear
                }
            } else {
                scrollReader
            }

            if vm.loadState != .loaded || (pageMode == "paged" && !pagedContentReady) { statusOverlay }

            if pageMode == "paged", vm.loadState == .loaded, pagedContentReady, !chromeVisible { tapZones }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if chromeVisible { topBar } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if chromeVisible { bottomBar } }
        .statusBarHidden(!chromeVisible)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .background(SwipeBackEnabler())
        .task { await enterReader() }
        .onDisappear { leaveReader() }
        .sheet(isPresented: $showCatalog) {
            ReaderCatalogSheet(
                chapters: vm.chapters,
                currentIndex: vm.currentIndex,
                onJump: { idx in
                    jump(to: idx, landing: .top, animated: false)
                }
            )
            .environmentObject(settings)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(brightnessOverride: $brightnessOverride)
                .environmentObject(settings)
        }
        .onChange(of: brightnessOverride) { newValue in
            if let v = newValue { UIScreen.main.brightness = CGFloat(v) }
        }
        .task(id: pagedSplitID) {
            guard pageMode == "paged", let chapter = vm.currentChapter else { return }
            await splitCurrentChapter(chapter, size: pageSize)
        }
        .onChange(of: pageMode) { _ in restoreReadingPosition(animated: false) }
        .onChange(of: settings.seamlessScroll) { _ in restoreReadingPosition(animated: false) }
    }

    // MARK: - Scroll mode

    @ViewBuilder
    private var scrollReader: some View {
        if settings.seamlessScroll {
            seamlessScrollReader
        } else if let chapter = vm.currentChapter {
            chapterScrollReader(index: vm.currentIndex, chapter: chapter)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func chapterScrollReader(index: Int, chapter: Chapter) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    scrollChapterTitle(index: index, title: chapter.title)
                    scrollChapterBlocks(index: index, chapter: chapter)
                    chapterFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: scrollSpaceName)
            .onTapGesture { toggleChrome() }
            .onPreferenceChange(ScrollAnchorPreferenceKey.self) { handleScrollOffsets($0) }
            .task(id: pendingScrollAnchor) {
                await commitPendingScrollAnchor()
            }
            .task(id: scrollJump?.token) {
                guard let jump = scrollJump else { return }
                try? await Task.sleep(nanoseconds: 20_000_000)
                performScrollJump(jump, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private var seamlessScrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(vm.chapters.enumerated()), id: \.element.id) { index, chapter in
                        scrollChapterTitle(index: index, title: chapter.title)
                        scrollChapterBlocks(index: index, chapter: chapter)
                        Color.clear.frame(height: 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: scrollSpaceName)
            .onTapGesture { toggleChrome() }
            .onPreferenceChange(ScrollAnchorPreferenceKey.self) { handleScrollOffsets($0) }
            .task(id: pendingScrollAnchor) {
                await commitPendingScrollAnchor()
            }
            .task(id: scrollJump?.token) {
                guard let jump = scrollJump else { return }
                try? await Task.sleep(nanoseconds: 20_000_000)
                performScrollJump(jump, proxy: proxy)
            }
        }
    }

    // MARK: - Paged mode

    @ViewBuilder
    private func pagedReader(chapter: Chapter) -> some View {
        GeometryReader { geo in
            Group {
                if !pagedPages.isEmpty, lastSplitChapterId == chapter.id {
                    PagedReaderView(
                        chapterId: chapter.id,
                        chapterTitle: chapter.title,
                        pages: pagedPages,
                        targetPageIndex: pagedTargetPage,
                        prevLastPage: prevLastPage,
                        prevChapterTitle: prevChapterTitle,
                        nextFirstPage: nextFirstPage,
                        nextChapterTitle: nextChapterTitle,
                        theme: theme,
                        fontSize: settings.fontSize,
                        lineSpacing: settings.lineSpacing,
                        onTapCenter: toggleChrome,
                        pageTurnToken: pageTurnToken,
                        onPrevChapter: { prev() },
                        onNextChapter: { next() },
                        onPageChanged: { recordPagedPage($0) }
                    )
                } else {
                    Color.clear
                }
            }
            .onAppear { if pageSize != geo.size { pageSize = geo.size } }
            .onChange(of: geo.size) { if pageSize != $0 { pageSize = $0 } }
        }
        .ignoresSafeArea()
    }

    // MARK: - Body pieces

    /// 加载/失败时的居中提示，避免夜间主题下黑屏。
    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 12) {
            if case .failed(let msg) = vm.loadState {
                Text(msg).font(.subheadline)
            } else {
                ProgressView()
                Text("正在加载…").font(.subheadline)
            }
        }
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pagedContentReady: Bool {
        guard pageMode == "paged", let chapter = vm.currentChapter else { return false }
        return !pagedPages.isEmpty && lastSplitChapterId == chapter.id
    }

    private func scrollChapterTitle(index: Int, title: String) -> some View {
        let anchor = ScrollAnchor(chapter: index, block: 0)
        return Text(title)
            .font(.system(size: settings.fontSize + 6, weight: .bold))
            .foregroundColor(theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 22)
            .id(anchor)
            .background(scrollAnchorReader(anchor))
    }

    private func scrollChapterBlocks(index: Int, chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: settings.lineSpacing) {
            ForEach(scrollBlocks(for: chapter, index: index)) { block in
                scrollBlock(block)
            }
        }
    }

    @ViewBuilder
    private func scrollBlock(_ block: ScrollBlock) -> some View {
        if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Color.clear
                .frame(height: max(8, settings.fontSize * 0.6))
                .id(block.id)
                .background(scrollAnchorReader(block.id))
        } else {
            TextKitPageTextView(
                text: block.text,
                font: UIFont.systemFont(ofSize: settings.fontSize),
                lineSpacing: settings.lineSpacing,
                textColor: UIColor(theme.text)
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(block.id)
                .background(scrollAnchorReader(block.id))
        }
    }

    private func scrollAnchorReader(_ anchor: ScrollAnchor) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollAnchorPreferenceKey.self,
                value: [ScrollAnchorOffset(anchor: anchor, minY: geo.frame(in: .named(scrollSpaceName)).minY)]
            )
        }
    }

    private func scrollBlocks(for chapter: Chapter, index: Int) -> [ScrollBlock] {
        replacedNames(chapter.content)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .enumerated()
            .map { offset, text in
                ScrollBlock(id: ScrollAnchor(chapter: index, block: offset + 1), text: text)
            }
    }

    private var chapterFooter: some View {
        HStack {
            Button("上一章") { prev() }
                .disabled(!vm.canPrev).opacity(vm.canPrev ? 1 : 0.3)
                .foregroundColor(theme.text)
            Spacer()
            Text("\(vm.currentIndex + 1) / \(vm.total)")
                .font(.caption.monospacedDigit())
                .foregroundColor(theme.secondaryText)
            Spacer()
            Button(vm.canNext ? "下一章" : "全书完") { next() }
                .opacity(vm.canNext ? 1 : 0.3)
                .foregroundColor(theme.text)
        }
        .font(.subheadline.weight(.medium))
        .padding(.top, 60)
    }

    /// 左右窄边只服务左右翻页模式；上下滚动模式不响应边缘切章。
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .frame(width: 56)
                .onTapGesture {
                    pageTurnToken -= 1
                    rescheduleAutoHide()
                }
            Spacer(minLength: 0)
            Color.clear.contentShape(Rectangle())
                .frame(width: 56)
                .onTapGesture {
                    pageTurnToken += 1
                    rescheduleAutoHide()
                }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            chromeIcon("chevron.left") { dismiss() }
            Button(action: openCatalog) {
                Text(vm.currentChapter?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
            }
            chromeIcon("list.bullet") { openCatalog() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var bottomBar: some View {
        let maxIndex = max(vm.total - 1, 0)
        let sliderMax = Double(max(maxIndex, 1))
        let sliderIndex = min(max(Int((isChapterSliderEditing ? chapterSliderValue : Double(vm.currentIndex)).rounded()), 0), maxIndex)

        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    chromeIcon("chevron.backward", disabled: !vm.canPrev) { prev() }
                    Slider(value: Binding(
                        get: { isChapterSliderEditing ? chapterSliderValue : Double(vm.currentIndex) },
                        set: { chapterSliderValue = min(max($0, 0), sliderMax) }
                    ), in: 0...sliderMax, step: 1, onEditingChanged: { editing in
                        if editing {
                            chapterSliderValue = Double(vm.currentIndex)
                            isChapterSliderEditing = true
                        } else {
                            isChapterSliderEditing = false
                            let target = min(max(Int(chapterSliderValue.rounded()), 0), maxIndex)
                            jump(to: target, landing: .top, animated: false)
                        }
                    })
                    .tint(Color(hex: 0xFC5B26))
                    chromeIcon("chevron.forward", disabled: !vm.canNext) { next() }
                }
                Text("\(sliderIndex + 1) / \(max(vm.total, 1))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().opacity(0.3)

            HStack(spacing: 0) {
                barItem("目录", "list.bullet", action: openCatalog)
                barItem(theme.isDark ? "白天" : "夜间", theme.isDark ? "sun.max" : "moon", action: toggleTheme)
                barItem("设置", "textformat") { showSettings = true }
            }
            .padding(.bottom, 6)
        }
        .background(.regularMaterial)
    }

    private func chromeIcon(_ systemName: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 32, height: 32)
                .foregroundColor(.primary)
                .opacity(disabled ? 0.3 : 1)
        }
        .disabled(disabled)
    }

    private func barItem(_ title: String, _ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName).font(.body)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
        }
    }

    // MARK: - Actions

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
        if chromeVisible { rescheduleAutoHide() } else { hideTask?.cancel() }
    }

    private func openCatalog() {
        hideTask?.cancel()
        showCatalog = true
    }

    private func prev() {
        guard vm.canPrev else { return }
        jump(to: vm.currentIndex - 1, landing: pageMode == "paged" ? .end : .top, animated: true)
    }

    private func next() {
        guard vm.canNext else { return }
        jump(to: vm.currentIndex + 1, landing: .top, animated: true)
    }

    private func toggleTheme() {
        withAnimation { settings.readingTheme = theme.isDark ? .paper : .night }
        rescheduleAutoHide()
    }

    private func jump(to index: Int, landing: ChapterLanding, animated: Bool) {
        guard vm.chapters.indices.contains(index) else { return }
        saveCurrentPosition()
        vm.jump(to: index)
        recordChapter(index)

        if pageMode == "paged" {
            pagedTargetPage = pageTarget(for: index, landing: landing)
        } else {
            requestScroll(to: scrollAnchor(for: index, landing: landing), animated: animated)
        }
        rescheduleAutoHide()
    }

    private func pageTarget(for index: Int, landing: ChapterLanding) -> Int {
        guard let bookId = bookStore.currentBook?.id else { return 0 }
        switch landing {
        case .top: return 0
        case .saved: return settings.lastPage(for: bookId, chapter: index)
        case .end: return -1
        }
    }

    private func scrollAnchor(for index: Int, landing: ChapterLanding) -> ScrollAnchor {
        guard let bookId = bookStore.currentBook?.id else {
            return ScrollAnchor(chapter: index, block: 0)
        }
        switch landing {
        case .top:
            return ScrollAnchor(chapter: index, block: 0)
        case .saved:
            let saved = settings.lastScrollBlock(for: bookId, chapter: index)
            return ScrollAnchor(chapter: index, block: min(saved, lastBlockIndex(for: index)))
        case .end:
            return ScrollAnchor(chapter: index, block: lastBlockIndex(for: index))
        }
    }

    private func lastBlockIndex(for index: Int) -> Int {
        guard vm.chapters.indices.contains(index) else { return 0 }
        let text = replacedNames(vm.chapters[index].content).replacingOccurrences(of: "\r\n", with: "\n")
        return max(0, text.components(separatedBy: "\n").count)
    }

    private func requestScroll(to anchor: ScrollAnchor, animated: Bool) {
        scrollJumpToken &+= 1
        pendingScrollAnchor = nil
        isProgrammaticScroll = true
        visibleScrollAnchor = anchor
        scrollJump = ScrollJump(anchor: anchor, animated: animated, token: scrollJumpToken)
        recordScrollAnchor(anchor)
        let token = scrollJumpToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if scrollJumpToken == token { isProgrammaticScroll = false }
        }
    }

    private func performScrollJump(_ jump: ScrollJump, proxy: ScrollViewProxy) {
        activeScrollJumpToken = jump.token
        isProgrammaticScroll = true
        if jump.animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(jump.anchor, anchor: .top)
            }
        } else {
            proxy.scrollTo(jump.anchor, anchor: .top)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            if activeScrollJumpToken == jump.token { isProgrammaticScroll = false }
        }
    }

    private func handleScrollOffsets(_ offsets: [ScrollAnchorOffset]) {
        guard !isProgrammaticScroll, !offsets.isEmpty else { return }
        let visibleTop: CGFloat = 72
        let anchor = offsets
            .filter { $0.minY <= visibleTop }
            .max { $0.minY < $1.minY }?
            .anchor
            ?? offsets.min { abs($0.minY - visibleTop) < abs($1.minY - visibleTop) }?.anchor

        guard let anchor, vm.chapters.indices.contains(anchor.chapter), anchor != visibleScrollAnchor else { return }
        visibleScrollAnchor = anchor
        pendingScrollAnchor = anchor
    }

    private func commitPendingScrollAnchor() async {
        guard let anchor = pendingScrollAnchor else { return }
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard pendingScrollAnchor == anchor else { return }
        recordScrollAnchor(anchor)
        if settings.seamlessScroll, anchor.chapter != vm.currentIndex {
            vm.jump(to: anchor.chapter)
        }
    }

    private func recordChapter(_ index: Int) {
        guard let bookId = bookStore.currentBook?.id else { return }
        settings.setLastChapter(index, for: bookId)
        bookStore.updateProgress(for: bookId, chapter: index)
    }

    private func recordScrollAnchor(_ anchor: ScrollAnchor) {
        guard let bookId = bookStore.currentBook?.id else { return }
        settings.setLastChapter(anchor.chapter, for: bookId)
        settings.setLastScrollBlock(anchor.block, for: bookId, chapter: anchor.chapter)
        bookStore.updateProgress(for: bookId, chapter: anchor.chapter)
    }

    private func recordPagedPage(_ page: Int) {
        pagedCurrentPage = page
        guard let bookId = bookStore.currentBook?.id else { return }
        settings.setLastChapter(vm.currentIndex, for: bookId)
        settings.setLastPage(page, for: bookId, chapter: vm.currentIndex)
        bookStore.updateProgress(for: bookId, chapter: vm.currentIndex)
    }

    private func saveCurrentPosition() {
        guard let bookId = bookStore.currentBook?.id else { return }
        if pageMode == "paged" {
            settings.setLastChapter(vm.currentIndex, for: bookId)
            settings.setLastPage(pagedCurrentPage, for: bookId, chapter: vm.currentIndex)
            bookStore.updateProgress(for: bookId, chapter: vm.currentIndex)
        } else if let anchor = visibleScrollAnchor, vm.chapters.indices.contains(anchor.chapter) {
            recordScrollAnchor(anchor)
        } else {
            recordChapter(vm.currentIndex)
        }
    }

    private func restoreReadingPosition(animated: Bool) {
        guard vm.loadState == .loaded, vm.chapters.indices.contains(vm.currentIndex) else { return }
        if pageMode == "paged" {
            pagedTargetPage = pageTarget(for: vm.currentIndex, landing: .saved)
        } else {
            requestScroll(to: scrollAnchor(for: vm.currentIndex, landing: .saved), animated: animated)
        }
    }

    private var pagedSplitID: String {
        "\(vm.currentIndex)-\(settings.fontSize)-\(settings.lineSpacing)-\(Int(pageSize.width))-\(Int(pageSize.height))-\(pageMode)-\(nameFrom)-\(nameTo)"
    }

    private func splitCurrentChapter(_ chapter: Chapter, size: CGSize) async {
        guard size.width > 50, size.height > 50 else { return }
        let text = replacedNames(chapter.content)
        let font = UIFont.systemFont(ofSize: settings.fontSize)
        let lineSpacing = settings.lineSpacing
        let inset = UIEdgeInsets(top: 56, left: 20, bottom: 32, right: 20)
        let chapterId = chapter.id
        let currentIndex = vm.currentIndex
        let prevCh = vm.chapters.indices.contains(currentIndex - 1) ? vm.chapters[currentIndex - 1] : nil
        let nextCh = vm.chapters.indices.contains(currentIndex + 1) ? vm.chapters[currentIndex + 1] : nil
        let sameChapter = chapterId == lastSplitChapterId
        let requestedPage = sameChapter ? pagedCurrentPage : pagedTargetPage
        let chunk = await Task.detached(priority: .userInitiated) {
            let curr = PageSplitter.split(text, font: font, lineSpacing: lineSpacing, pageSize: size, contentInset: inset)
            var prev: [String] = []
            var next: [String] = []
            if let pc = prevCh {
                prev = PageSplitter.split(replacedNames(pc.content), font: font, lineSpacing: lineSpacing, pageSize: size, contentInset: inset)
            }
            if let nc = nextCh {
                next = PageSplitter.split(replacedNames(nc.content), font: font, lineSpacing: lineSpacing, pageSize: size, contentInset: inset)
            }
            return (curr, prevCh?.title, prev.last, nextCh?.title, next.first)
        }.value
        await MainActor.run {
            lastSplitChapterId = chapterId
            let maxPage = max(0, chunk.0.count - 1)
            let targetPage = requestedPage < 0 ? maxPage : min(max(0, requestedPage), maxPage)
            pagedTargetPage = targetPage
            pagedCurrentPage = targetPage
            pagedPages = chunk.0
            prevChapterTitle = chunk.1 ?? ""
            prevLastPage = chunk.2
            nextChapterTitle = chunk.3 ?? ""
            nextFirstPage = chunk.4
        }
    }

    private func rescheduleAutoHide() {
        hideTask?.cancel()
        let delay = autoHideDelay
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) { chromeVisible = false }
            }
        }
    }

    // MARK: - Lifecycle

    private func enterReader() async {
        systemBrightnessOnEnter = Double(UIScreen.main.brightness)
        guard let book = bookStore.currentBook else { return }
        if vm.currentBookId != book.id || vm.chapters.isEmpty {
            vm.loadBook(book, settings: settings)
        }
        for _ in 0..<50 where vm.loadState == .loading {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        restoreReadingPosition(animated: false)
    }

    private func leaveReader() {
        hideTask?.cancel()
        saveCurrentPosition()
        if brightnessOverride != nil {
            UIScreen.main.brightness = CGFloat(systemBrightnessOnEnter)
        }
    }
}

// MARK: - 手势返回

/// 隐藏导航栏后系统边缘右滑返回会失效，这里强制恢复
/// `interactivePopGestureRecognizer`：仅当导航栈深度 > 1 时允许触发，
/// 既支持阅读器右滑退出，又避免根视图（书架）被 pop。
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = SwipeBackHost()
        vc.coordinator = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var nav: UINavigationController?
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (nav?.viewControllers.count ?? 0) > 1
        }
    }

    final class SwipeBackHost: UIViewController {
        var coordinator: Coordinator?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController, let coordinator else { return }
            coordinator.nav = nav
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = coordinator
        }
    }
}
