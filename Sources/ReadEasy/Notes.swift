import Foundation

/// 一条划词备注。按「原文 + 前后文 + 位置」定位，文件改动后页面会在新内容里重新查找原文。
struct Note: Codable, Identifiable, Equatable {
    let id: String
    /// 选中的原文（空白已合并成单个空格）
    let quote: String
    /// 原文前后各一小段文字，原文在文档里出现多次时用来分辨是哪一处
    let prefix: String
    let suffix: String
    /// 原文在整篇正文文字里的位置，前后文也分不出时取离它最近的一处
    let start: Int
    var text: String
    let created: Date
    var modified: Date

    /// 交给页面的数据
    var payload: [String: Any] {
        [
            "id": id, "quote": quote, "prefix": prefix, "suffix": suffix, "start": start,
            "text": text, "modified": modified.timeIntervalSince1970 * 1000,
        ]
    }
}

/// 页面上报的定位结果：placed 按在文档里的先后排列，missing 是在当前内容里找不到原文的备注
struct NotePlacement: Equatable {
    var placed: [String] = []
    var missing: Set<String> = []
}

/// 备注不写回 Markdown 文件，统一存在 ~/Library/Application Support/ReadEasy/notes.json，按文件路径分组。
@MainActor
final class NoteStore {
    static let shared = NoteStore()

    private struct Archive: Codable {
        var version = 1
        var files: [String: [Note]]
    }

    private let fileURL: URL
    private var files: [String: [Note]] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        // Debug 构建（自动化验证）不碰正式版的备注
        let folder = "ReadEasy Debug"
        #else
        let folder = "ReadEasy"
        #endif
        fileURL = support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("notes.json")
        load()
    }

    func notes(for file: URL) -> [Note] { files[file.path] ?? [] }

    func add(quote: String, prefix: String, suffix: String, start: Int, text: String, to file: URL) {
        let now = Date()
        let note = Note(id: UUID().uuidString, quote: quote, prefix: prefix, suffix: suffix, start: start,
                        text: text, created: now, modified: now)
        files[file.path, default: []].append(note)
        commit(file)
    }

    func update(_ id: String, text: String, in file: URL) {
        guard let index = files[file.path]?.firstIndex(where: { $0.id == id }),
              files[file.path]?[index].text != text else { return }
        files[file.path]?[index].text = text
        files[file.path]?[index].modified = Date()
        commit(file)
    }

    func delete(_ id: String, in file: URL) {
        guard files[file.path]?.contains(where: { $0.id == id }) == true else { return }
        files[file.path]?.removeAll { $0.id == id }
        if files[file.path]?.isEmpty == true { files[file.path] = nil }
        commit(file)
    }

    private func commit(_ file: URL) {
        save()
        NotificationCenter.default.post(name: .readerNotesDidChange, object: nil, userInfo: ["path": file.path])
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            files = try decoder.decode(Archive.self, from: data).files
        } catch {
            // 读不出来时把原文件挪到一边再从空白开始，不直接覆盖掉
            let backup = fileURL.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("ReadEasy 备注文件无法读取，已移到 \(backup.path)：\(error)")
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Archive(files: files)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ReadEasy 备注保存失败：\(error)")
        }
    }
}
