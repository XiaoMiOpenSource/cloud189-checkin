# 本地部署说明（Windows）

基于 [wes-lin/Cloud189Checkin](https://github.com/wes-lin/Cloud189Checkin) 的天翼云盘自动签到，已在本机完成依赖安装、账号配置脚本、一键运行脚本与计划任务脚本。

## 一、三分钟上手

```powershell
cd Cloud189Checkin

# 1) 录入账号（密码掩码输入，支持多账号，可保留已有推送配置）
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1

# 2) 立即试跑
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1

# 3) 注册每天自动签到（默认 10:35）
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Time 10:35
```

删除计划任务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Remove
```

## 二、本地文件说明

| 文件 | 用途 |
| --- | --- |
| `.env` | 账号与推送配置（敏感，`.gitignore` 已忽略） |
| `.env.example` | 配置模板，供手动填写参考 |
| `setup.ps1` | 交互式配置：多账号录入、密码掩码、自动保留推送配置 |
| `run.ps1` | 一键运行：占位检查、依赖自检、UTF-8 输出、写入运行历史 |
| `install-task.ps1` | 注册 / 删除 Windows 每日计划任务 |
| `.token/` | 登录态缓存，复用后可减少登录次数 |
| `.logs/run-history.log` | 每次运行的开始时间与结果（由 `run.ps1` 追加） |

## 三、账号配置方式

`.env` 中支持两种写法，任选其一：

**方式一（推荐，成对写）**

```dotenv
TY_USERNAME_1=你的账号
TY_PASSWORD_1=你的密码
TY_USERNAME_2=第二个账号
TY_PASSWORD_2=第二个密码
```

账号变量必须是 `TY_USERNAME_<序号>`；密码变量只需以 `_<同一序号>` 结尾，前缀随意，因此上游文档里的 `TY_PASSWORD_1` 这类命名同样可用：

```dotenv
TY_USERNAME_9=你的账号
TY_PASSWORD_1=你的密码
```

密码含 `#`、`$`、空格等字符时用引号包裹，例如 `TY_PASSWORD_1='ab#12$cd'`。

**方式二（JSON，覆盖方式一）**

```dotenv
TY_ACCOUNTS=[{"userName":"账号1","password":"密码1"},{"userName":"账号2","password":"密码2"}]
```

## 四、相比上游所做的本地适配

| 位置 | 改动 | 原因 |
| --- | --- | --- |
| `accounts.js` | 重写账号加载：支持 `.env` 成对解析（对密码变量名不敏感）、`TY_ACCOUNTS` JSON、进程环境变量三种来源；过滤模板占位值；无有效账号时打印明确提示并退出 | 上游只认 `TY_PASSWORD_<n>`，与 README 中 `TY_PASSWORD_1` 的写法不一致，容易出现“填了账号却提示没有账号” |
| `src/app.js` | 单个账号失败不再中断其他账号；登录失败的账号计入统计；有失败时退出码为 1；已签到时提示“今日已签到” | 上游脚本任何异常都会静默 `exit 0`，计划任务无法发现失败 |
| `src/app.js` | 容量汇总单独 try/catch | 避免汇总接口异常吞掉整体结果 |
| `.env` | 改为带注释的完整配置模板 | 上游 `.env` 是示例值，直接运行会拿占位账号去登录 |
| `.gitignore` | 追加 `.env`、`.env.local` | 上游仓库 `.gitignore` 未忽略 `.env`，极易误提交明文密码 |
| git 索引 | 执行 `git rm --cached .env`（本地文件保留） | 上游把 `.env` 提交进了仓库，只加 `.gitignore` 不生效，这样处理后凭据不会再进入版本库 |
| `package.json` 依赖 | 已执行 `npm install`（243 个包） | 开箱即用 |

## 五、验证记录

- 依赖安装：`npm install` 成功（Node.js v24.22.2）
- 网络连通：`cloud.189.cn` / `open.e.189.cn` / `api.cloud.189.cn` 均可直连（无需代理）
- 端到端链路：用无效测试账号运行，服务端返回 `账户名或密码错误`，说明 RSA 加密、登录参数、`getSessionForPC`、签到请求链路均正常，只差真实凭据
- 退出码：登录失败时进程退出码为 1（上游恒为 0）

## 六、常见问题

**提示“设备ID不存在 / 需要二次设备校验”**
天翼账号开启了设备锁。先在 [天翼云盘网页版](https://cloud.189.cn) 登录，进入安全设置关闭设备锁，再重新运行。

**登录要求验证码**
上游脚本不支持验证码。若当前网络环境触发风控验证码，先在浏览器登录一次该账号（同一出口 IP），再立即运行脚本，通常可跳过。

**代理 / 网络**
脚本直连 `*.189.cn`。如果本机全局代理导致访问异常，请在 `run.ps1` 中设置 `$env:NO_PROXY='189.cn,cloud.189.cn,open.e.189.cn,api.cloud.189.cn'`（PowerShell 5.1 已实测直连可用，一般无需改动）。

**计划任务没执行**
`install-task.ps1` 默认注册为“登录后运行”。需要未登录也执行时，改用带凭据注册：

```powershell
schtasks /Create /TN Cloud189Checkin /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"$PWD\run.ps1\"" /SC DAILY /ST 10:35 /RU <用户名> /RP <密码> /F
```

**查看日志**
`run.ps1` 会在 `.logs/run-history.log` 追加每次运行结果；脚本自身的过程日志在 `.logs/<账号>.log`（每次运行结束后自动清理，推送内容已包含完整日志）。

**推送**
`.env` 中任填一个通道即可：`SENDKEY`（Server 酱）、`TELEGRAM_BOT_TOKEN`+`TELEGRAM_CHAT_ID`、`WECOM_BOT_KEY`+`WECOM_BOT_TELPHONE`、`WX_PUSHER_APP_TOKEN`+`WX_PUSHER_UID`、`PUSH_PLUS_TOKEN`、`SHOWDOC_KEY`、`BARK_KEY`、`WPUSH_APIKEY`。留空则不推送。

## 七、升级上游代码

本地对 `accounts.js`、`src/app.js`、`.env`、`.gitignore` 有改动，直接 `git pull` 会冲突。升级前先备份，或按需只同步 `node_modules/cloud189-sdk` 版本：

```powershell
Copy-Item .env .env.bak
git stash
git pull
git stash pop
```

如冲突只涉及上述四个文件，按本文件第四节说明重新套用改动即可。

---

# 附：GitHub Actions 部署结果（2026-11-02 验证通过）

## 最终采用的方案

云端自动签到，仓库 `XiaoMiOpenSource/Cloud189Checkin`（fork 自上游）。

| 项目 | 配置 |
| --- | --- |
| 仓库 | https://github.com/XiaoMiOpenSource/Cloud189Checkin |
| Actions 开关 | `enabled: true`, `allowed_actions: all` |
| Workflow 权限 | `default_workflow_permissions: write`（保活提交需要） |
| environment | `user`（无保护规则，无审批人） |
| secrets | `TY_USERNAME_1`、`TY_PASSWORD_1`（environment 级） |
| workflow | `.github/workflows/run.yml` → `active` |
| 定时 | `cron: 35 2 * * *` = 北京时间每天 10:35（自带 0–300 秒随机延迟） |
| 首次运行 | 需在 run 页面点一次「Approve and run」（fork 仓库的安全机制） |

## 关键结论：设备锁是唯一堵点

排查过程中四种方式的结果：

| 尝试 | 结果 |
| --- | --- |
| 本机密码登录 | ❌ `设备ID不存在，需要二次设备校验` |
| GitHub 境外 IP 密码登录 | ❌ 同上 |
| 浏览器 `COOKIE_LOGIN_USER` + `JSESSIONID` 免密 | ❌ 服务端返回登录页 HTML，`Can not get session` |
| SSON 票据 | ⚠️ 浏览器 cookie 库中为 `v20` App-Bound 加密，离线无法解密；DevTools 中该域无有效票据 |

**关闭天翼设备锁（登录保护）后，本机与 GitHub 两端立即同时通过**，说明该错误与出口 IP 无关，纯粹是账号级的未登记设备校验。

关闭入口：
- 手机 APP：天翼云盘 → 我的 → 设置 → 账号与安全 → 设备锁 / 登录保护 → 关闭
- 网页版：cloud.189.cn → 右上角头像 → 账号与安全 / 安全中心 → 设备管理 → 关闭登录保护

## 验证日志（两端一致）

本机：
```
[INFO] 133****1300: 开始执行（账号密码登录）
[INFO] 133****1300: 个人签到任务: 今日已签到（重复执行不增加容量）
[INFO] 133****1300: 执行完毕, 耗时 1.07 秒
[INFO] 133****1300: 个人容量：⬆️  0.00M/2078.95G 家庭容量：⬆️  0.00M/2078.00G
```

GitHub Actions（run 41458517622，14.51 秒）：
```
[INFO] 133****1300: 开始执行（账号密码登录）
[INFO] 133****1300: 个人签到任务: 今日已签到（重复执行不增加容量）
[INFO] 133****1300: 个人容量：⬆️  0.00M/2078.95G 家庭容量：⬆️  0.00M/2078.00G
```

## 补充的代码能力（已推到 fork）

`accounts.js` / `src/app.js` 支持三种登录来源，按优先级：

1. `TY_SSON` —— SSON Cookie 票据
2. `TY_COOKIE` —— 整条浏览器 Cookie（`COOKIE_LOGIN_USER=...; JSESSIONID=...`）
3. `TY_USERNAME_n` / `TY_PASSWORD_n` —— 账号密码（当前生效）

同时保留本地增强：单账号失败不中断其他账号、失败时退出码 1、已签到明确提示。

## 维护要点

- **天翼改了登录策略或再次开启设备锁** → Actions 报 `设备ID不存在`，重新关闭设备锁即可
- **fork 仓库 60 天无活动会停用定时任务** → 上游 `Keep Running` 步骤每天空提交保活，需保持 Workflow 权限为 write
- **密码轮换** → 更新 environment secret `TY_PASSWORD_1`
- **查看运行结果**：仓库 Actions 页面，或 `gh run list --repo XiaoMiOpenSource/Cloud189Checkin`

## Server 酱推送（2026-11-02 配置并验证）

| 项 | 值 |
| --- | --- |
| environment secret | `SENDKEY`（environment `user`） |
| 首次验证 | 本地与 GitHub 均输出 `push: ServerChan推送成功` |
| 消息标题 | `天翼云盘自动签到任务` |
| 消息正文 | 完整运行日志（含容量增量和耗时） |

**必需的前置修复**：上游 `src/app.js` 里 `push(...)` 未 await，进程退出会切断未完成的 HTTP 请求，导致推送静默丢失。已改为 `await push(...)`，并把 `src/push/index.js` 各通道改为返回 Promise + `Promise.all` 聚合（单通道失败不影响其他）。

若改回密码或重设推送：`gh secret set SENDKEY --env user --repo XiaoMiOpenSource/Cloud189Checkin`。

其他可用通道（填对应变量即可，代码均已实现）：`TELEGRAM_BOT_TOKEN`+`TELEGRAM_CHAT_ID`、`WECOM_BOT_KEY`+`WECOM_BOT_TELPHONE`、`WX_PUSHER_APP_TOKEN`+`WX_PUSHER_UID`、`PUSH_PLUS_TOKEN`、`SHOWDOC_KEY`、`BARK_KEY`、`WPUSH_APIKEY`。
