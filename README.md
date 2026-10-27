# ReadEasy

简洁、美观、快捷的 macOS Markdown 阅读器。原生 AppKit / SwiftUI 外壳 + WKWebView 渲染，所有渲染库都打包在应用内，离线可用。

- 只读不改：专注阅读，文件在其他编辑器里保存后自动刷新
- macOS 原生风格：苹方 + SF Mono、系统强调色、毛玻璃侧栏，浅色 / 深色跟随系统
- 打开即用：单文件双击打开，或整个文件夹带侧边栏浏览，多个文件合并为系统标签页

## 功能

| 类别 | 说明 |
| --- | --- |
| 打开方式 | Finder 双击 / 右键「打开方式」/ 拖到窗口或 Dock 图标；可打开单个文件或整个文件夹 |
| 文件夹模式 | 左侧文件树（只列出含 Markdown 的目录），默认打开 README；文件增删后自动刷新 |
| 标签页 | 新打开的文件进入当前窗口的标签页；已打开的文件直接切换过去 |
| 渲染 | GFM 表格、任务列表、脚注、删除线、自动链接；GitHub 提示块 `> [!NOTE]`；代码高亮（Xcode 配色）；KaTeX 公式（`$…$`、`$$…$$`、```` ```math ````）；Mermaid 图表；Front matter 折叠显示；内嵌 HTML |
| 图片预览 | 点击图片或 Mermaid 图表放大查看：拖动或双指滑动平移，捏合、⌘ 滚轮或 ⌘+ / ⌘- 缩放，双击在适合窗口和放大之间切换；矢量图放大不糊；文件刷新时预览跟着更新 |
| 大纲 | 右侧按标题生成目录，跟随阅读位置高亮，点击平滑跳转 |
| 链接 | 点击 `other.md` 在当前标签页打开，⌘ 点击在新标签页打开；`#锚点` 页内跳转；网页链接用默认浏览器打开 |
| 历史 | 后退 / 前进，并恢复到离开时的滚动位置 |
| 查找 | 文内查找，显示「当前 / 总数」，文件刷新后保留高亮 |
| 快速打开 | ⌘P 按文件名模糊搜索：文件夹模式搜索整个文件夹，单文件模式搜索同目录及最近打开 |
| 自动刷新 | 监听当前文件，兼容「写临时文件再改名」的保存方式，刷新时保持滚动位置 |
| 其他 | 代码块一键复制、字号缩放、用外部编辑器打开、在 Finder 中显示、拷贝文件路径、最近打开 |

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开文件 / 打开文件夹 | ⌘O / ⇧⌘O |
| 快速打开 | ⌘P |
| 文内查找 / 下一个 / 上一个 | ⌘F / ⌘G / ⇧⌘G |
| 后退 / 前进 | ⌘[ / ⌘] |
| 放大 / 缩小 / 实际大小 | ⌘+ / ⌘- / ⌘0 |
| 显示或隐藏大纲 | ⌥⌘O |
| 显示或隐藏边栏（文件夹模式） | ⌃⌘S |
| 用外部编辑器打开 | ⌘E |
| 在 Finder 中显示 / 拷贝文件路径 | ⇧⌘R / ⌥⌘C |
| 新建标签页 / 新建窗口 | ⌘T / ⌘N |
| 切换标签页 | ⌃⇥ / ⌃⇧⇥ |

查找栏里按 ↩ 跳到下一个、⇧↩ 跳到上一个、esc 关闭；快速打开面板里用 ↑ ↓ 选择、↩ 打开、esc 关闭；图片预览里 ⌘+ / ⌘- 缩放、⌘0 在适合窗口和实际大小之间切换、方向键平移、esc 或点击空白处关闭。

## 安装

需要 macOS 14 及以上、Swift 6 工具链（安装 Command Line Tools 即可，不需要 Xcode）。

```bash
git clone <仓库地址> md-readeasy && cd md-readeasy
make install
```

`make install` 会构建 Release 版、安装到 `/Applications/ReadEasy.app`，并向 LaunchServices 注册文档类型。之后：

- **右键打开**：在 Finder 中右键 `.md` / `.markdown` 文件或文件夹 →「打开方式」→ ReadEasy
- **设为默认**：应用菜单 →「设为默认 Markdown 阅读器」，之后双击 `.md` 文件直接用 ReadEasy 打开
- **外部编辑器**：⌘E 默认依次寻找 VS Code、Cursor、Zed、Typora、Sublime Text、BBEdit、Nova、CotEditor，找不到时用「文本编辑」；可在应用菜单「外部编辑器…」中手动指定

### 卸载

```bash
osascript -e 'tell application id "io.github.ruichen31.ReadEasy" to quit'
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/ReadEasy.app
rm -rf /Applications/ReadEasy.app
defaults delete io.github.ruichen31.ReadEasy
```

## 开发

| 命令 | 作用 |
| --- | --- |
| `make build` | 构建 Release 版到 `build/ReadEasy.app` |
| `make run` | 构建并运行 `build/ReadEasy.app` |
| `make install` | 构建并安装到 `/Applications`，同时删除 `build/` 中的副本 |
| `make icon` | 重新生成 `Resources/AppIcon.icns` |
| `make vendor` | 从 npm 重新拉取渲染依赖到 `Resources/web/vendor`（需要网络） |
| `make clean` | 删除 `.build/` 和 `build/` |

