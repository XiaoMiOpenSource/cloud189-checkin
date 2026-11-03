// 账号加载（本地增强版，对变量名不敏感）
//
// 支持三种配置方式，按优先级依次尝试：
//   1) TY_ACCOUNTS=[{"userName":"a","password":"b"}]   JSON 数组（允许外层单引号）
//   2) .env 文件内的成对写法：TY_USERNAME_<n>=账号，紧随的 TY_<任意名>_<n>=密码
//      例：TY_USERNAME_1=138xxxx / TY_PASSWORD_1=xxx
//          TY_USERNAME_2=139xxxx / TY_GJEPZKBK_2=xxx
//   3) 进程环境变量 TY_USERNAME_<n> + TY_PASSWORD_<n>（GitHub Actions / 青龙面板场景）
const fs = require("fs");
const path = require("path");

const unquote = (value) => {
  const v = String(value == null ? "" : value).trim();
  if (v.length >= 2) {
    const first = v[0];
    const last = v[v.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return v.slice(1, -1);
    }
  }
  return v;
};

const isPlaceholder = (userName) =>
  /^(your_account|your_account_here|username|账号)$/i.test(String(userName || "").trim());

// ---- 方式 2：解析 .env 文件 ----
function loadFromDotEnvFile() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return [];

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  const found = [];

  for (let i = 0; i < lines.length; i += 1) {
    const m = lines[i].match(/^\s*TY_USERNAME_(\d+)\s*=\s*(.*)$/);
    if (!m) continue;

    const index = m[1];
    const userName = unquote(m[2].replace(/\s+#.*$/, ""));
    const passwordPattern = new RegExp(`^\\s*TY_[A-Za-z0-9]*_${index}\\s*=\\s*(.*)$`);

    let password = "";
    for (let j = i + 1; j < Math.min(i + 5, lines.length); j += 1) {
      const pm = lines[j].match(passwordPattern);
      if (pm) {
        password = unquote(pm[1].replace(/\s+#.*$/, ""));
        break;
      }
    }
    if (userName && password) {
      found.push({ userName, password });
    }
  }
  return found;
}

// ---- 方式 0：SSON Cookie（优先级最高；用于密码登录被风控/设备校验拦截的场景）----
// TY_SSON        = 浏览器 .189.cn 域下的 SSON cookie 值
// TY_SSON_LABEL  = 可选，日志里显示的账号标识（默认 sson_account）
function loadFromSsonCookie() {
  const raw = (process.env.TY_SSON || process.env.SSON || "").trim();
  if (!raw) return [];
  const label = (process.env.TY_SSON_LABEL || "sson_account").trim();
  const value = unquote(raw).replace(/^SSON\s*=\s*/i, "");
  if (!value) return [];
  return [{ userName: label, password: "", ssonCookie: value }];
}

// ---- 方式 0b：整条浏览器 Cookie（绕过设备校验的另一条路）----
// TY_COOKIE = 形如 "COOKIE_LOGIN_USER=xxx; JSESSIONID=yyy"
// 实现方式：把整条 cookie 拼到 SDK 的 SSON cookie 头里（SDK 固定发 "SSON=<值>"）
function loadFromRawCookie() {
  const raw = (process.env.TY_COOKIE || "").trim();
  if (!raw) return [];
  const label = (process.env.TY_COOKIE_LABEL || "cookie_account").trim();
  const value = unquote(raw);
  if (!value) return [];
  return [{ userName: label, password: "", ssonCookie: `x; ${value}` }];
}

// ---- 方式 3：进程环境变量 ----
function loadFromProcessEnv() {
  const found = [];
  for (let index = 1; index <= 50; index += 1) {
    const userName = (process.env[`TY_USERNAME_${index}`] || "").trim();
    const password = (process.env[`TY_PASSWORD_${index}`] || "").trim();
    if (userName && password) found.push({ userName, password });
  }
  return found;
}

// ---- 方式 1：JSON ----
function loadFromJson() {
  const raw = (process.env.TY_ACCOUNTS || "").trim();
  if (!raw) return [];
  const text = raw.replace(/^'+/, "").replace(/'+$/, "");
  const parsed = JSON.parse(text);
  if (!Array.isArray(parsed)) {
    throw new Error("TY_ACCOUNTS 必须是 JSON 数组");
  }
  return parsed
    .filter((item) => item && item.userName && item.password)
    .map((item) => ({
      userName: String(item.userName).trim(),
      password: String(item.password),
    }));
}

function loadAccounts() {
  const candidates = [
    loadFromSsonCookie(),
    loadFromRawCookie(),
    loadFromJson(),
    loadFromDotEnvFile(),
    loadFromProcessEnv(),
  ];
  for (const list of candidates) {
    const cleaned = list.filter(
      (acc) => acc.userName && (acc.password || acc.ssonCookie) && !isPlaceholder(acc.userName)
    );
    if (cleaned.length > 0) return cleaned;
  }
  return [];
}

const accounts = loadAccounts();

if (accounts.length === 0) {
  console.error(
    "[配置错误] 未读取到任何有效账号。请执行 setup.ps1 配置，或手动编辑 .env：" +
      "\n  方式一：TY_USERNAME_1=你的账号 / TY_PASSWORD_1=你的密码（支持 _2、_3 ...）" +
      "\n  方式二：TY_ACCOUNTS=[{\"userName\":\"账号\",\"password\":\"密码\"}]" +
      "\n  方式三：TY_SSON=浏览器里的 SSON cookie 值（绕过设备校验）"
  );
  process.exit(1);
}

module.exports = accounts;
