# Amigo · 交接文档（给评审 / 优化的 AI 读）

> 目的：让另一个 AI 或工程师**零上下文快速上手**这个项目，做代码评审、界面/体验优化。
> 读完这份文档 + 扫一遍 `Sources/Amigo/` 就能动手。有疑问以**代码为准**（注释是中文，风格偏紧凑）。
> 最新版本 tag：`v0.1.7`。仓库：https://github.com/FeiDao1224/amigo （私有）

---

## 0. 30 秒速览

- **是什么**：原生 macOS 桌面宠物（desktop pet）。一只常驻桌面、被你真实行为驱动、能接你自己大模型聊天/生成形象与动作的“桌搭子”。
- **技术栈**：Swift 6.x + AppKit + SwiftUI，**SwiftPM 包（无 Xcode 工程）**，目标 macOS 13+。单一可执行 target = `Amigo`。
- **规模**：`Sources/Amigo/` 共 **25 个 .swift、约 3591 行**。
- **跑起来**：项目根目录 `swift run`（产物在 `.build/arm64-apple-macosx/debug/Amigo`）。菜单栏出现爪印图标、桌面右下角出现宠物。
- **数据**：全部只在本机 `~/Library/Application Support/Amigo/`（含 API Key）。不上传任何服务器。
- **商业**：开发环境默认免费；正式包可在打包时注入许可证服务器和公钥，首次联网激活后离线验签使用。

---

## 1. 构建 / 运行 / 打包 / CI

```bash
# 开发
swift build                 # 编译（debug）
swift run                   # 编译并运行
swift build -c release      # release

# 打包成 .app（ad-hoc 自签，无需 Apple 账号/公证）
bash tools/package-app.sh   # 产出 dist/Amigo.app

# 出正式包（走 CI）
git tag vX.Y.Z && git push origin vX.Y.Z
#   → .github/workflows/build.yml 在 macos-15 上构建+打包+发 GitHub Release(Amigo.zip)
```

- **可执行名是 `Amigo`（不是 Lingzai）**。曾有历史坑：改名后 `.build/debug/Lingzai` 残留会被误跑；VM 时钟跳变会让 `swift build` 变 no-op。**行为不更新时先 `rm -rf .build` 干净构建，或直接 `swift run`。**
- `tools/`：`package-app.sh`（打包+自签+写 Info.plist）、`make-icon.swift`（生成图标）、`dewhite.swift`/`pixelize.swift`（一次性图像工具，非运行时依赖）。

---

## 2. 顶层结构

```
Sources/Amigo/        全部 App 源码（下面详述）
Assets/pets/          打包随附的内置形象 PNG + 动作帧（penguin / cow）
tools/                打包脚本、图标脚本
license-server/       自托管激活服务（Node 零依赖 + Docker，可选）
Docs/                 动画系统说明
.github/workflows/    build.yml（CI）
AppIcon.icns          App 图标
dist/                 打包产物（gitignore）
pet-raw/              原始素材（非运行时）
```

---

## 3. 运行期架构（数据流）

单进程、菜单栏 accessory app。三个核心对象：

- **`AppState`（AppState.swift）** — `ObservableObject`，持有 `config`（唯一数据源）、memories，被**设置窗**观察。所有“不高频”的状态/业务方法在这（模型管理、形象/动作、激活、记忆、导入等）。
- **`PetRuntime`（PetRuntime.swift）** — `ObservableObject`，只被**宠物窗**观察的**高频动画状态**（当前帧、fps、朝向、气泡、拖动态…）。刻意和 AppState 分开，避免高频重绘拖累设置窗。
- **`AppDelegate`（AppDelegate.swift，最核心）** — 组装一切：建菜单栏、建宠物窗 `PetPanel`、装 `BehaviorEngine` / `ChatSession`、跑 `cursorTimer`（0.05s）驱动点击穿透+行为动作、处理拖动、点击派发、开设置/聊天/引导窗、Dock 策略。**想理解交互逻辑先读它。**

