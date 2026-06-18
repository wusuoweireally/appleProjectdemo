import SwiftUI

/// 目录面板。当前章高亮并自动滚动定位，支持正序/倒序。
struct ReaderCatalogSheet: View {
    let chapters: [Chapter]
    let currentIndex: Int
    let onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reversed = false

    private var indices: [Int] {
        reversed ? Array((0..<chapters.count).reversed()) : Array(0..<chapters.count)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(indices, id: \.self) { idx in
                    row(for: idx)
                }
                .listStyle(.plain)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { proxy.scrollTo(currentIndex, anchor: .center) }
                    }
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { reversed.toggle() }
                    } label: {
                        Label(reversed ? "正序" : "倒序", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(for idx: Int) -> some View {
        let isCurrent = idx == currentIndex
        return Button {
            dismiss()
            onJump(idx)
        } label: {
            HStack(spacing: 10) {
                Text("\(idx + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                Text(chapters[idx].title)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color(hex: 0xFC5B26) : .primary)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Color(hex: 0xFC5B26).opacity(0.12) : Color.clear)
        .id(idx)
    }
}
