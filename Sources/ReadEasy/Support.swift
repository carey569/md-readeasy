import AppKit
import UniformTypeIdentifiers

enum MarkdownFiles {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"]

    static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static var contentTypes: [UTType] {
        var types = extensions.sorted().compactMap { UTType(filenameExtension: $0) }
        if let markdown = UTType("net.daringfireball.markdown") { types.insert(markdown, at: 0) }
        return types
    }
}

extension URL {
    /// 统一成去掉 `..`、解析符号链接后的路径，保证同一文件在各处比较时一致。
    var normalized: URL { standardizedFileURL.resolvingSymlinksInPath() }

    var tildePath: String { (path as NSString).abbreviatingWithTildeInPath }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

extension Notification.Name {
    static let readerZoomDidChange = Notification.Name("ReadEasy.zoomDidChange")
}

enum Preferences {
    private static let defaults = UserDefaults.standard
    static let zoomSteps: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static var zoom: Double {
        get {
            let value = defaults.double(forKey: "zoom")
            return value == 0 ? 1 : value
        }
        set {
            defaults.set(newValue, forKey: "zoom")
            NotificationCenter.default.post(name: .readerZoomDidChange, object: nil)
        }
    }

    static var showOutline: Bool {
        get { defaults.object(forKey: "showOutline") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showOutline") }
    }

    static var editorPath: String? {
        get { defaults.string(forKey: "editorPath") }
        set { defaults.set(newValue, forKey: "editorPath") }
    }

    static var windowFrame: NSRect? {
        get { defaults.string(forKey: "windowFrame").map(NSRectFromString).flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue.map(NSStringFromRect), forKey: "windowFrame") }
    }
}

enum TextLoader {
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// 优先 UTF-8，退回 GB18030（老的中文文档常见）。
    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: gb18030)
            ?? String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }
}

@MainActor
enum ExternalEditor {
    private static let knownEditors = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "abnerworks.Typora",
        "com.sublimetext.4",
        "com.barebones.bbedit",
        "com.panic.Nova",
        "com.coteditor.CotEditor",
    ]

    static var appURL: URL {
        if let path = Preferences.editorPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for id in knownEditors {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    }

    static var appName: String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    static func choose() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "选择"
        panel.message = "选择用来编辑 Markdown 的应用"
        if panel.runModal() == .OK, let url = panel.url {
            Preferences.editorPath = url.path
        }
    }
}
