import AppKit
import SwiftUI

@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model = ReaderModel()

    init() {
        let hosting = NSHostingController(rootView: ReaderRootView(model: model))
        hosting.sceneBridgingOptions = [.toolbars]
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1080, height: 760))
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "ReadEasy.reader"
        window.isReleasedWhenClosed = false
        window.title = "ReadEasy"

        super.init(window: window)
        window.delegate = self
        model.onDocumentChange = { [weak self] in self?.syncWindow() }
        model.openElsewhere = { [weak self] url in AppDelegate.shared.open(url, host: self) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func syncWindow() {
        guard let window else { return }
        if let file = model.currentFile {
            window.title = file.lastPathComponent
            window.representedURL = file
            let dir = file.deletingLastPathComponent()
            if let root = model.rootFolder {
                let parent = root.deletingLastPathComponent().path
                window.subtitle = String(dir.path.dropFirst(parent.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                window.subtitle = dir.tildePath
            }
        } else if let root = model.rootFolder {
            window.title = root.lastPathComponent
            window.representedURL = root
            window.subtitle = root.deletingLastPathComponent().tildePath
        } else {
            window.title = "ReadEasy"
            window.representedURL = nil
            window.subtitle = ""
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        model.teardown()
        AppDelegate.shared.controllerDidClose(self)
    }

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        Preferences.windowFrame = window.frame
    }

    // MARK: 菜单动作

    override func newWindowForTab(_ sender: Any?) {
        AppDelegate.shared.newTab(host: self)
    }

    @objc func readerGoBack(_ sender: Any?) { model.goBack() }
    @objc func readerGoForward(_ sender: Any?) { model.goForward() }
    @objc func readerFind(_ sender: Any?) { model.showFind() }
    @objc func readerFindNext(_ sender: Any?) { model.findStep(backwards: false) }
    @objc func readerFindPrevious(_ sender: Any?) { model.findStep(backwards: true) }
    @objc func readerQuickOpen(_ sender: Any?) { model.toggleQuickOpen() }
    @objc func readerToggleOutline(_ sender: Any?) { model.showOutline.toggle() }
    @objc func readerToggleSidebar(_ sender: Any?) { model.toggleSidebar() }

    @objc func readerOpenInEditor(_ sender: Any?) {
        if let file = model.currentFile { ExternalEditor.open(file) }
    }

    @objc func readerRevealInFinder(_ sender: Any?) {
        if let url = model.currentFile ?? model.rootFolder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func readerCopyPath(_ sender: Any?) {
        guard let url = model.currentFile ?? model.rootFolder else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    override func cancelOperation(_ sender: Any?) {
        if model.quickOpenVisible {
            model.quickOpenVisible = false
        } else if model.findVisible {
            model.hideFind()
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasFile = model.currentFile != nil
        switch item.action {
        case #selector(readerGoBack(_:)): return model.canGoBack
        case #selector(readerGoForward(_:)): return model.canGoForward
        case #selector(readerFind(_:)), #selector(readerFindNext(_:)), #selector(readerFindPrevious(_:)): return hasFile
        case #selector(readerToggleOutline(_:)):
            item.title = model.showOutline ? "隐藏大纲" : "显示大纲"
            return hasFile
        case #selector(readerToggleSidebar(_:)):
            item.title = model.columnVisibility == .detailOnly ? "显示边栏" : "隐藏边栏"
            return model.rootFolder != nil
        case #selector(readerOpenInEditor(_:)):
            item.title = "用 \(ExternalEditor.appName) 打开"
            return hasFile
        case #selector(readerRevealInFinder(_:)), #selector(readerCopyPath(_:)):
            return !model.isEmpty
        default:
            return true
        }
    }
}
