// 激活码管理：node admin.js issue [--plan pro] [--devices 1] [--days 365]
//              node admin.js list
//              node admin.js revoke <CODE>
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const DB = path.join(__dirname, "licenses.json");
const load = () => { try { return JSON.parse(fs.readFileSync(DB, "utf8")); } catch { return {}; } };
const save = (d) => fs.writeFileSync(DB, JSON.stringify(d, null, 2));
const gen = () => {
  const s = crypto.randomBytes(8).toString("hex").toUpperCase();
  return `LZ-${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}`;
};

const [cmd, ...args] = process.argv.slice(2);
const get = (k, d) => { const i = args.indexOf("--" + k); return i >= 0 ? args[i + 1] : d; };
const db = load();

if (cmd === "issue") {
  const code = gen();
  db[code] = {
    plan: get("plan", "pro"),
    maxDevices: parseInt(get("devices", "1"), 10),
    days: get("days") ? parseInt(get("days"), 10) : null, // null=永久
    expiresAt: null,
    devices: [],
    revoked: false,
    createdAt: Date.now(),
  };
  save(db);
  console.log("新激活码：", code);
  console.log(db[code]);
} else if (cmd === "list") {
  console.log(JSON.stringify(db, null, 2));
} else if (cmd === "revoke") {
  const c = (args[0] || "").toUpperCase();
  if (db[c]) { db[c].revoked = true; save(db); console.log("已吊销", c); }
  else console.log("没找到", c);
} else {
  console.log("用法: node admin.js issue [--plan pro] [--devices 1] [--days 365] | list | revoke <CODE>");
}
