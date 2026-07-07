#!/usr/bin/env swift
// 灵崽离线授权：卖家用私钥给"买家邮箱"签名 → 激活码；App 内嵌公钥验签。无需服务器。
// 用法：
//   生成密钥对(只做一次)：  swift tools/gen-license.swift keygen
//   给买家出码：           swift tools/gen-license.swift sign <买家邮箱> [私钥base64]
//   (私钥不填则读 tools/license-private.key)
import Foundation
import CryptoKit

let a = CommandLine.arguments
func die(_ s: String) -> Never { FileHandle.standardError.write(Data((s+"\n").utf8)); exit(1) }
guard a.count >= 2 else { die("usage: keygen | sign <email> [privkeyB64]") }

switch a[1] {
case "keygen":
    let k = Curve25519.Signing.PrivateKey()
    let priv = k.rawRepresentation.base64EncodedString()
    let pub = k.publicKey.rawRepresentation.base64EncodedString()
    try? priv.write(toFile: "tools/license-private.key", atomically: true, encoding: .utf8)
    try? pub.write(toFile: "tools/license-public.key", atomically: true, encoding: .utf8)
    print("PUBLIC=\(pub)")
    print("已保存 tools/license-private.key（务必保密，已 gitignore）与 tools/license-public.key")

case "sign":
    guard a.count >= 3 else { die("usage: sign <email> [privkeyB64]") }
    let privB64 = a.count >= 4 ? a[3]
        : ((try? String(contentsOfFile: "tools/license-private.key", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    guard let privData = Data(base64Encoded: privB64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else { die("私钥无效") }
    let email = a[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sig = try! key.signature(for: Data(email.utf8))
    print("邮箱：\(email)")
    print("激活码：\(sig.base64EncodedString())")

default: die("usage: keygen | sign <email> [privkeyB64]")
}