Debug 构建：`CONFIG=debug ./scripts/build-app.sh`。

> `build/ReadEasy.app` 存在时也会被系统注册，「打开方式」里会出现两个 ReadEasy。调试完运行 `make install` 或 `make clean` 即可恢复。

### 目录结构

```
Sources/ReadEasy/
  main.swift                  入口
  AppDelegate.swift           打开文件 / 文件夹、窗口与标签页管理、最近打开、默认应用设置
  MainMenu.swift              菜单栏与快捷键
  ReaderWindowController.swift  窗口：标题、代理图标、菜单动作
  ReaderModel.swift           单个窗口的状态：当前文档、文件夹、历史、查找、快速打开
  ReaderView.swift            SwiftUI 界面：侧边栏、文档区、大纲、查找栏、快速打开、欢迎页
  WebBridge.swift             WKWebView 与渲染页之间的双向通信
  FileSystem.swift            文件树扫描、单文件监听、目录监听（FSEvents）
  QuickOpen.swift             快速打开的模糊匹配
  Support.swift               偏好设置、文本编码、外部编辑器
  DebugHooks.swift            仅 Debug：自动化验证钩子
Resources/
  Info.plist                  文档类型声明（决定「打开方式」）
  AppIcon.icns                应用图标（scripts/make-icon.swift 生成）
  zh-Hans.lproj/              中文本地化，系统菜单项显示为中文
  web/index.html              渲染页
  web/reader.css              阅读样式
  web/reader.js               Markdown 渲染、大纲、查找、链接处理
  web/vendor/                 第三方渲染库
scripts/
  build-app.sh                编译并组装 .app，--install 时安装并注册
  make-icon.swift             绘制图标
  vendor.sh                   更新第三方渲染库
```

### 实现要点

- **渲染**：每个窗口常驻一个 WKWebView，只加载一次 `index.html`。切换文件时原生层读取文本，通过 `callAsyncJavaScript` 交给 `ReadEasy.render()`，页面内用 markdown-it 渲染后整体替换内容，不重新加载页面，所以切换文件很快。
- **相对路径**：渲染前把页面的 `<base>` 设为当前文件所在目录，图片和链接按 Markdown 原文的相对路径解析。
- **Mermaid 按需加载**：Mermaid 体积约 2.7MB，只在文档里出现 ```` ```mermaid ```` 时才加载；渲染结果按「源码 + 主题」缓存，自动刷新时不会闪烁。
- **自动刷新**：用 `DispatchSource` 监听文件描述符；文件被删除或改名（原子保存）时重新打开描述符。连续事件合并为一次刷新，内容没变就跳过。
- **安全**：页面设置了 CSP，Markdown 里内嵌的脚本和 `on*` 事件不会执行；指向可执行文件的本地链接只在 Finder 中显示，不直接运行。
- **图片预览**：在页面内叠一层预览，Mermaid 图表复制一份 SVG 节点，图片用同一地址新建 `<img>`；缩放时直接改元素的宽高而不是 CSS `scale`，矢量图在任意倍率下都按实际尺寸重绘。预览打开时页面会告诉原生层，菜单里的缩放快捷键和 esc 就改为作用于预览。
- **滚动位置**：页面在滚动停下后上报位置，原生层缓存，用于后退 / 前进恢复，以及网页进程意外退出后的重新渲染。

### 自动化验证

Debug 构建会监听分布式通知 `ReadEasy.debug`，`userInfo` 为 `action`、`arg`、`out`，可以在没有屏幕录制权限的环境下驱动应用并截图。常用 action：

| action | 说明 |
| --- | --- |
| `open` / `navigate` | 打开路径 / 在当前窗口跳转到文件 |
| `back` / `forward` / `outline` / `sidebar` / `quickOpen` / `zoomIn` / `newTab` | 对应菜单操作 |
| `find` | 打开查找栏并搜索 `arg` |
| `js` | 在页面中执行 `arg`，结果写入 `out` |
| `state` | 把窗口状态（标题、当前文件、标题列表、查找结果、标签页等）以 JSON 写入 `out` |
| `menus` | 把菜单结构写入 `out` |
| `snapshot` | 截取当前窗口保存到 `arg`（PNG） |
| `appearance` | `light` / `dark` / 其他值跟随系统 |
| `clearRecents` | 清空最近打开 |

## 第三方依赖

| 库 | 版本 | 许可 |
| --- | --- | --- |
| [markdown-it](https://github.com/markdown-it/markdown-it) | 15.0.3 | MIT |
| [markdown-it-footnote](https://github.com/markdown-it/markdown-it-footnote) | 4.0.0 | MIT |
| [markdown-it-texmath](https://github.com/goessner/markdown-it-texmath) | 1.0.0 | MIT |
| [highlight.js](https://highlightjs.org) | 11.11.1 | BSD-3-Clause |
| [KaTeX](https://katex.org) | 0.16.25 | MIT |
| [Mermaid](https://mermaid.js.org) | 11.12.1 | MIT |
