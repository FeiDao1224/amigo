# 交接

新会话先读这份，再读根目录的 `ARCHITECTURE.md`（对象分工、必读坑、已知短板都在那里）。

## 现在停在哪（2026-10-17 接手时）

- 最新发布 **v1.0.0**（2026-07-20），`AppInfo.version` 也还是 1.0.0。
- v1.0.0 之后还有 6 个提交**没发版**，最重要的是 `b265d71`「拆出 AmigoCore，并加上情绪陪伴」（心情 / 亲密度 / 日记）和 `0d60d03`（隐身、清空、记忆解析的修复）。README 已经按情绪陪伴改写，但 Releases 里下载到的还是旧版。
- 下载页 `web/` 部署在 Vercel（`vercel.json`，`tools/sync-web-release.sh` 同步发布包）。
- 2026-09-12 之后一直没动过；2026-10-16 整理 GitHub 时被设为 Archive，10-17 接手时已 unarchive。仓库是**公开**的。
- 10-17 在 Mac 上 `swift build` 通过（首次全量约 90 秒）。

## 下一步候选

1. 把情绪陪伴版本发出去：改 `AppInfo.swift` 版本号 → 打 tag → CI 构建发 Release。
2. 空闲 CPU 约 10%（`PetView` 的 `TimelineView` 无条件 20fps 重绘 + 0.05s `cursorTimer`），桌面常驻应用这个值偏高。
3. `sleep` 动作没有随包内置帧。

## 常用命令

```bash
swift build                    # 迭代时的最便宜检查
swift run                      # 起 App（菜单栏爪印）
swift test                     # 表征测试
bash tools/package-app.sh      # 打包 dist/Amigo.app
```

## 踩过的坑

（新发现的追加在这里）