数据流：`config`(磁盘 JSON) → `AppState` → 回调闭包喂给 `PetRuntime` / 引擎 → SwiftUI 视图渲染。用户操作 → AppState 方法改 config → `persist()` 落盘 → 通过 `onXxxChanged` 闭包通知 runtime 刷新。

---

## 4. 文件地图（按子系统分组）

### 入口 / 组装
- `main.swift`(6) — 启动 NSApplication + AppDelegate。
- `AppDelegate.swift`(403) — **见上，交互与窗口管理中枢**。内含 `PetPanel: NSPanel`（透明置顶点击穿透宠物窗）。

### 状态 / 数据模型
- `AppState.swift`(388) — 业务/状态中枢。
- `Models.swift`(154) — `Config`（全部持久化字段，见 §5）、`Provider`、`CustomPet`、`CustomAction`、`CardData`（人设）、`ConfigStore`（**容错解码**，见 §7）、`Provider.fromImport`（从 ccswitch:// / Codex 配置解析 provider）。
- `Memory.swift`(30) — 长期记忆模型 + `MemoryStore`。
- `PetRuntime.swift` — 高频动画状态 + `showAction`（按帧数自适应 fps）+ `speak` / `nudge` 的 LLM 调用。

### 宠物窗 / 动画 / 交互
- `PetView.swift` — 宠物 SwiftUI 视图：气泡/输入框 + 帧动画(`TimelineView`)+ 点击/双击/长按/拖动手势。
- `Components.swift`(191) — `VisualEffectView`(毛玻璃)、`PetMotion`/`MoveMotion`(程序位移动画兜底)、气泡形状、`SectionHeader` 等。
- `BehaviorEngine.swift`(60) — 30s 定时的“主动督促”引擎（久坐/熬夜/离开回来/专注），读系统闲置时长，冒泡。**注意：这只管主动冒泡；拖动/点击穿透/切动作逻辑在 AppDelegate。**

### 形象 / 动作生成（重点、易出问题）
- `SpriteGen.swift`(227) — **动作帧生成管线**：`PetAnimAction`(6 个内置动作 + prompt + `loopSeconds`) → 调 ImageGen 生成一张 **3×3=9 帧** 网格图 → 切 9 帧 → `removeWhite`(去白底) → `register`(**水平按重心对齐 + 底部对齐**，防横晃) → 存 `generated/<形象>/<动作>/frame-0..8.png`。
- `ImageGen.swift`(119) — OpenAI 兼容 `/images/edits`（模型 `gpt-image-2`），**multipart 优先、JSON `image_urls` 兜底**。**生图是硬门槛：只有支持图像编辑的中转站能用**（Claude 系不行）。
- `Pixelizer.swift`(126) — 无模型时的本地像素化（Vision 抠图 `VNGenerateForegroundInstanceMaskRequest` + 降色）。
- `PetImages.swift`(49) — 形象静态图加载 + `installDefaults`（首启把打包内置形象+动作帧拷到本机）。

### 聊天 / 记忆
- `ChatSession.swift`(102) — 多轮对话 + `ChatStore`(chat.json) + 后台从对话抽取长期记忆。
- `ChatView.swift`(74) — 独立聊天窗（毛玻璃）。
- `LLM.swift`(45) — OpenAI 兼容 `/chat/completions` 封装（**每次请求经 `Compliance.inject` 注入合规红线**）。
- `SystemInfo.swift`(40) — 实时状态（时间/内存/前台 app）注入 system prompt；前台 app 部分受 `senseFrontApp` 开关控制。

### 设置界面（SwiftUI）
- `SettingsView.swift`(356) — 设置主壳：左侧栏（通用/模型/形象/性格/交互/关于）+ 右侧内容路由。窗口 800×520，侧栏项等高（cap 74）。
- `SettingsPanes.swift`(246) — `ModelPane`(模型手填)、`PersonaPane`(名字+人设)、`MemoryPane`(记忆/隐私)。
- `PetSettingsCards.swift`(423) — 形象页的卡片：`CharacterPicker`(当前形象置顶、名字跟随人设、可删自定义)、`CharacterCard`、`ActionRow`/`ActionPreview`(动作预览，fps 按帧数算)、`NewActionCard`、`ProPane`(激活，免费版隐藏)、`CustomPetCard`(自定义形象生成，拟人化/像素程度选项前置)。
- `OnboardingView.swift`(44) — 首启引导。

