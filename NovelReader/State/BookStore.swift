import SwiftUI

@MainActor
final class BookStore: ObservableObject {
    @Published var books: [Book] = []

    private let defaults = UserDefaults.standard
    private let booksKey = "savedBooks"
    private let currentBookIdKey = "currentBookId"
    private let dataVersionKey = "bookStoreDataVersion"
    private let currentDataVersion = 1

    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var currentBook: Book? {
        get {
            let id = defaults.string(forKey: currentBookIdKey)
            return books.first { $0.id == id } ?? books.first
        }
        set {
            defaults.set(newValue?.id, forKey: currentBookIdKey)
        }
    }

    init() {
        let savedVersion = defaults.integer(forKey: dataVersionKey)
        if savedVersion != currentDataVersion {
            defaults.removeObject(forKey: booksKey)
            defaults.removeObject(forKey: currentBookIdKey)
            defaults.set(currentDataVersion, forKey: dataVersionKey)
        }
        load()
        if books.isEmpty {
            books = [.builtIn]
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: booksKey),
              let decoded = try? JSONDecoder().decode([Book].self, from: data)
        else { return }
        books = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        defaults.set(data, forKey: booksKey)
    }

    // MARK: - Import

    func importBook(from url: URL) throws -> Book {
        let raw = try TextEncoding.readContent(from: url)
        let importDir = docsURL.appendingPathComponent("ImportedBooks", isDirectory: true)
        try FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)

        let uuid = UUID().uuidString
        let dest = importDir.appendingPathComponent("\(uuid).txt")
        try raw.write(to: dest, atomically: true, encoding: .utf8)

        let fileName = url.lastPathComponent
        let title = (fileName as NSString).deletingPathExtension
        let relPath = "ImportedBooks/\(uuid).txt"
        let book = Book.new(title: title, filePath: relPath, fileName: fileName)
        books.append(book)
        currentBook = book
        save()
        return book
    }

    // MARK: - Delete

    func delete(_ book: Book) {
        guard !book.isBuiltIn else { return }
        if let path = book.filePath {
            try? FileManager.default.removeItem(at: docsURL.appendingPathComponent(path))
        }
        books.removeAll { $0.id == book.id }
        save()
    }

    // MARK: - Update

    func updateProgress(for bookId: String, chapter: Int) {
        guard let idx = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[idx].lastChapter = chapter
        save()
    }

    func setCurrentBook(_ book: Book) {
        currentBook = book
    }

    // MARK: - URL helper

    func fileURL(for book: Book) -> URL? {
        if book.isBuiltIn {
            return Bundle.main.url(forResource: "novel", withExtension: "txt")
        }
        guard let path = book.filePath else { return nil }
        return docsURL.appendingPathComponent(path)
    }
}
