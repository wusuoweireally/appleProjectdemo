import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var vm: ReaderViewModel
    @EnvironmentObject private var settings: ReaderSettings
    @EnvironmentObject private var bookStore: BookStore
    @State private var toast = ""
    @State private var openReader = false

    private let banners: [(String, String, [Color])] = [
        ("限时免费", "夏日书单 精选畅读", [Color(hex: 0xFC5B26), Color(hex: 0xFF8C42)]),
        ("新书速递", "本周新书上架",   [Color(hex: 0x3A5AAB), Color(hex: 0x6FB1FC)]),
        ("读者热推", "万人评分 9.0+",  [Color(hex: 0x2E8B57), Color(hex: 0x66BB6A)]),
    ]
    private let categories = ["精选", "都市", "玄幻", "科幻", "悬疑", "言情", "历史", "武侠"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    bannerScroll
                    categoryChips
                    Text("为你推荐").font(.headline).padding(.horizontal, 16)
                    recommendGrid
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("书城")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $openReader) {
                ReaderView()
            }
        }
        .overlay(alignment: .bottom) { toastView }
    }

    private var bannerScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(banners.indices, id: \.self) { i in
                    let b = banners[i]
                    ZStack(alignment: .leading) {
                        LinearGradient(colors: b.2, startPoint: .leading, endPoint: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(b.0).font(.headline).foregroundColor(.white)
                            Text(b.1).font(.caption).foregroundColor(.white.opacity(0.9))
                        }
                        .padding(16)
                    }
                    .frame(width: 300, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.self) { c in
                    Text(c)
                        .font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.gray.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var recommendGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(bookStore.books) { book in
                Button {
                    bookStore.setCurrentBook(book)
                    vm.loadBook(book, settings: settings)
                    openReader = true
                } label: {
                    VStack(spacing: 6) {
                        BookCover(title: book.title, colors: book.colors)
                        Text(book.title).font(.caption.weight(.medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
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
