import Foundation

/// 服务器激活：调你自托管的激活服务（license-server）。激活码 + 设备绑定 + 可吊销 + 到期。
/// 部署后把 serverBase 改成你的地址（本机测试用 http://localhost:8787）。
enum License {
    static let serverBase = "http://localhost:8787"

    struct Result {
        let ok: Bool
        let expiresAt: Double?     // epoch ms，nil=永久
        let error: String?         // "__offline__" = 网络失败（宽限用）
    }

    static func call(_ path: String, code: String, device: String) async -> Result {
        guard let url = URL(string: serverBase + path) else { return Result(ok: false, expiresAt: nil, error: "激活服务器地址无效") }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "device": device])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return Result(ok: j["ok"] as? Bool ?? false, expiresAt: j["expiresAt"] as? Double, error: j["error"] as? String)
        } catch {
            return Result(ok: false, expiresAt: nil, error: "__offline__")
        }
    }
}
