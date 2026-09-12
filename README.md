<div align="center">

# Amigo

**一只住在 Mac 桌面上的情绪陪伴。**

摸摸、喂一口会开心；冷落久了会想你。不干活，也不催你，除非你打开督促。

完全免费 · 开源 · 数据只留在你自己电脑上

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![license](https://img.shields.io/badge/license-MIT-green)
![price](https://img.shields.io/badge/price-free%20%C2%B7%20no%20IAP-orange)

</div>

---

## 它做什么

常驻桌面，多数时间不说话。右键可以摸摸、喂一口，或问它今天来过没有。心情和亲密度会变，不理也不会死；它自己记一句日记。

- 拖着它在桌面上跑；也可以让它蹲在当前窗口右下角
- 长按或双击可以聊天（自己的大模型，可选）
- 内置咕咕嘎嘎和草地牛；配了能生图的模型，才能生成新形象和新动作
- 久坐 / 熬夜催促默认可以关，和陪伴不是同一套开关

没配模型也能陪着。聊天、生成形象和动作才需要 Key。

## 上手

**下载**

1. 去 [Releases](../../releases) 下载 `Amigo.zip`，解压
2. 右键 `Amigo.app` →「打开」（ad-hoc 自签，未经 Apple 公证；之后可以双击）
3. 菜单栏出现爪印，桌面上出现它

**跑源码**

```bash
git clone https://github.com/FeiDao1224/amigo.git
cd amigo && swift run
```

需要 macOS 13+、Swift 5.10+（Xcode 15+）。SwiftPM，没有 Xcode 工程。

## 打包

```bash
swift build -c release
bash tools/package-app.sh          # 产出 dist/Amigo.app
```

脚本会写入 `Info.plist`、拷进图标和内置形象，并做 ad-hoc 自签。被 Gatekeeper 拦住时：右键打开，或 `xattr -cr /路径/Amigo.app`。

版本号只改 `Sources/AmigoCore/App/AppInfo.swift`。

## 模型

设置 → **模型**：填 OpenAI 兼容端点 + Key + 模型。Key 只存在本机 `config.json`（`chmod 600`），不进 Keychain、不上云。

生成动作 / 自定义形象需要端点支持 `gpt-image-2` 的 `/images/edits`。只会聊天的 Key 生不了图。

文本和生图都会走内置合规（[Compliance.swift](Sources/AmigoCore/LLM/Compliance.swift)）：拒绝违法和受保护 IP，只做原创形象。

## 数据

全部在 `~/Library/Application Support/Amigo/`：`config.json`、形象与动作帧、记忆、聊天、日记。设置 → **通用** 可以打开文件夹、导出或清空。

## 目录

```
Sources/Amigo/           可执行入口
Sources/AmigoCore/       业务与 UI
Tests/AmigoCoreTests/    表征测试
Assets/pets/             内置形象和动作帧
tools/package-app.sh     打包自签
ARCHITECTURE.md          改代码前读这个
```

## 参与

先看 [ARCHITECTURE.md](ARCHITECTURE.md)。里面写了对象分工、陪伴与动作决策，以及改 `Config` / API Key 前必须知道的坑。

```bash
swift test
```

## 许可证

[MIT](LICENSE)。
