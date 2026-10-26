import AppKit
import Observation
import SwiftUI

struct Heading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

struct FindStatus: Equatable {
    var current = 0
    var total = 0
}

private struct HistoryEntry {
    let url: URL
    let scrollY: Double
}

/// 一个窗口（标签页）的全部状态：可能是单个文件，也可能是一个文件夹。
@MainActor
@Observable
final class ReaderModel {
    // 文件夹模式
    private(set) var rootFolder: URL?
    private(set) var tree: [FileNode] = []
    private(set) var folderFiles: [URL] = []
    private(set) var isScanning = false
    var expanded: Set<String> = []
    var columnVisibility: NavigationSplitViewVisibility = .all

    // 当前文档
    private(set) var currentFile: URL?
    private(set) var loadError: String?
    var headings: [Heading] = []
    var activeHeading: String?
    var showOutline = Preferences.showOutline {
        didSet { Preferences.showOutline = showOutline }
    }

    // 查找
    var findVisible = false
    var findQuery = "" {
        didSet { if findQuery != oldValue { runFind(backwards: false) } }
    }
    var findStatus = FindStatus()
    private(set) var findFocusRequest = 0

    // 快速打开
    var quickOpenVisible = false
    private(set) var quickOpenItems: [QuickOpenItem] = []

    // 后退 / 前进
    private var backStack: [HistoryEntry] = []
    private var forwardStack: [HistoryEntry] = []
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    @ObservationIgnored let web = WebBridge()
    /// 当前文档或文件夹变化时通知窗口更新标题
    @ObservationIgnored var onDocumentChange: (() -> Void)?
    /// 交给 App 层打开（新标签页、拖入的文件等）
    @ObservationIgnored var openElsewhere: ((URL) -> Void)?
    @ObservationIgnored private var fileWatcher: FileWatcher?
    @ObservationIgnored private var folderMonitor: DirectoryMonitor?
    @ObservationIgnored private var renderedText: String?
    @ObservationIgnored private var reloadWork: DispatchWorkItem?

    var isEmpty: Bool { rootFolder == nil && currentFile == nil }

    init() {
        web.model = self
    }

    func teardown() {
        fileWatcher = nil
        folderMonitor = nil
        reloadWork?.cancel()
    }

    // MARK: 打开

    func load(_ url: URL) {
        if url.isDirectory { openFolder(url) } else { navigate(to: url) }
    }

    func openDropped(_ urls: [URL]) {
        for url in urls { openElsewhere?(url) }
    }

    private func openFolder(_ url: URL) {
        rootFolder = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        folderMonitor = DirectoryMonitor(url: url) { [weak self] in self?.rescanFolder() }
        rescanFolder { [weak self] in
            guard let self, self.currentFile == nil, let doc = self.defaultDocument() else { return }
            self.navigate(to: doc)
        }
        onDocumentChange?()
    }

