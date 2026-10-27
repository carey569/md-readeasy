import AppKit

@MainActor
enum MainMenu {
    static func build(recentMenuDelegate: NSMenuDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(root(appMenu()))
        main.addItem(root(fileMenu(recentMenuDelegate: recentMenuDelegate)))
        main.addItem(root(editMenu()))
        main.addItem(root(viewMenu()))
        main.addItem(root(goMenu()))
        let window = windowMenu()
        main.addItem(root(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "帮助")
        main.addItem(root(help))
        NSApp.helpMenu = help
        return main
    }

    private static func root(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "ReadEasy")
        menu.addItem(item("关于 ReadEasy", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("设为默认 Markdown 阅读器", #selector(AppDelegate.setDefaultReaderAction(_:))))
        menu.addItem(item("外部编辑器…", #selector(AppDelegate.chooseEditorAction(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "服务")
        let servicesItem = item("服务", nil)
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item("隐藏 ReadEasy", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("全部显示", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("退出 ReadEasy", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(recentMenuDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu(title: "文件")
        menu.addItem(item("新建窗口", #selector(AppDelegate.newWindowAction(_:)), "n"))
        menu.addItem(item("新建标签页", #selector(NSResponder.newWindowForTab(_:)), "t"))
        menu.addItem(.separator())
        menu.addItem(item("打开…", #selector(AppDelegate.openFileAction(_:)), "o"))
        menu.addItem(item("打开文件夹…", #selector(AppDelegate.openFolderAction(_:)), "o", [.command, .shift]))
        let recent = NSMenu(title: "打开最近使用")
        recent.delegate = recentMenuDelegate
        let recentItem = item("打开最近使用", nil)
        recentItem.submenu = recent
        menu.addItem(recentItem)
        menu.addItem(item("快速打开…", #selector(ReaderWindowController.readerQuickOpen(_:)), "p"))
        menu.addItem(.separator())
        menu.addItem(item("用外部编辑器打开", #selector(ReaderWindowController.readerOpenInEditor(_:)), "e"))
        menu.addItem(item("在 Finder 中显示", #selector(ReaderWindowController.readerRevealInFinder(_:)), "r", [.command, .shift]))
        menu.addItem(item("拷贝文件路径", #selector(ReaderWindowController.readerCopyPath(_:)), "c", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("关闭", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(item("撤销", Selector(("undo:")), "z"))
        menu.addItem(item("重做", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("剪切", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("拷贝", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("粘贴", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("全选", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("查找…", #selector(ReaderWindowController.readerFind(_:)), "f"))
        menu.addItem(item("查找下一个", #selector(ReaderWindowController.readerFindNext(_:)), "g"))
        menu.addItem(item("查找上一个", #selector(ReaderWindowController.readerFindPrevious(_:)), "g", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "显示")
        menu.addItem(item("隐藏边栏", #selector(ReaderWindowController.readerToggleSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("显示大纲", #selector(ReaderWindowController.readerToggleOutline(_:)), "o", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("实际大小", #selector(AppDelegate.zoomResetAction(_:)), "0"))
        menu.addItem(item("放大", #selector(AppDelegate.zoomInAction(_:)), "+"))
        // ⌘= 与 ⌘+ 同效（美式键盘上 + 需要按 Shift）
        let zoomInAlt = item("放大", #selector(AppDelegate.zoomInAction(_:)), "=")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlt)
        menu.addItem(item("缩小", #selector(AppDelegate.zoomOutAction(_:)), "-"))
        let widthMenu = NSMenu(title: "正文宽度")
        for width in ContentWidth.allCases {
            let option = item(width.title, #selector(AppDelegate.contentWidthAction(_:)))
            option.representedObject = width.rawValue
            widthMenu.addItem(option)
        }
        menu.addItem(root(widthMenu))
        menu.addItem(.separator())
        menu.addItem(item("显示标签页栏", #selector(NSWindow.toggleTabBar(_:))))
        menu.addItem(item("显示所有标签页", #selector(NSWindow.toggleTabOverview(_:)), "\\", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("进入全屏幕", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "前往")
        menu.addItem(item("后退", #selector(ReaderWindowController.readerGoBack(_:)), "["))
        menu.addItem(item("前进", #selector(ReaderWindowController.readerGoForward(_:)), "]"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "窗口")
        menu.addItem(item("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("缩放", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("显示上一个标签页", #selector(NSWindow.selectPreviousTab(_:)), "\t", [.control, .shift]))
        menu.addItem(item("显示下一个标签页", #selector(NSWindow.selectNextTab(_:)), "\t", .control))
        menu.addItem(item("将标签页移到新窗口", #selector(NSWindow.moveTabToNewWindow(_:))))
        menu.addItem(item("合并所有窗口", #selector(NSWindow.mergeAllWindows(_:))))
        menu.addItem(.separator())
        menu.addItem(item("前置全部窗口", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
