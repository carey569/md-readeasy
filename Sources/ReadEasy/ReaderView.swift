import AppKit
import SwiftUI
import WebKit

struct ReaderRootView: View {
    @Bindable var model: ReaderModel
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if model.rootFolder != nil {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    SidebarView(model: model)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
                } detail: {
                    DocumentPane(model: model)
                }
            } else {
                DocumentPane(model: model)
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .overlay {
            if model.quickOpenVisible { QuickOpenView(model: model) }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.openDropped(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }
}

// MARK: - 文档区

struct DocumentPane: View {
    @Bindable var model: ReaderModel

    var body: some View {
        ZStack(alignment: .top) {
            WebViewHost(webView: model.web.webView)
                .opacity(model.currentFile == nil ? 0 : 1)

            if model.currentFile == nil {
                if model.rootFolder == nil {
                    WelcomeView()
                } else if !model.isScanning {
                    ContentUnavailableView {
                        Label(model.tree.isEmpty ? "没有 Markdown 文件" : "选择一个文档", systemImage: "doc.text")
                    } description: {
                        Text(model.tree.isEmpty ? "这个文件夹里没有找到 .md 文件" : "从左侧选择，或按 ⌘P 快速打开")
                    }
                }
            }

            if model.findVisible {
                FindBar(model: model)
                    .padding(.top, 10)
                    .padding(.trailing, 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 20)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .inspector(isPresented: outlinePresented) {
            OutlineView(model: model)
                .inspectorColumnWidth(min: 180, ideal: 230, max: 360)
        }
        .toolbar {
            if model.currentFile != nil {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: model.goBack) {
                        Label("后退", systemImage: "chevron.left")
                    }
                    .disabled(!model.canGoBack)
                    .help("后退 ⌘[")
                    Button(action: model.goForward) {
                        Label("前进", systemImage: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                    .help("前进 ⌘]")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.showOutline.toggle()
                    } label: {
                        Label("大纲", systemImage: "list.bullet.indent")
                    }
                    .help("显示或隐藏大纲 ⌥⌘O")
                }
            }
        }
    }

    private var outlinePresented: Binding<Bool> {
        Binding(
            get: { model.showOutline && model.currentFile != nil },
            set: { if model.currentFile != nil { model.showOutline = $0 } })
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - 欢迎页

struct WelcomeView: View {
    private let recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(8))

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("ReadEasy")
                    .font(.system(size: 26, weight: .semibold))
                Text("把 Markdown 文件或文件夹拖到这里")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("打开文件…") { AppDelegate.shared.openFileAction(nil) }
                Button("打开文件夹…") { AppDelegate.shared.openFolderAction(nil) }
            }
            .controlSize(.large)

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近打开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .padding(.bottom, 4)
                    ForEach(recents, id: \.self) { url in
                        RecentRow(url: url)
                    }
                }
                .frame(width: 360)
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecentRow: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button {
            AppDelegate.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(url.lastPathComponent)
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().tildePath)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 侧边栏

struct SidebarView: View {
    @Bindable var model: ReaderModel

    var body: some View {
        List(selection: selection) {
            Section(model.rootFolder?.lastPathComponent ?? "") {
                ForEach(model.tree) { node in
                    FileTreeRow(node: node, model: model)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.currentFile?.path },
            set: { path in
                guard let path, MarkdownFiles.isMarkdown(URL(fileURLWithPath: path)) else { return }
                model.navigate(to: URL(fileURLWithPath: path))
            })
    }
}

private struct FileTreeRow: View {
    let node: FileNode
    @Bindable var model: ReaderModel

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: expanded) {
                ForEach(children) { FileTreeRow(node: $0, model: model) }
            } label: {
                Label(node.displayName, systemImage: "folder")
                    .contentShape(Rectangle())
                    .onTapGesture { expanded.wrappedValue.toggle() }
            }
        } else {
            Label(node.displayName, systemImage: "doc.text")
                .lineLimit(1)
                .help(node.url.lastPathComponent)
                .tag(node.id)
                .contextMenu {
                    Button("在新标签页中打开") { model.openElsewhere?(node.url) }
                    Button("用 \(ExternalEditor.appName) 打开") { ExternalEditor.open(node.url) }
                    Divider()
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                }
        }
    }

    private var expanded: Binding<Bool> {
        Binding(
            get: { model.expanded.contains(node.id) },
            set: { open in
                if open { model.expanded.insert(node.id) } else { model.expanded.remove(node.id) }
            })
    }
}

