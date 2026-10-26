import CoreServices
import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    let url: URL
    let children: [FileNode]?

    var id: String { url.path }
    var isDirectory: Bool { children != nil }
    var displayName: String {
        isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }
}

enum FileTree {
    struct Result: Sendable {
        var nodes: [FileNode] = []
        var files: [URL] = []
    }

    private static let skippedDirectories: Set<String> = ["node_modules", "Pods", "Carthage", "DerivedData", "__pycache__"]

    /// 递归列出 Markdown 文件，只保留含有 Markdown 的目录。目录在前，按 Finder 的顺序排序。
    static func scan(_ root: URL, maxDepth: Int = 12, limit: Int = 20_000) -> Result {
        var result = Result()
        var visited = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        func walk(_ dir: URL, depth: Int) -> [FileNode] {
            guard depth <= maxDepth, visited < limit,
                  let items = try? FileManager.default.contentsOfDirectory(
                      at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return [] }

            var dirs: [FileNode] = []
            var docs: [FileNode] = []
            for item in items.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                visited += 1
                let values = try? item.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory == true
                // 系统返回的路径可能带 /private 前缀，统一从 root 拼接，保证与应用内其他路径一致
                let url = dir.appendingPathComponent(item.lastPathComponent, isDirectory: isDirectory)
                if isDirectory {
                    guard values?.isPackage != true, !skippedDirectories.contains(item.lastPathComponent) else { continue }
                    let children = walk(url, depth: depth + 1)
                    if !children.isEmpty { dirs.append(FileNode(url: url, children: children)) }
                } else if MarkdownFiles.isMarkdown(url) {
                    docs.append(FileNode(url: url, children: nil))
                    result.files.append(url)
                }
            }
            return dirs + docs
        }

        result.nodes = walk(root, depth: 0)
        return result
    }
}

/// 监听单个文件的修改。编辑器常用“写临时文件再改名”的方式保存，所以文件被替换后要重新打开描述符。
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var retries = 0

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // 改名保存的瞬间文件可能还不存在，稍后重试
            guard retries < 20 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.start() }
            return
        }
        retries = 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                source.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.start()
                    self?.onChange()
                }
            } else {
                self.onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }
}

/// 用 FSEvents 监听目录树里文件的增删改名，用来刷新侧边栏。
final class DirectoryMonitor {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, _, flags, _ in
            guard let info else { return }
            let structural = FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                    | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagMustScanSubDirs)
            let changed = (0..<count).contains { flags[$0] & structural != 0 }
            if changed {
                Unmanaged<DirectoryMonitor>.fromOpaque(info).takeUnretainedValue().onChange()
            }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
