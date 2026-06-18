import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var vm: ReaderViewModel
    @EnvironmentObject private var settings: ReaderSettings
    @EnvironmentObject private var bookStore: BookStore
    @State private var toast = ""

    private var bookId: String { bookStore.currentBook?.id ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(LinearGradient(
                                colors: [Color(hex: 0xFC5B26), Color(hex: 0xFF8C42)],
                                startPoint: .top, endPoint: .bottom))
                            Image(systemName: "person.fill").foregroundColor(.white).font(.title2)
                        }
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("读客").font(.headline)
                            Text("已读至第 \(settings.lastChapter(for: bookId) + 1) 章")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("阅读统计") {
                    statRow("总章节", "\(vm.total)")
                    statRow("本书字数", wordCount)
                    statRow("当前进度", percent)
                }

                Section("主题") { themeRow }

                Section {
                    Button(role: .destructive) {
                        settings.setLastChapter(0, for: bookId)
                        bookStore.updateProgress(for: bookId, chapter: 0)
                        showToast("已清除阅读进度")
                    } label: {
                        Label("清除阅读进度", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("关于") {
                    LabeledContent("书名", value: bookStore.currentBook?.title ?? "—")
                    LabeledContent("版本", value: "1.0.0")
                }
            }
            .navigationTitle("我的")
        }
        .task {
            guard let book = bookStore.currentBook, vm.chapters.isEmpty else { return }
            vm.loadBook(book, settings: settings)
        }
        .overlay(alignment: .bottom) { toastView }
    }

    private var wordCount: String {
        let n = vm.chapters.reduce(0) { $0 + $1.content.count }
        return n >= 10000 ? String(format: "%.1f 万字", Double(n) / 10000) : "\(n) 字"
    }

    private var percent: String {
        guard vm.total > 0 else { return "—" }
        let ch = settings.lastChapter(for: bookId)
        return String(format: "%.0f%%", Double(ch + 1) / Double(vm.total) * 100)
    }

    private func statRow(_ key: String, _ value: String) -> some View {
        HStack { Text(key); Spacer(); Text(value).foregroundStyle(.secondary) }
    }

    private var themeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(ReadingTheme.allCases) { t in
                    Button { settings.readingTheme = t } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(t.background).frame(width: 38, height: 38)
                                if settings.readingTheme == t {
                                    Circle().stroke(Color(hex: 0xFC5B26), lineWidth: 3).frame(width: 38, height: 38)
                                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundColor(t.text)
                                }
                            }
                            Text(t.name).font(.caption2).foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var toastView: some View {
        Group {
            if !toast.isEmpty {
                Text(toast).font(.caption)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.8), in: Capsule())
                    .foregroundColor(.white).padding(.bottom, 30)
            }
        }
        .animation(.easeInOut, value: toast)
    }

    private func showToast(_ msg: String) {
        toast = msg
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); toast = "" }
    }
}
