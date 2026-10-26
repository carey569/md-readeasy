import Foundation

struct QuickOpenItem: Identifiable, Hashable {
    let url: URL
    let name: String
    /// 显示在文件名后面的位置信息
    let location: String
    fileprivate let nameKey: [Character]
    fileprivate let pathKey: [Character]

    var id: String { url.path }
}

enum QuickOpen {
    static func items(for urls: [URL], base: URL?) -> [QuickOpenItem] {
        var seen = Set<String>()
        let basePath = base.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        return urls.compactMap { url in
            guard seen.insert(url.path).inserted else { return nil }
            let relative: String
            if let basePath, url.path.hasPrefix(basePath) {
                relative = String(url.path.dropFirst(basePath.count))
            } else {
                relative = url.tildePath
            }
            let dir = (relative as NSString).deletingLastPathComponent
            return QuickOpenItem(
                url: url,
                name: url.lastPathComponent,
                location: dir,
                nameKey: Array(url.lastPathComponent.lowercased()),
                pathKey: Array(relative.lowercased()))
        }
    }

    /// 模糊匹配：文件名命中优先，其次是路径；连续命中、单词开头命中加分。
    static func rank(_ items: [QuickOpenItem], query: String, limit: Int = 60) -> [QuickOpenItem] {
        let q = Array(query.trimmingCharacters(in: .whitespaces).lowercased().filter { $0 != " " })
        guard !q.isEmpty else { return Array(items.prefix(limit)) }
        var scored: [(score: Int, item: QuickOpenItem)] = []
        for item in items {
            if let s = score(q, item.nameKey) {
                scored.append((s + 1000, item))
            } else if let s = score(q, item.pathKey) {
                scored.append((s, item))
            }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.item.pathKey.count < $1.item.pathKey.count }
        return scored.prefix(limit).map(\.item)
    }

    private static let separators: Set<Character> = ["/", " ", "-", "_", "."]

    private static func score(_ query: [Character], _ text: [Character]) -> Int? {
        var score = 0
        var from = 0
        var last = -2
        for c in query {
            guard from < text.count, let idx = text[from...].firstIndex(of: c) else { return nil }
            score += idx == last + 1 ? 8 : 1
            if idx == 0 || separators.contains(text[idx - 1]) { score += 6 }
            last = idx
            from = idx + 1
        }
        return score - text.count / 10
    }
}
