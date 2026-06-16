// PackDiscovery.swift — 在 App 内发现社区扩展包(扫描 GitHub `menumate-pack` topic)。
//
// 主 App 非沙盒,URLSession 无需网络 entitlement。用 GitHub 公开搜索 API(免鉴权,
// 速率较低但偶发浏览足够)。结果交给导入流程(PackImportSheet)按 owner/repo 预填,
// 仍走"逐脚本审查 + 默认禁用"的安全流程。

import Foundation

struct DiscoveredPack: Identifiable, Decodable, Equatable {
    let fullName: String          // "owner/repo"
    let description: String?
    let stargazersCount: Int
    let htmlURL: String
    let pushedAt: String?
    var id: String { fullName }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case stargazersCount = "stargazers_count"
        case htmlURL = "html_url"
        case pushedAt = "pushed_at"
    }
}

enum PackDiscovery {
    static let topic = "menumate-pack"

    /// 拉取带 `menumate-pack` topic 的公开仓库,按 star 降序。
    static func search() async throws -> [DiscoveredPack] {
        var comp = URLComponents(string: "https://api.github.com/search/repositories")!
        comp.queryItems = [
            .init(name: "q", value: "topic:\(topic)"),
            .init(name: "sort", value: "stars"),
            .init(name: "order", value: "desc"),
            .init(name: "per_page", value: "50"),
        ]
        var req = URLRequest(url: comp.url!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MenuMate", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "PackDiscovery", code: -1)
        }
        guard http.statusCode == 200 else {
            // 403 多为未鉴权速率限制
            throw NSError(domain: "PackDiscovery", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub API \(http.statusCode)"])
        }
        struct SearchResult: Decodable { let items: [DiscoveredPack] }
        return try JSONDecoder().decode(SearchResult.self, from: data).items
    }
}
