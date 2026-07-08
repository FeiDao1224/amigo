// 灵崽激活服务（零依赖，Node 自带 http + 本地 JSON 存储）
// 跑：node server.js   （默认 :8787，可 PORT=xxxx node server.js）
// 发码：node admin.js issue --plan pro --devices 1 --days 365
const http = require("http");
const fs = require("fs");
const path = require("path");

const DB = process.env.LICENSE_DB || path.join(__dirname, "licenses.json");
const PORT = process.env.PORT || 8787;

const load = () => { try { return JSON.parse(fs.readFileSync(DB, "utf8")); } catch { return {}; } };
const save = (d) => fs.writeFileSync(DB, JSON.stringify(d, null, 2));
const body = (req) => new Promise((res) => { let b = ""; req.on("data", (c) => (b += c)); req.on("end", () => { try { res(JSON.parse(b || "{}")); } catch { res({}); } }); });
const json = (res, code, obj) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST") return json(res, 404, { ok: false, error: "not found" });
  const data = await body(req);
  const db = load();
  const code = String(data.code || "").trim().toUpperCase();
  const device = String(data.device || "").trim();

  const lic = db[code];
  if (!lic || lic.revoked) return json(res, 200, { ok: false, error: "激活码无效" });
  if (lic.expiresAt && Date.now() > lic.expiresAt) return json(res, 200, { ok: false, error: "激活码已过期" });

  if (req.url === "/api/activate") {
    if (!device) return json(res, 200, { ok: false, error: "缺少设备标识" });
    lic.devices = lic.devices || [];
    if (!lic.devices.includes(device)) {
      if (lic.devices.length >= (lic.maxDevices || 1)) return json(res, 200, { ok: false, error: "该激活码的设备数已用完" });
      lic.devices.push(device);
      lic.activatedAt = lic.activatedAt || Date.now();
      if (lic.days && !lic.expiresAt) lic.expiresAt = Date.now() + lic.days * 86400000; // 按激活起算
      save(db);
    }
    return json(res, 200, { ok: true, plan: lic.plan || "pro", expiresAt: lic.expiresAt || null });
  }

  if (req.url === "/api/validate") {
    const bound = (lic.devices || []).includes(device);
    return json(res, 200, { ok: bound, plan: lic.plan || "pro", expiresAt: lic.expiresAt || null, error: bound ? undefined : "此设备未激活" });
  }
  return json(res, 404, { ok: false, error: "not found" });
});

server.listen(PORT, () => console.log(`灵崽激活服务已启动 :${PORT}`));
