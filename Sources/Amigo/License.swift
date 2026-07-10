import CryptoKit
import Foundation

/// 首次联网激活后取得 Ed25519 签名收据；之后 App 用内置公钥离线验签。
/// 私钥只留在 license-server，不能打进 App 或提交到仓库。
enum License {
    static let serverBase: String = configurationValue("AMIGO_LICENSE_SERVER", bundleKey: "AmigoLicenseServer")
    static let publicKeyBase64: String = configurationValue("AMIGO_LICENSE_PUBLIC_KEY", bundleKey: "AmigoLicensePublicKey")
    static let enforced: Bool = boolConfiguration("AMIGO_LICENSE_ENFORCED", bundleKey: "AmigoLicenseEnforced")

    struct Result {
        let ok: Bool
        let expiresAt: Double?     // epoch ms，nil=永久
        let error: String?
        let receipt: String?
    }

    private struct ReceiptPayload: Codable {
        let version: Int
        let code: String
        let device: String
        let plan: String
        let expiresAt: Double?
        let issuedAt: Double
    }

    /// 验证已保存的签名收据。此路径完全离线，不请求服务器。
    static func verify(_ receipt: String, device: String) -> Result {
        guard !receipt.isEmpty else { return Result(ok: false, expiresAt: nil, error: "未激活", receipt: nil) }
        let parts = receipt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "v1",
              let payloadData = base64URLData(String(parts[1])),
              let signature = base64URLData(String(parts[2])),
              let publicKeyData = Data(base64Encoded: publicKeyBase64), publicKeyData.count == 32 else {
            return Result(ok: false, expiresAt: nil, error: "许可证格式无效", receipt: nil)
        }

        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            guard publicKey.isValidSignature(signature, for: Data(parts[1].utf8)) else {
                return Result(ok: false, expiresAt: nil, error: "许可证签名无效", receipt: nil)
            }
            let payload = try JSONDecoder().decode(ReceiptPayload.self, from: payloadData)
            guard payload.version == 1, payload.device == device else {
                return Result(ok: false, expiresAt: payload.expiresAt, error: "许可证不属于此设备", receipt: nil)
            }
            if let expiresAt = payload.expiresAt, Date().timeIntervalSince1970 * 1000 > expiresAt {
                return Result(ok: false, expiresAt: expiresAt, error: "许可证已过期", receipt: nil)
            }
            return Result(ok: true, expiresAt: payload.expiresAt, error: nil, receipt: receipt)
        } catch {
            return Result(ok: false, expiresAt: nil, error: "许可证无法验证", receipt: nil)
        }
    }

    /// 仅首次激活、换设备或在线复验时调用。离线失败不会影响已验签的本地收据。
    static func call(_ path: String, code: String, device: String) async -> Result {
        guard !serverBase.isEmpty, let url = URL(string: serverBase + path) else {
            return Result(ok: false, expiresAt: nil, error: "激活服务器地址无效", receipt: nil)
        }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "device": device])
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return Result(ok: false, expiresAt: nil, error: "__server__", receipt: nil)
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return Result(
                ok: json["ok"] as? Bool ?? false,
                expiresAt: json["expiresAt"] as? Double,
                error: json["error"] as? String,
                receipt: json["receipt"] as? String
            )
        } catch {
            return Result(ok: false, expiresAt: nil, error: "__offline__", receipt: nil)
        }
    }

    private static func configurationValue(_ environmentKey: String, bundleKey: String) -> String {
        if let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty { return value }
        return Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String ?? ""
    }

    private static func boolConfiguration(_ environmentKey: String, bundleKey: String) -> Bool {
        if let value = ProcessInfo.processInfo.environment[environmentKey] {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return Bundle.main.object(forInfoDictionaryKey: bundleKey) as? Bool ?? false
    }

    private static func base64URLData(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
