# Amigo 架构说明

写给想读懂或改动这个项目的人。读完这份 + 扫一遍 `Sources/AmigoCore/`，就能动手改。
有出入以代码为准（注释是中文，风格偏紧凑）。

---

## 速览

- **是什么**：原生 macOS 桌面宠物。常驻桌面、被你的真实操作驱动切换动作，可以接你自己的大模型聊天、生成形象与动作。
- **技术栈**：Swift + AppKit + SwiftUI，SwiftPM 包（**没有 Xcode 工程**），目标 macOS 13+。库 target `AmigoCore` + 可执行 target `Amigo` + 测试 `AmigoCoreTests`。
- **规模**：核心库按职责分目录，约 3800 行业务代码。
- **数据**：全部只在本机 `~/Library/Application Support/Amigo/`（含 API Key）。不上传任何服务器。
- **授权**：MIT。无内购、无账号、无联网校验；BYOK，模型成本由使用者自己的 key 承担。

---

## 构建 / 运行 / 打包

```bash
swift build                 # 编译（debug）
swift test                  # AmigoCore 表征测试
swift run                   # 编译并运行
swift build -c release      # release

bash tools/package-app.sh   # 打包 dist/Amigo.app（ad-hoc 自签，无需 Apple 账号）

git tag vX.Y.Z && git push origin vX.Y.Z
#   → .github/workflows/build.yml 在 macos-15 上构建、打包并发 GitHub Release
```

**版本号唯一来源是 `Sources/AmigoCore/App/AppInfo.swift`**，`package-app.sh` 从中读取写进 `Info.plist`，关于页也读它。改版本只改这一处。

`tools/` 里除 `package-app.sh` 外都是手动跑的一次性工具，不参与构建：`make-icon.swift`（重生成图标）、`dewhite.swift` / `pixelize.swift`（图像处理）。

---

## 顶层结构

```
Sources/Amigo/            可执行入口（main.swift → AmigoApp.start）
Sources/AmigoCore/        全部业务与 UI（可被测试依赖）
  App/                    启动、AppDelegate、AppState、版本号
  Models/                 Config / Provider / 人设 / 记忆
  Pet/                    运行时、视图、跟随、行为、动作决策
  Chat/                   会话与聊天窗
  Generation/             生图切帧
  LLM/                    聊天 API、合规、系统信息
  Settings/               设置与引导
  System/                 开机自启
Tests/AmigoCoreTests/     纯逻辑表征测试
Assets/pets/              随包内置形象 PNG + 动作帧（penguin / cow）
tools/                    打包脚本与手动工具
Docs/                     动画系统说明
.github/workflows/        build.yml（CI）
AppIcon.icns              App 图标
dist/                     打包产物（已 gitignore）
```

---

## 运行期架构

单进程、菜单栏 accessory app。三个核心对象：

- **`AppState`** — `ObservableObject`，持有 `config`（唯一数据源）和 memories，被**设置窗**观察。所有非高频的状态与业务方法在这里（模型管理、形象、动作、记忆、导入导出）。
- **`PetRuntime`** — `ObservableObject`，只被**宠物窗**观察的**高频动画状态**（当前帧、fps、朝向、气泡、拖动态）。刻意与 AppState 分开，避免高频重绘拖累设置窗。
- **`AppDelegate`** — 组装一切：菜单栏、宠物窗 `PetPanel`、`BehaviorEngine` / `ChatSession` / `WindowFollower`，以及 0.05s 的 `cursorTimer`（驱动点击穿透、窗口跟随与行为动作）。切哪套动作交给 `PetActionPolicy`（纯函数）。**想理解交互逻辑先读它。**

数据流：`config.json` → `AppState` → 回调闭包喂给 `PetRuntime` 与各引擎 → SwiftUI 渲染。
用户操作 → `AppState` 方法改 `config` → `persist()` 落盘 → 通过 `onXxxChanged` 闭包通知 runtime 刷新。

---

## 文件地图

### 入口 / 组装
- `Sources/Amigo/main.swift` — 转发到 `AmigoApp.start()`。
- `App/Launch.swift` — 启动 NSApplication。
- `App/AppDelegate.swift` — 交互与窗口管理中枢，内含 `PetPanel: NSPanel`（透明置顶、可点击穿透的宠物窗）。
- `App/AppInfo.swift` — 版本号、仓库地址、bundle id。

### 状态 / 数据模型
- `App/AppState.swift` — 业务与状态中枢。
- `Models/Config.swift` — `Config`、`CustomPet`、`CustomAction`、`ConfigStore`（**容错解码**，见「必读坑」）。
- `Models/Provider.swift` — `Provider.fromImport`（分享链接 / Codex 配置）、`KeychainStore`（只读/删，把历史 key 迁回本地）。
- `Models/Persona.swift` — `CardData`（人设）。
- `Models/Memory.swift` — 长期记忆模型 + `MemoryStore`。
- `Pet/PetRuntime.swift` — 高频动画状态、`showAction`（按帧数自适应 fps）、`speak` / `nudge` 的 LLM 调用。

