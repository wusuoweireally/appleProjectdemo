import Foundation

/// 一章正文。id 为全书顺序索引（0-based），用作稳定的持久化键。
struct Chapter: Identifiable, Equatable {
    let id: Int
    let title: String
    let content: String
}