// MARK: - 大纲

struct OutlineView: View {
    let model: ReaderModel

    var body: some View {
        let minLevel = model.headings.map(\.level).min() ?? 1
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.headings) { heading in
                        OutlineRow(
                            heading: heading,
                            depth: heading.level - minLevel,
                            active: heading.id == model.activeHeading
                        ) {
                            model.web.scrollTo(heading.id)
                        }
                        .id(heading.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .overlay {
                if model.headings.isEmpty {
                    Text("没有标题")
                        .foregroundStyle(.tertiary)
                }
            }
            .onChange(of: model.activeHeading) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
            }
        }
    }
}

private struct OutlineRow: View {
    let heading: Heading
    let depth: Int
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(heading.text.isEmpty ? " " : heading.text)
                .font(.system(size: 13, weight: depth == 0 ? .medium : .regular))
                .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : depth >= 2 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.leading, CGFloat(min(depth, 4)) * 12 + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.accentColor.opacity(0.12) : hovering ? Color.primary.opacity(0.05) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 查找栏

struct FindBar: View {
    @Bindable var model: ReaderModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("在文档中查找", text: $model.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    model.findStep(backwards: press.modifiers.contains(.shift))
                    return .handled
                }
                .onExitCommand { model.hideFind() }
            if !model.findQuery.isEmpty {
                Text(model.findStatus.total == 0 ? "无结果" : "\(model.findStatus.current)/\(model.findStatus.total)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 16)
            Group {
                Button { model.findStep(backwards: true) } label: { Image(systemName: "chevron.up") }
                    .help("上一个 ⇧⌘G")
                Button { model.findStep(backwards: false) } label: { Image(systemName: "chevron.down") }
                    .help("下一个 ⌘G")
                Button { model.hideFind() } label: { Image(systemName: "xmark.circle.fill") }
                    .help("关闭 esc")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .onAppear { focused = true }
        .onChange(of: model.findFocusRequest) { focused = true }
    }
}

// MARK: - 快速打开

struct QuickOpenView: View {
    @Bindable var model: ReaderModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [QuickOpenItem] { QuickOpen.rank(model.quickOpenItems, query: query) }

    var body: some View {
        let results = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .onTapGesture { model.quickOpenVisible = false }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                    TextField("按文件名查找", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onSubmit { open(results) }
                        .onExitCommand { model.quickOpenVisible = false }
                        .onKeyPress(.downArrow) { move(1, count: results.count); return .handled }
                        .onKeyPress(.upArrow) { move(-1, count: results.count); return .handled }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                if !results.isEmpty {
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    QuickOpenRow(item: item, selected: index == selection)
                                        .id(index)
                                        .onTapGesture { model.openFromQuickOpen(item) }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 340)
                        .fixedSize(horizontal: false, vertical: true)
                        .onChange(of: selection) { _, index in proxy.scrollTo(index) }
                    }
                } else if !query.isEmpty {
                    Divider()
                    Text("没有匹配的文件")
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .frame(width: 580)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
            .padding(.top, 64)
        }
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func open(_ results: [QuickOpenItem]) {
        guard results.indices.contains(selection) else { return }
        model.openFromQuickOpen(results[selection])
    }
}

private struct QuickOpenRow: View {
    let item: QuickOpenItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            Text(item.name)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(item.location)
                .font(.callout)
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
    }
}
