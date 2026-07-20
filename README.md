<div align="center">

# 🐾 Amigo · 桌面搭子

**一只住在你 Mac 桌面、会观察你状态、陪你干活、还能被你调教性格的小家伙。**

完全免费 · 开源 · 数据只留在你自己电脑上

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![license](https://img.shields.io/badge/license-MIT-green)
![price](https://img.shields.io/badge/price-free%20%C2%B7%20no%20IAP-orange)

</div>

---

## 这是什么

Amigo 是一只常驻 macOS 桌面的宠物。它不只是个动图——它**看得到你此刻在干嘛**（久坐、熬夜、打开了什么软件），然后自己切换动作、时不时冒个泡提醒你；你也可以长按它直接聊天，或者上传几张照片让 AI 把它捏成**你专属的像素形象**。

- 🖐️ **能拖能玩**：拖着它在整个桌面上跑，拖得越快跑得越欢
- 📌 **会跟着你**：自己跑到你正在操作的那个窗口右下角蹲着（可关）
- 💬 **能聊天**：长按开对话，接你自己的大模型，聊多了它会慢慢记住你
- 🎨 **能换装**：内置咕咕嘎嘎（企鹅）和草地牛，也能上传照片生成专属形象和动作
- 🔒 **够安心**：完全免费开源，无账号无内购，API Key 和聊天记录只存在你本机

## 30 秒上手

**普通用户（下载即用）**

1. 去 [Releases](../../releases) 下载 `Amigo.zip`，解压
2. 右键 `Amigo.app` →「打开」（应用是 ad-hoc 自签、未经 Apple 公证，首次需要右键打开，之后双击即可）
3. 菜单栏冒出爪印图标、桌面右下角蹦出宠物 —— **长按它就能开聊**

**开发者（跑源码）**

```bash
git clone https://github.com/FeiDao1224/amigo.git
cd amigo && swift run          # 菜单栏出现爪印图标，桌面出现宠物
```

需要 macOS 13+、Swift 5.9 及以上工具链（Xcode 15+）。原生 SwiftPM + AppKit/SwiftUI，没有 Xcode 工程文件。首次运行会自动装好内置形象，开箱即动。

---

## 打包分发（.app）

```bash
swift build -c release
bash tools/package-app.sh          # 产出 dist/Amigo.app
```

`package-app.sh` 会：写 `Info.plist`（`com.amigo.app`、`LSUIElement`）、内置图标、把 `Assets/pets`（形象 + 动作帧）拷进包、**ad-hoc 自签**（不需要 Apple 开发者账号 / 公证）。

分发给别人时若被 Gatekeeper 拦下（未经公证的应用）：
- 右键 → 打开；或终端 `xattr -cr /路径/Amigo.app` 后再双击

## 配模型（BYOK）

设置 →「模型」页填端点 + Key（支持智谱 / DeepSeek / Kimi / 通义 / 硅基流动，或任意 OpenAI 兼容中转站）。
没配模型也能用内置形象自带的动作；**生成新动作 / 自定义形象**才需要模型。

## 内容合规红线

生成能力内置了合规护栏（[Sources/Amigo/Compliance.swift](Sources/Amigo/Compliance.swift)）：

- **文本**：每次大模型请求都注入红线系统提示（优先级高于用户自定义人设），输出须符合中华人民共和国法律法规，拒绝涉政敏感 / 暴恐 / 色情 / 赌毒 / 违法犯罪 / 翻墙规避监管等内容。
- **形象生成**：每次生图 prompt 追加版权 / 商标 / 肖像红线；对用户描述做前置关键词初筛，命中受保护 IP（迪士尼 / 宝可梦 / 三丽鸥等）或违法词直接拦下，只产出原创、非侵权形象。
- 上传自有素材做形象时，UI 也会提示「请使用原创或你有权使用的素材」。

## 数据位置

全部只存本机：`~/Library/Application Support/Amigo/`
（`config.json`、`pets/` 形象与动作帧、`memories.json`、`chat.json`）。模型 API Key 只存本机 `config.json`（`chmod 600`），不上云、不进 Keychain。
设置 →「性格 · 隐私」里可一键在访达打开 / 导出 / 清空。

## 目录结构

```
Sources/Amigo/       App 源码（AppKit + SwiftUI）
Assets/pets/         打包随附的内置形象 + 动作帧
tools/               package-app.sh（打包自签）等手动工具
Docs/                动画系统说明
ARCHITECTURE.md      架构说明（改代码前先读这个）
AppIcon.icns         App 图标
```

## 参与开发

想读懂代码或提 PR，先看 [ARCHITECTURE.md](ARCHITECTURE.md) —— 里面写清了三个核心对象的分工、动作生成管线，以及几个**改动前必须知道的坑**（尤其是 `Config` 字段的容错解码和 API Key 的存储方式）。

已知短板和值得下手的方向也列在那份文档末尾。

## 许可证

[MIT](LICENSE)。随便用、随便改、随便分发，保留版权声明即可。
