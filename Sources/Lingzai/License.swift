import Foundation
import CryptoKit

/// 离线授权：卖家用私钥给"买家邮箱"签名生成激活码；此处用内嵌公钥验签。无需服务器。
/// 出码见 tools/gen-license.swift（私钥在 tools/license-private.key，切勿泄露/入库）。
enum License {
    /// 公钥（Curve25519，base64）。换密钥对时用 `gen-license.swift keygen` 的 PUBLIC 覆盖这里。
    private static let publicKeyB64 = "mZKD0LQCEmTxiU6+Lfbme+whut54BQ1lFlt46NSoLBw="

    /// 校验"邮箱 + 激活码"是否匹配（激活码 = 用私钥对小写邮箱的签名）
    static func verify(email: String, code: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !c.isEmpty,
              let pkData = Data(base64Encoded: publicKeyB64),
              let sig = Data(base64Encoded: c),
              let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: pkData)
        else { return false }
        return pk.isValidSignature(sig, for: Data(e.utf8))
    }
}
