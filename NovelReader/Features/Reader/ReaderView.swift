import SwiftUI
import UIKit

/// 小说阅读主体。
///
/// 交互要点：
/// - 两种翻页方式：上下滚动 / 左右翻页（设置里切换）。
/// - 文字区可长按选词复制（textSelection）。
/// - 左右各 56pt 边缘为翻章热区；中间大片区域单击切换工具栏。
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
    @State private var scrollToTopToken = 0
    @State private var seamlessTopID: Int?
    @State private var seamlessJumpTarget: Int?
    @State private var pendingTopID: Int?
    @State private var isNavigatingViaJump = false

    @State private var brightnessOverride: Double?
    @State private var systemBrightnessOnEnter: Double = 0.6

    // 翻页模式专用
    @State private var pagedPages: [String] = []
    @State private var pagedTargetPage: Int = 0
    @State private var pageSize: CGSize = .zero
    @State private var lastSplitChapterId: Int = -1
    @State private var pageTurnToken = 0
    @State private var prevChapterTitle = ""
    @State private var prevLastPage: String?
    @State private var nextChapterTitle = ""
    @State private var nextFirstPage: String?

    private let autoHideDelay: TimeInterval = 6
    private var theme: ReadingTheme { settings.readingTheme }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            if pageMode == "paged", let chapter = vm.currentChapter {
                pagedReader(chapter: chapter)
            } else {
                scrollReader
            }

            tapZones
        }
        .safeAreaInset(edge: .top, spacing: 0) { if chromeVisible { topBar } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if chromeVisible { bottomBar } }
        .preferredColorScheme(theme.colorScheme)
        .statusBarHidden(!chromeVisible)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .task { await enterReader() }
        .onDisappear { leaveReader() }
        .sheet(isPresented: $showCatalog) {
            ReaderCatalogSheet(
                chapters: vm.chapters,
                currentIndex: vm.currentIndex,
                onJump: { idx in
                    vm.jump(to: idx)
                    settings.setLastChapter(idx, for: bookStore.currentBook?.id ?? "")
                    pagedTargetPage = 0
                    if settings.seamlessScroll { seamlessJumpTarget = idx }
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
    }

    // MARK: - Scroll mode

    @ViewBuilder
    private var scrollReader: some View {
        if settings.seamlessScroll {
            seamlessScrollReader
        } else {
            chapterScrollReader
        }
    }

    @ViewBuilder
    private var chapterScrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text(vm.currentChapter?.title ?? "")
                        .font(.system(size: settings.fontSize + 6, weight: .bold))
                        .foregroundColor(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 22)
                        .id("top")

                    Text(bodyText)
                        .font(.system(size: settings.fontSize))
                        .foregroundColor(theme.text)
                        .lineSpacing(settings.lineSpacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    chapterFooter
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 120)
            }
            .onTapGesture { toggleChrome() }
            .onChange(of: vm.currentIndex) { _ in bumpScrollToTop() }
            .onChange(of: scrollToTopToken) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private var seamlessScrollReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(vm.chapters.enumerated()), id: \.element.id) { index, chapter in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(chapter.title)
                                .font(.system(size: settings.fontSize + 6, weight: .bold))
                                .foregroundColor(theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 22)
                                .id(index)

                            Text(replacedNames(chapter.content))
                                .font(.system(size: settings.fontSize))
                                .foregroundColor(theme.text)
                                .lineSpacing(settings.lineSpacing)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.bottom, 40)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 120)
            }
            .scrollPosition(id: $seamlessTopID)
            .onTapGesture { toggleChrome() }
            .onChange(of: seamlessTopID) { newID in
                guard !isNavigatingViaJump else { return }
                pendingTopID = newID
            }
            .task(id: pendingTopID) {
                guard let idx = pendingTopID, idx != vm.currentIndex else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard pendingTopID == idx else { return }
                vm.jump(to: idx)
                settings.setLastChapter(idx, for: bookStore.currentBook?.id ?? "")
            }
            .onChange(of: seamlessJumpTarget) { target in
                guard let idx = target else { return }
                isNavigatingViaJump = true
                vm.jump(to: idx)
                settings.setLastChapter(idx, for: bookStore.currentBook?.id ?? "")
                proxy.scrollTo(idx, anchor: .top)
                seamlessJumpTarget = nil
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    isNavigatingViaJump = false
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                seamlessJumpTarget = vm.currentIndex
            }
        }
    }

    // MARK: - Paged mode

    @ViewBuilder
    private func pagedReader(chapter: Chapter) -> some View {
        GeometryReader { geo in
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
                onNextChapter: { next() }
            )
            .onAppear { if pageSize != geo.size { pageSize = geo.size } }
            .onChange(of: geo.size) { if pageSize != $0 { pageSize = $0 } }
        }
        .ignoresSafeArea()
    }

    // MARK: - Body pieces

    private var bodyText: String {
        switch vm.loadState {
        case .loading, .idle: return "正在加载…"
        case .failed(let m):  return m
        case .loaded:         return replacedNames(vm.currentChapter?.content ?? "")
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

    /// 左右窄边：翻页模式 → 翻页；无缝滚动 → 跳到上/下章开头；普通滚动 → 翻章。
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .frame(width: 56)
                .onTapGesture {
                    if pageMode == "paged" {
                        pageTurnToken -= 1
                        rescheduleAutoHide()
                    } else if settings.seamlessScroll {
                        let target = max(0, vm.currentIndex - 1)
                        seamlessJumpTarget = target
                        rescheduleAutoHide()
                    } else {
                        prev()
                    }
                }
            Spacer(minLength: 0)
            Color.clear.contentShape(Rectangle())
                .frame(width: 56)
                .onTapGesture {
                    if pageMode == "paged" {
                        pageTurnToken += 1
                        rescheduleAutoHide()
                    } else if settings.seamlessScroll {
                        let target = min(vm.total - 1, vm.currentIndex + 1)
                        seamlessJumpTarget = target
                        rescheduleAutoHide()
                    } else {
                        next()
                    }
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
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    chromeIcon("chevron.backward", disabled: !vm.canPrev) { prev() }
                    Slider(value: Binding(
                        get: { Double(vm.currentIndex) },
                        set: { vm.jump(to: Int($0.rounded())) }
                    ), in: 0...Double(max(vm.total - 1, 1)))
                    .tint(Color(hex: 0xFC5B26))
                    chromeIcon("chevron.forward", disabled: !vm.canNext) { next() }
                }
                Text("\(vm.currentIndex + 1) / \(vm.total)")
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
        vm.move(-1)
        settings.setLastChapter(vm.currentIndex, for: bookStore.currentBook?.id ?? "")
        pagedTargetPage = -1
        rescheduleAutoHide()
    }

    private func next() {
        guard vm.canNext else { return }
        vm.move(1)
        settings.setLastChapter(vm.currentIndex, for: bookStore.currentBook?.id ?? "")
        pagedTargetPage = 0
        rescheduleAutoHide()
    }

    private func toggleTheme() {
        withAnimation { settings.readingTheme = theme.isDark ? .paper : .night }
        rescheduleAutoHide()
    }

    private func bumpScrollToTop() { scrollToTopToken &+= 1 }

    private var pagedSplitID: String {
        "\(vm.currentIndex)-\(settings.fontSize)-\(settings.lineSpacing)-\(Int(pageSize.width))-\(Int(pageSize.height))-\(pageMode)-\(nameFrom)-\(nameTo)"
    }

    private func splitCurrentChapter(_ chapter: Chapter, size: CGSize) async {
        guard size.width > 50, size.height > 50 else { return }
        let text = replacedNames(chapter.content)
        let font = UIFont.systemFont(ofSize: settings.fontSize)
        let lineSpacing = settings.lineSpacing
        let inset = UIEdgeInsets(top: 56, left: 22, bottom: 32, right: 22)
        let chapterId = chapter.id
        let chunk = await Task.detached(priority: .userInitiated) {
            let curr = PageSplitter.split(text, font: font, lineSpacing: lineSpacing, pageSize: size, contentInset: inset)
            let prevCh = vm.chapters.indices.contains(vm.currentIndex - 1) ? vm.chapters[vm.currentIndex - 1] : nil
            let nextCh = vm.chapters.indices.contains(vm.currentIndex + 1) ? vm.chapters[vm.currentIndex + 1] : nil
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
            if chapterId != lastSplitChapterId {
                lastSplitChapterId = chapterId
            } else {
                pagedTargetPage = 0
            }
            if pagedTargetPage < 0 { pagedTargetPage = max(0, chunk.0.count - 1) }
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
        if vm.chapters.isEmpty { vm.loadBook(book, settings: settings) }
        for _ in 0..<50 where vm.loadState == .loading {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        pagedTargetPage = 0
    }

    private func leaveReader() {
        hideTask?.cancel()
        guard let bookId = bookStore.currentBook?.id else { return }
        settings.setLastChapter(vm.currentIndex, for: bookId)
        bookStore.updateProgress(for: bookId, chapter: vm.currentIndex)
        if brightnessOverride != nil {
            UIScreen.main.brightness = CGFloat(systemBrightnessOnEnter)
        }
    }
}
