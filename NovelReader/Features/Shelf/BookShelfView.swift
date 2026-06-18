import SwiftUI
import UniformTypeIdentifiers

/// 统一的书籍封面：渐变底 + 书名。
struct BookCover: View {
    let title: String
    let colors: [Color]

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(8)
        }
        .frame(width: 92, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

struct BookShelfView: View {
    @EnvironmentObject private var vm: ReaderViewModel
    @EnvironmentObject private var settings: ReaderSettings
    @EnvironmentObject private var bookStore: BookStore
    @State private var openReader = false
    @State private var toast = ""
    @State private var showImporter = false
    @State private var deleteTarget: Book?
    @State private var openTarget: Book?

    private var current: Book? { bookStore.currentBook }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let book = current {
                        continueCard(for: book)
                    }
                    shelfGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $openReader) {
                ReaderView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText]) { result in
                handleImport(result)
            }
            .confirmationDialog("删除此书？", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let book = deleteTarget { bookStore.delete(book) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("文件副本将从 App 中移除。")
            }
        }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: - Continue Card

    private func continueCard(for book: Book) -> some View {
        let progressTitle: String = {
            let ch = settings.lastChapter(for: book.id)
            return ch == 0 ? "开始阅读 · \(book.title)" : "第 \(ch + 1) 章"
        }()

        return HStack(spacing: 14) {
            BookCover(title: book.title, colors: book.colors)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.title3.weight(.bold))
                Text("\(book.author) 著").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(progressTitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Button {
                    openTarget = book
                    openBook(book)
                } label: {
                    Label("继续阅读", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color(hex: 0xFC5B26), in: Capsule())
                        .foregroundColor(.white)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Shelf Grid

    private var shelfGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(bookStore.books) { book in
                Button {
                    openTarget = book
                    openBook(book)
                } label: {
                    VStack(spacing: 6) {
                        BookCover(title: book.title, colors: book.colors)
                        Text(book.title).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if !book.isBuiltIn {
                        Button(role: .destructive) {
                            deleteTarget = book
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openBook(_ book: Book) {
        bookStore.setCurrentBook(book)
        vm.loadBook(book, settings: settings)
        openReader = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let book = try bookStore.importBook(from: url)
                showToast("已导入：\(book.title)")
            } catch {
                showToast("导入失败：\(error.localizedDescription)")
            }
        case .failure(let error):
            showToast("导入失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Toast

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
