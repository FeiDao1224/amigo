# Amigo激活服务（自托管）

市面常见做法的最小版：**15 天试用 + 首次联网激活 + 设备绑定 + 离线签名许可证 + 可吊销**。后台在你自己手里，零依赖，只用 Node 自带模块，数据存本地 JSON。

## 首次配置签名密钥

先生成一次 Ed25519 密钥对。私钥只在服务器保存，公钥会被写进正式 App 包：

```bash
node admin.js keygen --out ./data/license-private.pem
```

命令会输出 `AMIGO_LICENSE_PUBLIC_KEY=...`。这是可公开的公钥；**不要提交或发送** `license-private.pem`。

## 跑起来（Docker，推荐）
```bash
cd license-server
docker compose up -d --build          # 起服务，:8787，数据和私钥在 ./data
# 线上：把这目录扔你 VPS，docker compose up -d，前面套 Nginx/Caddy 上 HTTPS
```
不想用 Docker 也行（零依赖）：`node server.js`（可 `PORT=xxxx LICENSE_DB=/path/licenses.json node server.js`）。

## 发激活码（卖之前生成，发给买家）
Docker 里发码（数据落在挂载卷 /data）：
```bash
docker compose exec amigo-license node admin.js issue --plan pro --devices 1 --days 365
docker compose exec amigo-license node admin.js list
docker compose exec amigo-license node admin.js revoke LZ-XXXX-XXXX-XXXX-XXXX
```
不用 Docker：
```bash
node admin.js issue --plan pro --devices 1 --days 365   # 1 台设备、365 天
node admin.js issue --plan pro --devices 3              # 3 台、永久(不填 days)
node admin.js list                                      # 看所有码/已绑定设备
node admin.js revoke LZ-XXXX-XXXX-XXXX-XXXX              # 退款/盗用→吊销
```
- `days` 从**首次激活**当天起算；不填=永久。
- `devices`=该码最多能激活几台机器（超了会拒绝）。

## 打包正式收费版

`AMIGO_LICENSE_ENFORCED=1` 时，打包脚本会要求服务器地址和公钥齐全；缺少任一项会中止，避免误发锁死的收费包。

```bash
export AMIGO_LICENSE_ENFORCED=1
export AMIGO_LICENSE_SERVER=https://license.example.com
export AMIGO_LICENSE_PUBLIC_KEY='keygen 命令输出的值'
swift build -c release
bash tools/package-app.sh
```

开发时不设置这些变量，App 保持免费状态。线上必须使用 HTTPS。

## 接口
- `POST /api/activate {code, device}` → `{ok, plan, expiresAt, receipt}`；绑定设备并返回 Ed25519 签名收据。
- `POST /api/validate {code, device}` → `{ok, expiresAt, receipt}`；联网时可刷新收据并检查吊销。
- `receipt` 绑定设备和到期日，App 用内置公钥离线验签；断网不会锁定已激活用户。吊销会在下次联网复验时生效。

## 商业模型（已内置）
- 未激活：**免费试用 15 天**（App 端记安装日）。
- 试用到期且未激活：**锁定**（只能进设置去激活，其余不可用）。
- 激活后：永久 / 到 `expiresAt` 为止。
