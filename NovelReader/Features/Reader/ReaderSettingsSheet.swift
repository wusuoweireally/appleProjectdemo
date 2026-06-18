import SwiftUI
import UIKit

/// 阅读设置：翻页方式、亮度、字号、行距、背景主题、角色名替换。
struct ReaderSettingsSheet: View {
    @EnvironmentObject private var settings: ReaderSettings
    @Binding var brightnessOverride: Double?
    @Environment(\.dismiss) private var dismiss

    @AppStorage("pageMode") private var pageMode = "scroll"
    @AppStorage("nameFrom") private var nameFrom = "陈晓"
    @AppStorage("nameTo")   private var nameTo = ""

    private var theme: ReadingTheme { settings.readingTheme }

    var body: some View {
        NavigationStack {
            Form {
                Section("翻页方式") {
                    Picker("翻页方式", selection: $pageMode) {
                        Text("上下滚动").tag("scroll")
                        Text("左右翻页").tag("paged")
                    }
                    .pickerStyle(.segmented)
                    if pageMode == "scroll" {
                        Toggle("无缝滚动（跨章节连续）", isOn: $settings.seamlessScroll)
                    }
                }

                Section("亮度") { brightnessRow }

                Section("排版") {
                    Stepper(value: $settings.fontSize, in: 12...32) {
                        HStack {
                            Text("字号")
                            Spacer()
                            Text("\(Int(settings.fontSize))").foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color(hex: 0xFC5B26))

                    HStack {
                        Text("行距")
                        Spacer()
                        Text("\(Int(settings.lineSpacing))").foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.lineSpacing, in: 4...24, step: 1)
                        .tint(Color(hex: 0xFC5B26))
                }

                Section("背景") { themePicker }

                Section {
                    TextField("原角色名（默认主角）", text: $nameFrom)
                    TextField("替换为", text: $nameTo)
                } header: {
                    Text("角色名替换")
                } footer: {
                    Text("将全书该名字替换为新名，「替换为」留空则不替换。")
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var brightnessRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { brightnessOverride ?? Double(UIScreen.main.brightness) },
                set: { brightnessOverride = $0 }
            ), in: 0.3...1.0)
            .tint(Color(hex: 0xFC5B26))
            Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
        }
    }

    private var themePicker: some View {
        HStack(spacing: 0) {
            ForEach(ReadingTheme.allCases) { t in
                Button {
                    withAnimation { settings.readingTheme = t }
                } label: {
                    ZStack {
                        Circle()
                            .fill(t.background)
                            .frame(width: 46, height: 46)
                            .overlay(Circle().stroke(
                                theme == t ? Color(hex: 0xFC5B26) : .gray.opacity(0.3),
                                lineWidth: theme == t ? 3 : 1
                            ))
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        if t == theme {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundColor(t.text)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }
}
