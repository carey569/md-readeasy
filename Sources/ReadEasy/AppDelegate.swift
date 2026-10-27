import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    static private(set) var shared: AppDelegate!

    private var controllers: [ReaderWindowController] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: 生命周期

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.build(recentMenuDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugHooks.install()
        #endif
        // 双击文件启动时 application(_:open:) 会先于这里被调用，已有窗口就不再开欢迎页
        if controllers.isEmpty { newWindowAction(nil) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let host = currentController
        for url in urls { open(url, host: host) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindowAction(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: 窗口与标签页

    private var currentController: ReaderWindowController? {
        if let controller = (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? ReaderWindowController {
            return controller
        }
        return controllers.last { $0.window?.isVisible == true }
    }

    /// 打开文件或文件夹：已打开的直接切过去；当前是空白窗口就在里面打开；否则作为新标签页打开。
    func open(_ url: URL, host: ReaderWindowController? = nil) {
        let url = url.normalized
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            NSSound.beep()
            return
        }
        if !isDir.boolValue, !MarkdownFiles.isMarkdown(url) {
            NSWorkspace.shared.open(url)
            return
        }

        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        let existing = controllers.first { c in
            isDir.boolValue
                ? c.model.rootFolder?.path == url.path
                : c.model.rootFolder == nil && c.model.currentFile?.path == url.path
        }
        if let existing {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let host = host ?? currentController
        if let host, host.model.isEmpty {
            host.model.load(url)
            host.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = makeController()
        controller.model.load(url)
        present(controller, asTabOf: host)
    }

    func newTab(host: ReaderWindowController?) {
        present(makeController(), asTabOf: host ?? currentController)
    }

    func controllerDidClose(_ controller: ReaderWindowController) {
        controllers.removeAll { $0 === controller }
    }

    private func makeController() -> ReaderWindowController {
        let controller = ReaderWindowController()
        controllers.append(controller)
        return controller
    }

    private func present(_ controller: ReaderWindowController, asTabOf host: ReaderWindowController?) {
        guard let window = controller.window else { return }
        if let hostWindow = host?.window, hostWindow.isVisible, hostWindow !== window {
            hostWindow.addTabbedWindow(window, ordered: .above)
        } else {
            place(window)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func place(_ window: NSWindow) {
        if let other = controllers.last(where: { $0.window !== window && $0.window?.isVisible == true })?.window {
            window.setFrame(other.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: other.frame.minX, y: other.frame.maxY)))
        } else if let frame = Preferences.windowFrame {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
    }

    // MARK: 菜单动作

    @objc func newWindowAction(_ sender: Any?) {
        present(makeController(), asTabOf: nil)
    }

    @objc func newWindowForTab(_ sender: Any?) {
        newTab(host: currentController)
    }

    @objc func openFileAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MarkdownFiles.contentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "选择要阅读的 Markdown 文件"
        guard panel.runModal() == .OK else { return }
        let host = currentController
        panel.urls.forEach { open($0, host: host) }
    }

    @objc func openFolderAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "打开"
        panel.message = "选择一个包含 Markdown 文档的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    @objc func openRecentAction(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { open(url) }
    }

    /// 当前窗口正在预览图片时，缩放快捷键作用于预览图，而不是页面字号
    private var activeViewer: WebBridge? {
        guard let model = currentController?.model, model.viewerOpen else { return nil }
        return model.web
    }

    @objc func zoomInAction(_ sender: Any?) {
        if let viewer = activeViewer { return viewer.viewerZoom(1) }
        Preferences.zoom = Preferences.zoomSteps.first { $0 > Preferences.zoom + 0.001 } ?? Preferences.zoom
    }

    @objc func zoomOutAction(_ sender: Any?) {
        if let viewer = activeViewer { return viewer.viewerZoom(-1) }
        Preferences.zoom = Preferences.zoomSteps.last { $0 < Preferences.zoom - 0.001 } ?? Preferences.zoom
    }

    @objc func zoomResetAction(_ sender: Any?) {
        if let viewer = activeViewer { return viewer.viewerZoom(0) }
        Preferences.zoom = 1
    }

    @objc func chooseEditorAction(_ sender: Any?) {
        ExternalEditor.choose()
    }

    private var markdownType: UTType? { UTType("net.daringfireball.markdown") }

    private var isDefaultReader: Bool {
        guard let type = markdownType,
              let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return app.normalized.path == Bundle.main.bundleURL.normalized.path
    }

    @objc func setDefaultReaderAction(_ sender: Any?) {
        guard let type = markdownType else { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error {
                    alert.alertStyle = .warning
                    alert.messageText = "设置失败"
                    alert.informativeText = error.localizedDescription
                } else {
                    alert.messageText = "已将 ReadEasy 设为 Markdown 文件的默认打开方式"
                    alert.informativeText = "在 Finder 中双击 .md 文件会直接用 ReadEasy 打开。"
                }
                alert.runModal()
            }
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setDefaultReaderAction(_:)):
            item.state = isDefaultReader ? .on : .off
            return true
        case #selector(chooseEditorAction(_:)):
            item.title = "外部编辑器：\(ExternalEditor.appName)…"
            return true
        case #selector(zoomInAction(_:)):
            return activeViewer != nil || Preferences.zoom < (Preferences.zoomSteps.last ?? 3)
        case #selector(zoomOutAction(_:)):
            return activeViewer != nil || Preferences.zoom > (Preferences.zoomSteps.first ?? 0.5)
        default:
            return true
        }
    }

    // MARK: 最近打开（NSMenuDelegate）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.tildePath
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "清除菜单", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = NSDocumentController.shared
        menu.addItem(clear)
    }
}
