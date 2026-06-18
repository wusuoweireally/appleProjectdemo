import Foundation
import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published var currentIndex: Int = 0
    private(set) var currentBookId: String = ""

    var currentChapter: Chapter? {
        guard chapters.indices.contains(currentIndex) else { return nil }
        return chapters[currentIndex]
    }

    var canPrev: Bool { currentIndex > 0 }
    var canNext: Bool { currentIndex < chapters.count - 1 }
    var total: Int { chapters.count }

    func loadBook(_ book: Book, settings: ReaderSettings) {
        guard book.id != currentBookId || chapters.isEmpty else { return }
        currentBookId = book.id
        chapters = []
        currentIndex = 0
        loadState = .loading
        Task.detached(priority: .userInitiated) { [book] in
            let (chapters, error) = await Self.load(from: book)
            await MainActor.run {
                if let error {
                    self.loadState = .failed(error)
                } else {
                    self.chapters = chapters
                    self.loadState = .loaded
                    let saved = settings.lastChapter(for: book.id)
                    if chapters.indices.contains(saved) { self.currentIndex = saved }
                }
            }
        }
    }

    func jump(to index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentIndex = index
    }

    func move(_ delta: Int) {
        jump(to: currentIndex + delta)
    }

    private static func load(from book: Book) async -> (chapters: [Chapter], error: String?) {
        let url: URL?
        if book.isBuiltIn {
            url = Bundle.main.url(forResource: "novel", withExtension: "txt")
        } else if let path = book.filePath {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = docs.appendingPathComponent(path)
        } else {
            url = nil
        }
        guard let fileURL = url else {
            return ([], "找不到文件")
        }
        do {
            let raw = try TextEncoding.readContent(from: fileURL)
            let chapters = ChapterParser.parse(raw)
            return chapters.isEmpty
                ? ([], "未能解析出任何章节")
                : (chapters, nil)
        } catch {
            return ([], "读取失败：\(error.localizedDescription)")
        }
    }
}