### 宠物窗 / 动画 / 交互
- `Pet/PetView.swift` — 宠物视图：气泡 / 输入框 + 帧动画 + 点击 / 双击 / 长按 / 拖动手势。顶部的 `PetLayout` 定义窗口与精灵尺寸。
- `Pet/Components.swift` — 毛玻璃、`PetMotion` / `MoveMotion`（无生成帧时的程序位移兜底）、气泡形状、`SectionHeader` 等。
- `Pet/WindowFollower.swift` — 贴住当前活动窗口右下角。只读 `CGWindowList` 取窗口边框，不需要辅助功能权限。
- `Pet/BehaviorEngine.swift` — 30s 定时的主动督促引擎（久坐 / 熬夜 / 离开归来 / 专注）。**只管主动冒泡**；切动作在 `PetActionPolicy`，点击穿透在 AppDelegate。
- `Pet/PetActionPolicy.swift` — 根据对话 / 隐身 / 拖动 / 闲置决定播哪套动作（可单测）。

### 形象 / 动作生成
- `Generation/SpriteGen.swift` — 动作帧生成管线：`PetAnimAction`（work / phone / think / idle / walk / sleep）→ 调 ImageGen 用**洋红 #FF00FF 作为抠图底**生成一张 3×3 网格图 → 切 9 帧 → `removeChroma`（角点自适应色键，避免白色形象被吃掉）→ `dropOutlierFrames`（按包围盒高度中位数剔除穿模 / 画崩帧，保底 ≥5 帧）→ `register`（水平按**重心**对齐 + 底部对齐，防横晃）→ 存 `generated/<形象>/<动作>/frame-0..8.png`。
- `Generation/ImageGen.swift` — OpenAI 兼容 `/images/edits`（模型 `gpt-image-2`），multipart 优先、JSON `image_urls` 兜底。
- `Generation/Pixelizer.swift` — 无模型时的本地像素化（Vision 前景抠图 + 降色）。
- `Pet/PetImages.swift` — 形象静态图加载 + `installDefaults`（首启把内置形象和动作帧拷到本机）。

### 聊天 / 记忆
- `Chat/ChatSession.swift` — 多轮对话 + `ChatStore`（chat.json）+ 后台从对话抽取长期记忆。
- `Chat/MemoryInference.swift` — 从模型回复解析记忆 JSON（非法范围不 trap）。
- `Chat/ChatView.swift` — 独立聊天窗。
- `LLM/LLM.swift` — OpenAI 兼容 `/chat/completions` 封装，**每次请求经 `Compliance.inject` 注入内容红线**。
- `LLM/SystemInfo.swift` — 实时状态（时间 / 内存 / 前台 app）+ 共用的 `idleSeconds()`；前台 app 部分受 `senseFrontApp` 开关控制。

### 设置界面
- `Settings/SettingsView.swift` — 设置主壳：左侧栏（通用 / 模型 / 形象 / 性格 / 交互 / 关于）+ 右侧内容路由。
- `Settings/SettingsPanes.swift` — `ModelPane`、`PersonaPane`、`MemoryPane`。
- `Settings/PetSettingsCards.swift` — 形象页卡片：形象选择器、`ActionRow` / `ActionPreview`、`NewActionCard`、`CustomPetCard`。
- `Settings/OnboardingView.swift` — 首启引导。

### 系统集成
- `LLM/Compliance.swift` — 内容红线：文本红线（`inject`）、图像版权红线（`imageClause`）、用户输入初筛（`screenImagePrompt`）。
- `System/LaunchAtLogin.swift` — 开机自启，往 `~/Library/LaunchAgents/com.amigo.app.plist` 写 LaunchAgent。

---

## 数据与存储

全部在 `~/Library/Application Support/Amigo/`（目录 `0700`）：

- `config.json`（`0600`）— 全部配置，**含明文 API Key**。
- `memories.json` / `chat.json` — 记忆与聊天记录。
- `pets/<形象>.png` — 形象静态图；`pets/generated/<形象>/<动作>/frame-N.png` — 动作帧。

**形象系统**：内置 `penguin`（咕咕嘎嘎，默认）与 `cow`（草地牛）；用户自定义存 `customPets`（**追加不覆盖**）。名字与人设按形象绑定在 `personas`，换形象各自切换。

---

## 关键交互实现