### 系统集成 / 其它
- `License.swift` — Ed25519 离线许可证验签 + 首次联网激活/在线复验；正式配置从打包 Info.plist 或环境变量读取。
- `Compliance.swift`(58) — **内容合规红线**：文本红线(`inject`)、图像版权红线(`imageClause`)、用户输入初筛(`screenImagePrompt`)。
- `LaunchAtLogin.swift`(38) — 开机启动（SMAppService）。

---

## 5. 数据模型 & 存储

**存储位置（全部本机）**：`~/Library/Application Support/Amigo/`
- `config.json` — 见下 `Config`（不含 API Key；模型 Key 存于 macOS Keychain）。
- `memories.json` / `chat.json` — 记忆 / 聊天。
- `pets/<形象>.png` — 形象静态图；`pets/generated/<形象>/<动作>/frame-N.png` — 动作帧。

**`Config` 全字段**（改字段务必看 §7 的容错解码，别踩数据丢失坑）：
```
providers[], activeId, dockVisible, proactive, proactiveLLM,
petX/petY, stealth, character(默认 penguin), customPets[],
licenseCode/licenseActivated/licenseExpiresAt/licenseReceipt/deviceId/installedAt,
activeAction, behaviorDriven, mapSlow/mapFast/mapChat,
customActions[], personas{形象→CardData},
clickLeft/clickDouble/clickLong/clickRight,
senseFrontApp, autoMemory, onboarded, seededDoubleClickChat
```

**形象系统**：内置 `penguin`(咕咕嘎嘎，默认) + `cow`(草地牛)；用户自定义存 `customPets`（**追加不覆盖**）。选择器里“当前形象置顶”，卡片名字**跟随 `personas[形象].name`**（没设人设名就用默认名）。

---

## 6. 关键交互实现（评审重点看这几处）

- **透明点击穿透宠物窗**：`AppDelegate.cursorTick()`（0.05s 定时）用 `petGrabRect`（带**滞回 hysteresis**，防边缘抖动）判断鼠标是否在宠物上，只在变化时切 `panel.ignoresMouseEvents`。**这是“拖不动/抓不住”类 bug 的高发区。**
- **拖动**：`dragTick()` 用绝对鼠标坐标移动 `NSPanel`；平滑测速 → `mapSlow`(走)/`mapFast`(跑)；`dx` 定 `facingLeft`(水平翻转)。
- **行为驱动切动作**：`updateBehaviorAction()`：对话/等回复→phone；拖动→走/跑；前台有 app→work；空→默认动作。
- **动作播放帧率**：`PetRuntime.showAction` 里 `fps = min(20, 帧数 / loopSeconds)`。**这是“播放太快”的修复点**——帧率按实际帧数自适应，4/9/16 帧都同循环时长。`PetAnimAction.loopSeconds` 是每个动作节奏的唯一调节点。
- **帧对齐**：`SpriteGen.register()` 水平以**重心(centroidX)**为锚、底部对齐。**这是“动作横晃”的修复点**（原来用包围盒中心，胳膊摆动会带偏）。

---

## 7. 必读坑 & 约定（省你踩雷）

