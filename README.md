# Amigo · 桌面搭子

被你真实行为驱动的原生 macOS 桌宠。一只住在桌面、会观察你的状态、陪你干活、还能被你调教性格的小家伙。

- 原生 SwiftPM + AppKit/SwiftUI，无 Xcode 工程，`swift build` 直接跑
- BYOK：接你自己的大模型端点（OpenAI 兼容），聊天 / 生成形象 / 生成动作都直连，数据只走你和你选的模型
- 行为驱动：久坐 / 熬夜 / 拖动 / 打开软件 → 自动切动作、主动冒泡
- 完全免费、开源（MIT）；无内购、无账号、无联网校验，数据只走你和你选的模型

> 说明：产品 / App / Bundle(`com.amigo.app`) / 数据目录 / 源码目录(`Sources/Amigo`) 全部统一为 **Amigo**。

---

## 开发运行

```bash
swift build            # 编译
swift run              # 直接跑（菜单栏出现爪印图标，桌面出现宠物）
```

- 需要 macOS 13+、Swift 6.x 工具链
- 首次运行会把内置形象（香蕉猫 + 看表鱼）连动作帧拷到数据目录，开箱即动

## 打包分发（.app）

```bash
swift build -c release
bash tools/package-app.sh          # 产出 dist/Amigo.app
```

`package-app.sh` 会：写 `Info.plist`（`com.amigo.app`、`LSUIElement`）、内置图标、把 `Assets/pets`（形象 + 动作帧）拷进包、**ad-hoc 自签**（不需要 Apple 开发者账号 / 公证）。

发给别人时若被 Gatekeeper 拦（未署名开发者）：
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
Sources/Amigo/     App 源码（AppKit + SwiftUI）
Assets/pets/         打包随附的内置形象 + 动作帧
tools/               package-app.sh（打包自签）、make-icon.swift
Docs/                动画系统等说明
AppIcon.icns         App 图标
```