- **点击穿透**：`AppDelegate.cursorTick()`（0.05s）用 `petGrabRect`（带**滞回**，防边缘抖动）判断鼠标是否在宠物身上，只在状态变化时切 `panel.ignoresMouseEvents`。**「抓不住 / 拖不动」类问题的高发区。**
- **窗口尺寸**：平时窗口只有 `PetLayout.compact`（贴合宠物本体），冒泡或输入时才撑到 `PetLayout.expanded`。`syncPanelSize()` **每帧都按底边中点这个锚点摆位** —— 因为 `NSHostingView` 会抢先按内容改窗口大小、且钉的是左上角，不纠正宠物会整个往下掉。
- **拖动**：`dragTick()` 用绝对鼠标坐标移动面板；拖得越快播放倍速越高；`dx` 决定 `facingLeft`。
- **窗口跟随**：`WindowFollower` 以 5Hz 查活动窗口、20Hz 插值移动（每帧趋近 22%、上限 70pt），拖走后暂时脱离，切窗口自动恢复。
- **行为切动作**：`PetActionPolicy`：对话 / 等回复 → `mapChat`；拖动 → `mapDrag`；闲置 >180s → sleep（优先于工作）；前台有 app → work；隐身或关掉行为驱动 → 默认动作。AppDelegate 只负责采样闲置/前台并应用结果。
- **播放帧率**：`PetRuntime.showAction` 里 `fps = min(20, 帧数 / loopSeconds)`，4 / 9 / 16 帧都是同样的循环时长。`PetAnimAction.loopSeconds` 是节奏的唯一调节点。

---

## 必读坑

1. **改 `Config` 字段要小心**：Swift 合成的 Codable 缺字段会**整体解码失败**。`ConfigStore.load()` 已做容错合并（严格解码失败 → 把磁盘值合并到默认配置再解），所以**加字段是安全的**；但**别把这段容错删掉**，否则用户升级会丢模型配置、形象和人设。
2. **API Key 存本地明文 `config.json`（`0600`），不进 Keychain。** 曾短暂迁往 Keychain 后回退，`AppState.migrateProviderSecretsBack()` 负责把历史条目搬回来（**读成功才删** Keychain 条目，读不到就保留，绝不因读取失败销毁 key）。改这块前先想清楚。
3. **一次性迁移不能删**：`migrateDataDir()`（旧数据目录改名）、`migrateCharacters()`（清理已下架形象）、`migrateCompactPetWindow()`（窗口收窄后修正存档位置）、`LaunchAtLogin.migrateLegacyLabel()`（旧自启标签）。都是幂等的、带标志位或存在性判断。
4. **生图能力是硬门槛**：动作与自定义形象生成依赖端点支持 `gpt-image-2` 的 `/images/edits`。**只有聊天能力的 key 生不了图** —— 「为什么我生不了动作」多半是这个原因。
5. **帧数历史**：4 帧（初版）→ 16 帧（太抽）→ 现在 9 帧（3×3）。旧形象里可能残留 4 / 16 帧，`loadFrames` 读到缺帧为止、fps 自适应，混着也能播；要看新效果需重新生成。
6. **两个 ObservableObject 分工别混**：高频动画状态放 `PetRuntime`，其余放 `AppState`，否则设置窗会被高频重绘拖慢。
7. **新增生成入口别绕过合规**：文本走 `LLM.chat` 会自动 `Compliance.inject`，生图走 `ImageGen.edit` 会自动加 `imageClause`。

---

## 已知短板

**架构**
- `AppDelegate.swift` 仍负责窗口 / 穿透 / 拖动 / 菜单；动作决策已抽到 `PetActionPolicy`。
- 与 AppKit 深度耦合，没有平台抽象层。
- 空闲时约 10% CPU、100MB 内存（release 构建实测）：`PetView` 的 `TimelineView` 无条件 20fps 重绘，加上 0.05s 的 `cursorTimer`。静止时应该可以降到接近零。

**生成质量**
- 9 帧网格偶发画崩或倒置，目前靠 prompt 强约束 + `dropOutlierFrames` + 重新生成兜底，还可以加朝向检测和帧间一致性校验。
- `register()` 的重心对齐对原地动作效果好，大幅位移动作可能仍偏。
- 形象相似度只靠提示词，没有二次校验。

**工程**
- 已有 `AmigoCoreTests`（合规、导入 Provider、Config 容错、记忆解析、动作决策）。`SpriteGen` 切帧对齐、`WindowFollower` 落点仍未覆盖。
- 网络错误与非标准返回的兜底可以更全（`ImageGen.sanitize` 是起点）。
- `sleep` 动作没有随包内置帧，需要用户自己生成。

**体验**
- 设置各面板的信息密度与一致性可以整体过一遍。
- 没有做过系统性的深色模式与无障碍适配审查。
