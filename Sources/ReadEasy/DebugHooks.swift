#if DEBUG
import AppKit
import WebKit

/// 仅 Debug 构建：通过分布式通知驱动应用，便于在没有屏幕录制权限的环境下自动验证。
/// 例：postNotificationName("ReadEasy.debug", userInfo: ["action": "snapshot", "arg": "/tmp/a.png"])
@MainActor
enum DebugHooks {
    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("ReadEasy.debug"), object: nil, queue: .main
        ) { note in
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { handle(info["action"] ?? "", arg: info["arg"] ?? "", out: info["out"] ?? "") }
        }
    }

    private static var controller: ReaderWindowController? {
        (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.orderedWindows.first)?.windowController as? ReaderWindowController
    }

    private static func handle(_ action: String, arg: String, out: String) {
        guard let controller else { return write("no controller", to: out) }
        let model = controller.model
        switch action {
        case "snapshot": snapshot(controller, to: arg)
        case "open": AppDelegate.shared.open(URL(fileURLWithPath: arg))
        case "navigate": model.navigate(to: URL(fileURLWithPath: arg))
        case "link": model.handleLink(arg, newTab: false)
        case "back": model.goBack()
        case "forward": model.goForward()
        case "find":
            model.showFind()
            model.findQuery = arg
        case "findNext": model.findStep(backwards: false)
        case "hideFind": model.hideFind()
        case "quickOpen": model.toggleQuickOpen()
        case "outline": model.showOutline.toggle()
        case "sidebar": model.toggleSidebar()
        case "zoomIn": AppDelegate.shared.zoomInAction(nil)
        case "zoomReset": AppDelegate.shared.zoomResetAction(nil)
        case "width": Preferences.contentWidth = ContentWidth(rawValue: arg) ?? .standard
        case "pinch":
            // 模拟一次捏合：arg 为每一步的放大量，逗号分隔
            let web = model.web
            let center = CGPoint(x: web.webView.bounds.midX, y: web.webView.bounds.midY)
            let steps = arg.split(separator: ",").compactMap { Double($0) }
            web.magnify(by: 0, phase: .began, at: center)
            for step in steps { web.magnify(by: step, phase: .changed, at: center) }
            web.magnify(by: 0, phase: .ended, at: center)
        case "layoutSettings": model.layoutSettingsVisible.toggle()
        case "popoverShot":
            guard let window = NSApp.windows.first(where: { "\(type(of: $0))".contains("Popover") }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return write("no popover", to: out) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
        case "newTab": AppDelegate.shared.newTab(host: controller)
        case "clearRecents": NSDocumentController.shared.clearRecentDocuments(nil)
        case "appearance": NSApp.appearance = arg == "dark" ? NSAppearance(named: .darkAqua) : arg == "light" ? NSAppearance(named: .aqua) : nil
        case "js":
            model.web.webView.evaluateJavaScript(arg) { result, error in
                write("\(result.map { "\($0)" } ?? "nil") \(error.map { "ERROR \($0)" } ?? "")", to: out)
            }
        case "state":
            let tabs = controller.window?.tabbedWindows?.map(\.title) ?? []
            let state: [String: Any] = [
                "title": controller.window?.title ?? "",
                "subtitle": controller.window?.subtitle ?? "",
                "file": model.currentFile?.path ?? "",
                "root": model.rootFolder?.path ?? "",
                "headings": model.headings.map(\.text),
                "active": model.activeHeading ?? "",
                "find": "\(model.findStatus.current)/\(model.findStatus.total)",
                "quickOpenItems": model.quickOpenItems.map(\.name),
                "canGoBack": model.canGoBack,
                "canGoForward": model.canGoForward,
                "tabs": tabs,
                "windows": NSApp.windows.filter(\.isVisible).map(\.title),
                "treeCount": model.folderFiles.count,
                "expanded": Array(model.expanded),
                "zoom": Preferences.zoom,
                "pageZoom": model.web.webView.pageZoom,
                "width": Preferences.contentWidth.rawValue,
                "loadError": model.loadError ?? "",
                "viewerOpen": model.viewerOpen,
            ]
            let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            write(String(data: data ?? Data(), encoding: .utf8) ?? "", to: out)
        case "menus":
            var lines: [String] = []
            for top in NSApp.mainMenu?.items ?? [] {
                lines.append("[\(top.title)]")
                for item in top.submenu?.items ?? [] where !item.isSeparatorItem {
                    let mods = item.keyEquivalentModifierMask
                    let key = item.keyEquivalent.isEmpty ? "" : "\(mods.contains(.control) ? "⌃" : "")\(mods.contains(.option) ? "⌥" : "")\(mods.contains(.shift) ? "⇧" : "")\(mods.contains(.command) ? "⌘" : "")\(item.keyEquivalent)"
                    lines.append("  \(item.title) \(key)\(item.isHidden ? " (hidden)" : "")")
                }
            }
            write(lines.joined(separator: "\n"), to: out)
        default:
            write("unknown action \(action)", to: out)
        }
    }

    private static func write(_ text: String, to path: String) {
        guard !path.isEmpty else { return }
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// 窗口外观用 cacheDisplay 绘制，WebView 内容（跨进程渲染）用 takeSnapshot 叠加上去
    private static func snapshot(_ controller: ReaderWindowController, to path: String) {
        guard let window = controller.window, let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        let bounds = view.bounds
        view.cacheDisplay(in: bounds, to: rep)
        let web = controller.model.web.webView
        web.takeSnapshot(with: nil) { image, _ in
            let final = NSImage(size: bounds.size)
            final.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
            rep.draw(in: bounds)
            if let image, controller.model.currentFile != nil {
                var frame = web.convert(web.bounds, to: view)
                if view.isFlipped { frame.origin.y = bounds.height - frame.maxY }
                image.draw(in: frame)
            }
            final.unlockFocus()
            if let tiff = final.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
#endif
