import AppKit
import WebKit

/// 每个窗口一个 WKWebView，常驻加载 index.html，之后只通过 JS 替换内容，切换文件不重新加载页面。
@MainActor
final class WebBridge: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: ReaderWebView
    weak var model: ReaderModel?
    /// 页面滚动停下后上报的位置，用于前进/后退和网页进程意外退出后恢复
    private(set) var scrollY: Double = 0

    private let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")!
    private var isReady = false
    private var hasLoaded = false
    private var pendingRender: [String: Any]?
    private var observers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    override init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        webView = ReaderWebView(frame: .zero, configuration: config)
        super.init()

        config.userContentController.add(WeakScriptHandler(self), name: "bridge")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = Preferences.zoom
        #if DEBUG
        webView.isInspectable = true
        #endif
        load()

        observers.append(NotificationCenter.default.addObserver(
            forName: .readerZoomDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.webView.pageZoom = Preferences.zoom }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAccent() }
        })
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyAccent() }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func load() {
        isReady = false
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    // MARK: 原生 → 页面

    func render(markdown: String, fileURL: URL, anchor: String?, scrollY: Double, keepScroll: Bool) {
        let payload: [String: Any] = [
            "markdown": markdown,
            "base": fileURL.deletingLastPathComponent().absoluteString,
            "anchor": anchor ?? "",
            "scrollY": scrollY,
            "keepScroll": keepScroll,
        ]
        if !keepScroll { self.scrollY = scrollY }
        if isReady { send(payload) } else { pendingRender = payload }
    }

    private func send(_ payload: [String: Any]) {
        webView.callAsyncJavaScript(
            "return await ReadEasy.render(p)", arguments: ["p": payload], in: nil, in: .page
        ) { result in
            if case let .failure(error) = result { NSLog("ReadEasy 渲染失败：\(error)") }
        }
    }

    func scrollTo(_ id: String) {
        guard isReady else { return }
        webView.callAsyncJavaScript("ReadEasy.scrollToId(id)", arguments: ["id": id], in: nil, in: .page)
    }

    func find(_ query: String, backwards: Bool) async -> FindStatus {
        guard isReady else { return FindStatus() }
        let result = try? await webView.callAsyncJavaScript(
            "return ReadEasy.find(q, b)", arguments: ["q": query, "b": backwards], contentWorld: .page)
        return FindStatus(result as? [String: Any])
    }

    func findClear() {
        guard isReady else { return }
        webView.evaluateJavaScript("ReadEasy.findClear()")
    }

    private func applyAccent() {
        guard isReady else { return }
        var hex = "#007aff"
        webView.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                hex = String(format: "#%02x%02x%02x",
                             Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
            }
        }
        webView.evaluateJavaScript("ReadEasy.setAccent('\(hex)')")
    }

    // MARK: 页面 → 原生

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        switch type {
        case "ready":
            let reloaded = hasLoaded
            hasLoaded = true
            isReady = true
            applyAccent()
            if let payload = pendingRender {
                pendingRender = nil
                send(payload)
            } else if reloaded {
                // 页面被重新加载（例如网页进程退出后重启），内容需要重新渲染
                model?.rerender()
            }
        case "headings":
            let list = body["headings"] as? [[String: Any]] ?? []
            model?.headings = list.compactMap { item in
                guard let id = item["id"] as? String, let level = item["level"] as? Int else { return nil }
                return Heading(id: id, level: level, text: item["text"] as? String ?? "")
            }
        case "active":
            model?.activeHeading = body["id"] as? String
        case "scroll":
            scrollY = body["y"] as? Double ?? 0
        case "link":
            if let href = body["href"] as? String {
                model?.handleLink(href, newTab: body["newTab"] as? Bool ?? false)
            }
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
        case "find":
            model?.findStatus = FindStatus(body)
        default:
            break
        }
    }

    // MARK: 导航

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        // 嵌入的 https iframe 正常加载
        if action.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
        if url.isFileURL, url.path == indexURL.path, action.navigationType != .linkActivated {
            return decisionHandler(.allow)
        }
        // 其余主框架导航（例如把文件拖进网页区域）都不在页面里跳转，交给原生处理
        decisionHandler(.cancel)
        if url.isFileURL {
            model?.openDropped([url])
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class ReaderWebView: WKWebView {
    private static let hiddenMenuItems: Set<String> = [
        "WKMenuItemIdentifierReload",
        "WKMenuItemIdentifierGoBack",
        "WKMenuItemIdentifierGoForward",
        "WKMenuItemIdentifierOpenLinkInNewWindow",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierOpenFrameInNewWindow",
        "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierDownloadMedia",
    ]

    // 不接收拖放，让外层 SwiftUI 视图统一处理“拖文件进来打开”
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items where Self.hiddenMenuItems.contains(item.identifier?.rawValue ?? "") {
            menu.removeItem(item)
        }
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        super.willOpenMenu(menu, with: event)
    }
}

extension FindStatus {
    init(_ dict: [String: Any]?) {
        self.init(current: dict?["current"] as? Int ?? 0, total: dict?["total"] as? Int ?? 0)
    }
}
