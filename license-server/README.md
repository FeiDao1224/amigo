# Amigo激活服务（自托管）

市面常见做法的最小版：**试用期 + 激活码 + 设备绑定 + 可吊销**，后台在你自己手里。零依赖，只用 Node 自带模块，数据存本地 `licenses.json`。

## 跑起来（Docker，推荐）
```bash
cd license-server
docker compose up -d --build          # 起服务，:8787，licenses.json 存在 ./data
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

## App 怎么连
把 App 里 `Sources/Amigo/License.swift` 的 `serverBase` 改成你的服务器地址（本机测试用 `http://localhost:8787`，上线换成 `https://你的域名`）。

## 接口
- `POST /api/activate {code, device}` → `{ok, plan, expiresAt}`；绑定设备，超期/超设备数/吊销都会 `ok:false + error`。
- `POST /api/validate {code, device}` → `{ok, expiresAt}`；App 启动时校验；**服务器连不上时 App 用本地缓存宽限**，不会误锁。

## 商业模型（已内置）
- 未激活：**免费试用 7 天**（App 端记安装日）。
- 试用到期且未激活：**锁定**（只能进设置去激活，其余不可用）。
- 激活后：永久 / 到 `expiresAt` 为止。
