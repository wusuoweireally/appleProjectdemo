import SwiftUI

@main
struct NovelReaderApp: App {
    @StateObject private var settings = ReaderSettings()
    @StateObject private var vm = ReaderViewModel()
    @StateObject private var bookStore = BookStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(vm)
                .environmentObject(bookStore)
                .tint(Color(hex: 0xFC5B26))
        }
    }
}

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            BookShelfView()
                .tabItem { Label("书架", systemImage: "books.vertical.fill") }
                .tag(0)
            ExploreView()
                .tabItem { Label("书城", systemImage: "square.grid.2x2.fill") }
                .tag(1)
            ProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(2)
        }
    }
}