    private func rescanFolder(then completion: (() -> Void)? = nil) {
        guard let root = rootFolder else { return }
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { FileTree.scan(root) }.value
            guard rootFolder == root else { return }
            tree = result.nodes
            folderFiles = result.files
            isScanning = false
            completion?()
        }
    }

    /// 打开文件夹时默认显示的文档：README > index > 第一个顶层文档
    private func defaultDocument() -> URL? {
        let topLevel = tree.filter { !$0.isDirectory }.map(\.url)
        for name in ["readme.md", "readme.markdown", "index.md"] {
            if let url = topLevel.first(where: { $0.lastPathComponent.lowercased() == name }) { return url }
        }
        return topLevel.first
    }

    // MARK: 导航

    func navigate(to url: URL, anchor: String? = nil) {
        let url = url.normalized
        if url.path == currentFile?.path {
            if let anchor { web.scrollTo(anchor) }
            return
        }
        if let current = currentFile {
            backStack.append(HistoryEntry(url: current, scrollY: web.scrollY))
            forwardStack.removeAll()
        }
        show(url, anchor: anchor, scrollY: 0)
    }

    func goBack() {
        guard let entry = backStack.popLast() else { return }
        if let current = currentFile {
            forwardStack.append(HistoryEntry(url: current, scrollY: web.scrollY))
        }
        show(entry.url, anchor: nil, scrollY: entry.scrollY)
    }

    func goForward() {
        guard let entry = forwardStack.popLast() else { return }
        if let current = currentFile {
            backStack.append(HistoryEntry(url: current, scrollY: web.scrollY))
        }
        show(entry.url, anchor: nil, scrollY: entry.scrollY)
    }

    private func show(_ url: URL, anchor: String?, scrollY: Double) {
        currentFile = url
        headings = []
        activeHeading = nil
        renderedText = nil
        revealInSidebar(url)
        fileWatcher = FileWatcher(url: url) { [weak self] in self?.scheduleReload() }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        render(anchor: anchor, scrollY: scrollY, keepScroll: false)
        onDocumentChange?()
    }

    private func render(anchor: String?, scrollY: Double, keepScroll: Bool) {
        guard let url = currentFile else { return }
        guard let text = TextLoader.read(url) else {
            loadError = FileManager.default.fileExists(atPath: url.path) ? "无法读取这个文件" : "文件已被移动或删除"
            return
        }
        loadError = nil
        if keepScroll, text == renderedText { return }
        renderedText = text
        web.render(markdown: text, fileURL: url, anchor: anchor, scrollY: scrollY, keepScroll: keepScroll)
    }

    /// 外部编辑器保存时可能连续触发多次事件，合并成一次刷新
    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.render(anchor: nil, scrollY: 0, keepScroll: true)
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// 网页进程重启后页面是全新的，按上次记录的位置重新渲染
    func rerender() {
        renderedText = nil
        render(anchor: nil, scrollY: web.scrollY, keepScroll: false)
    }

    private func revealInSidebar(_ url: URL) {
        guard let root = rootFolder?.path else { return }
        var dir = url.deletingLastPathComponent().path
        while dir.count > root.count, dir.hasPrefix(root + "/") {
            expanded.insert(dir)
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    func toggleSidebar() {
        guard rootFolder != nil else { return }
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    // MARK: 链接

    func handleLink(_ href: String, newTab: Bool) {
        guard let url = URL(string: href) else { return }
        switch url.scheme?.lowercased() {
        case "file":
            let target = URL(fileURLWithPath: url.path).normalized
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
                NSSound.beep()
                return
            }
            if isDir.boolValue {
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } else if MarkdownFiles.isMarkdown(target) {
                if newTab {
                    openElsewhere?(target)
                } else {
                    navigate(to: target, anchor: url.fragment?.removingPercentEncoding)
                }
            } else {
                let values = try? target.resourceValues(forKeys: [.isApplicationKey, .isExecutableKey])
                // 链接指向可执行文件时只在 Finder 中显示，避免点一下就运行
                if values?.isApplication == true || values?.isExecutable == true {
                    NSWorkspace.shared.activateFileViewerSelecting([target])
                } else {
                    NSWorkspace.shared.open(target)
                }
            }
        case "http", "https", "mailto":
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    // MARK: 查找

    func showFind() {
        let wasVisible = findVisible
        findVisible = true
        findFocusRequest += 1
        if !wasVisible, !findQuery.isEmpty { runFind(backwards: false) }
    }

    func hideFind() {
        findVisible = false
        findStatus = FindStatus()
        web.findClear()
    }

    func findStep(backwards: Bool) {
        guard findVisible, !findQuery.isEmpty else {
            showFind()
            return
        }
        runFind(backwards: backwards)
    }

    func runFind(backwards: Bool) {
        let query = findQuery
        Task {
            let status = await web.find(query, backwards: backwards)
            if query == findQuery { findStatus = status }
        }
    }

    // MARK: 快速打开

    func toggleQuickOpen() {
        if quickOpenVisible {
            quickOpenVisible = false
            return
        }
        quickOpenVisible = true
        if let root = rootFolder {
            quickOpenItems = QuickOpen.items(for: folderFiles, base: root)
            return
        }
        // 单文件模式：当前文件所在目录（浅层扫描）+ 最近打开的文档
        let dir = currentFile?.deletingLastPathComponent()
        let recents = NSDocumentController.shared.recentDocumentURLs.filter(MarkdownFiles.isMarkdown)
        quickOpenItems = QuickOpen.items(for: recents, base: dir)
        guard let dir else { return }
        Task {
            let nearby = await Task.detached(priority: .userInitiated) { FileTree.scan(dir, maxDepth: 3, limit: 4000).files }.value
            if quickOpenVisible { quickOpenItems = QuickOpen.items(for: recents + nearby, base: dir) }
        }
    }

    func openFromQuickOpen(_ item: QuickOpenItem) {
        quickOpenVisible = false
        navigate(to: item.url)
    }
}
