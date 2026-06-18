## 项目概述

NovelReader - SwiftUI iOS 阅读器 App，支持上下滚动和左右翻页两种阅读模式。

### 技术栈
- SwiftUI, UIKit (PageViewController)
- iOS 17+ (Debug) / 26.0 (Release)
- Xcode 17
- 无第三方依赖，纯 SwiftUI + 原生框架

### 项目结构

```
NovelReader/
├── NovelReaderApp.swift              # @main 入口，注入环境对象
├── Theme/
│   ├── Color+Hex.swift               # 颜色扩展
│   └── ReadingTheme.swift            # 5种阅读主题
├── State/
│   ├── ReaderSettings.swift          # 用户偏好持久化 (UserDefaults)
│   ├── ReaderViewModel.swift         # 章节加载/跳转状态
│   └── BookStore.swift               # 书籍管理 (导入/删除/进度)
├── Models/
│   ├── Chapter.swift                 # 章节模型 (id/title/content)
│   ├── Book.swift                    # 书籍模型 + 内置书
│   └── ChapterParser.swift           # 正则解析章节
├── Utils/
│   └── TextEncoding.swift            # 编码检测
├── Features/
│   ├── Shelf/
│   │   ├── BookShelfView.swift       # 书架 (继续阅读/导入)
│   │   ├── ExploreView.swift         # 书城
│   │   └── ProfileView.swift         # 我的 (进度/清除)
│   └── Reader/
│       ├── ReaderView.swift          # 阅读主视图 (滚动+翻页)
│       ├── PagedReaderView.swift     # 左右翻页容器
│       ├── PageSplitter.swift        # TextKit 分页引擎
│       ├── ReaderSettingsSheet.swift # 设置面板
│       └── ReaderCatalogSheet.swift  # 目录面板
└── Resources/
    ├── novel.txt                     # 内置小说文本
    └── Assets.xcassets
```

### 构建与部署

| 命令 | 说明 |
|------|------|
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project NovelReader.xcodeproj -scheme NovelReader -configuration Debug -destination 'generic/platform=iOS Simulator' build` | 构建模拟器版本 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project NovelReader.xcodeproj -scheme NovelReader -configuration Debug -destination 'id=00008140-000938D40243801C' -derivedDataPath /tmp/NovelReaderDeviceDerivedData build` | 构建真机版本 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 00008140-000938D40243801C /tmp/NovelReaderDeviceDerivedData/Build/Products/Debug-iphoneos/NovelReader.app` | 无线安装到 iPhone |

- **开发团队**: N9MNGZNT3J
- **Bundle ID**: com.demo.novelreader
- **签名**: Automatic (Apple Development: tu.zhitao@qq.com)
- **真机设备**: iPhone 16 Pro (00008140-000938D40243801C)
- **全局工具链**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（本机 xcode-select 指向 CommandLineTools，需要显式指定）

### 核心交互

- `ReaderView` 是阅读主视图，所有章节切换在当前视图内完成，不 push 导航栈
- 上下滚动模式：正文按换行拆块，通过 PreferenceKey 上报可见位置保存进度
- 左右翻页模式：TextKit 预分页，UIPageViewController 驱动，边界自动跨章
- 阅读位置持久化：章节号 + 页码(翻页) / 滚动块索引(滚动)，按 bookId 隔离
- 菜单显示时隐藏左右边缘热区，避免与滑块/按钮冲突

### 注意事项

- 代码已经通过 swiftc -parse 和 xcodebuild 验证
- iOS 26.0 有 UIScreen.main 废弃警告，不影响功能
- 不用 touch xcassets 或 pbxproj 除非有明确需要