1. **改 `Config` 字段绝不能想当然**：Swift 合成 Codable 缺字段会**整体解码失败**。`ConfigStore.load()` 已做**容错合并**（strict 失败→把磁盘值 merge 到默认配置再解），所以加字段安全；但**别把这段容错删了**，否则升级会丢用户模型配置 / 形象 / 性格。旧版明文 API Key 会在启动时迁移到 macOS Keychain。
2. **命名**：产品/包/数据目录/源码目录全是 **Amigo**。全代码无 lingzai 残留，**唯一例外**是 `AppState.migrateDataDir()`——把旧 `~/Library/Application Support/Lingzai` 一次性搬到 `Amigo`，**不能删**。
3. **生图能力是硬门槛**：动作/自定义形象生成依赖中转站的 `gpt-image-2 /images/edits`。**Claude/Anthropic key 生不了图**；官方 OpenAI key 要看权限/模型名。评审“为什么某些人生不了动作”多半是这个。
4. **帧数历史**：4 帧(初版)→16 帧(太抽)→现 **9 帧(3×3)**。旧形象里可能残留 4/16 帧，`loadFrames` 读到缺帧为止、fps 自适应，**混着也能播**；要看新效果需“重生成”。
5. **两个 ObservableObject 分工**：高频动画状态放 `PetRuntime`、其余放 `AppState`，别混，否则设置窗会被高频重绘拖慢。
6. **合规红线**：所有 LLM 文本请求走 `LLM.chat` → 自动 `Compliance.inject`；所有生图走 `ImageGen.edit` → 自动加 `imageClause`。新增生成入口记得别绕过。
7. **收费包不能只改一个 Bool**：必须在打包时同时提供 `AMIGO_LICENSE_ENFORCED=1`、服务器 HTTPS 地址和 Ed25519 公钥。私钥只留在 `license-server` 的数据卷，首次激活返回的签名收据让 App 离线工作。

---

## 8. 已知短板 / 建议优化方向（给评审 AI 的切入点）

**架构 / 可维护性**
- `AppDelegate.swift`(403) 职责过重（窗口+交互+定时器+菜单全塞一起），可拆分。
- 逻辑与 AppKit 深度耦合，**无平台抽象层**——将来跨平台(Win)是重写外壳级工程（见 README 讨论/对话记录）。
- `cursorTimer` 每 0.05s 轮询驱动点击穿透+行为判定，可评估是否用事件监听替代以降功耗。

**生成质量（体验痛点）**
- 9 帧网格生成偶发“帧画崩/倒置(脚在头顶)”，目前靠 prompt 强约束 + 重生成兜底，**缺程序级坏帧检测/剔除**——可考虑生成后校验（如各帧包围盒一致性、朝向检测）自动丢弃离群帧。
- `register()` 的重心对齐对“底座稳定”类动作好，但对大幅位移动作可能仍偏；可评估“底部带重心”或光流对齐。
- 相似度(“传神”)靠提示词，无二次校验。

**界面 / 体验**
- 设置各面板信息密度/一致性可整体过一遍（SwiftUI）。
- 首启引导、空态、错误提示（toast）可打磨。
- 无深浅色/无障碍系统性适配审查。

**健壮性**
- 网络错误/超时/中转站各种非标准返回的兜底可以更全（`ImageGen.sanitize` 是起点）。
- 当前 SwiftPM 工具链未配置测试框架；核心可测逻辑（`Compliance`、`ConfigStore` 容错、`SpriteGen` 切帧/对齐、`Provider.fromImport`）仍应在测试环境就绪后补齐覆盖。

**产品**
- “读本机 CC Switch / Codex 配置一键导入”只有 `Provider.fromImport` 雏形，未做自动扫描 + 生图能力标注（见对话记录里的方案讨论）。
- 激活/试用逻辑(`License`/`ProPane`)默认关闭，开收费前需端到端复测。

---

## 9. 评审时的建议动作

1. 先 `swift run` 跑起来，把玩宠物（拖动/双击开对话/右键菜单）+ 逛一遍设置各页，对照 §6 找体验问题。
2. 精读 `AppDelegate.swift` + `AppState.swift` + `SpriteGen.swift`（交互、状态、生成三条主线）。
3. 按 §8 挑方向出评审意见；改动前留意 §7 的坑。
4. 纯逻辑处优先补测试再重构。

> 环境限制提醒：当前仓库在 macOS 上开发，`swift build`/运行/截图只能在 Mac 验证；Windows 相关是纯讨论、无代码。
