#requires -Version 5.1
<#
.SYNOPSIS
    把 Cloud189Checkin 切到 GitHub Actions 自动签到（fork + 权限 + 环境 + Secrets + 触发）。

.DESCRIPTION
    前置条件：已安装 GitHub CLI 并完成认证（gh auth login）。
    脚本只操作你自己的 fork，不会修改上游仓库。

.PARAMETER AccountsJson
    天翼账号 JSON，例如：
    '[{"userName":"13800000000","password":"pwd"}]'
    不传则交互式录入（密码掩码）。

.PARAMETER SkipRun
    配置完成后不触发首次运行。

.PARAMETER UpstreamRepo
    上游仓库，默认 wes-lin/Cloud189Checkin。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\github-setup.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\github-setup.ps1 -AccountsJson '[{"userName":"a","password":"b"}]'
#>

param(
    [string]$AccountsJson = '',
    [string]$AccountsFile = '',
    [switch]$SkipRun,
    [string]$UpstreamRepo = 'wes-lin/Cloud189Checkin'
)

$ErrorActionPreference = 'Stop'

# 优先从文件读取账号 JSON（避免命令行传 JSON 时引号被剥掉）
if (-not [string]::IsNullOrWhiteSpace($AccountsFile)) {
    if (-not (Test-Path $AccountsFile)) {
        Write-Host "[错误] 账号文件不存在: $AccountsFile" -ForegroundColor Red
        exit 1
    }
    $AccountsJson = (Get-Content -Raw -Encoding UTF8 $AccountsFile).Trim()
}

# ---- 全局设置：GitHub 访问走本机代理 ----
$env:HTTPS_PROXY = 'http://127.0.0.1:7897'
$env:HTTP_PROXY = 'http://127.0.0.1:7897'
$env:GH_NO_UPDATE_NOTIFIER = '1'

function Find-Gh {
    $candidates = @(
        'C:\Program Files\GitHub CLI\gh.exe',
        (Join-Path $env:LOCALAPPDATA 'GitHubCLI\gh.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '未找到 gh.exe，请先安装 GitHub CLI'
}

$gh = Find-Gh

function Gh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgList)
    # 原生命令写 stderr 时，Stop 模式会把正常的“失败返回”升级成终止错误，这里局部降级
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = 0
    try {
        $out = & $gh @ArgList 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    return @{ code = $code; text = ($out | Out-String).Trim() }
}

function Api {
    param([string]$Method, [string]$Path, [hashtable]$Fields)
    $argv = @('api', '--method', $Method, $Path)
    if ($Fields) {
        foreach ($k in $Fields.Keys) {
            $v = $Fields[$k]
            if ($v -is [bool]) { $argv += @('-F', "$k=$($v.ToString().ToLower())") }
            else { $argv += @('-f', "$k=$v") }
        }
    }
    return Gh @argv
}

Write-Host ''
Write-Host '=== 天翼云盘 · 切换到 GitHub Actions 自动签到 ===' -ForegroundColor Cyan
Write-Host ''

# ---- 1. 认证检查 ----
$auth = Gh 'auth' 'status'
if ($auth.code -ne 0) {
    Write-Host '[错误] GitHub CLI 未认证。请先在你的终端执行：' -ForegroundColor Red
    Write-Host '  & "C:\Program Files\GitHub CLI\gh.exe" auth login' -ForegroundColor Yellow
    Write-Host '  选择 GitHub.com -> HTTPS -> Login with a web browser，浏览器里授权即可' -ForegroundColor Yellow
    exit 1
}
Write-Host '[1/8] gh 已认证' -ForegroundColor Green

$meRaw = Gh 'api' 'user'
if ($meRaw.code -ne 0) { Write-Host "[错误] 无法读取账号信息: $($meRaw.text)" -ForegroundColor Red; exit 1 }
$me = $meRaw.text | ConvertFrom-Json
$owner = $me.login
$fork = "$owner/Cloud189Checkin"
Write-Host "      账号: $owner   目标仓库: $fork"

# ---- 2. Fork ----
Write-Host '[2/8] 检查 / 创建 fork...' -ForegroundColor Green
$existing = Gh 'repo' 'view' $fork '--json' 'name'
if ($existing.code -eq 0) {
    Write-Host "      已存在 fork: $fork"
} else {
    $forkResult = Gh 'repo' 'fork' $UpstreamRepo '--clone=false'
    if ($forkResult.code -ne 0) {
        Write-Host "[错误] fork 失败: $($forkResult.text)" -ForegroundColor Red
        exit 1
    }
    Write-Host "      已创建 fork: $fork"
}

# 等待 fork 可访问（GitHub 侧异步）
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 3
    $check = Gh 'repo' 'view' $fork '--json' 'defaultBranchRef'
    if ($check.code -eq 0 -and $check.text -match 'main') { $ready = $true; break }
}
if (-not $ready) { Write-Host '[警告] fork 尚未完全就绪，继续执行' -ForegroundColor Yellow }

# ---- 3. Actions 总开关 ----
Write-Host '[3/8] 启用该仓库的 Actions...' -ForegroundColor Green
$r = Api 'PUT' "/repos/$fork/actions/permissions" @{ enabled = $true; allowed_actions = 'all' }
if ($r.code -ne 0) { Write-Host "      [警告] $($r.text)" -ForegroundColor Yellow } else { Write-Host '      OK' }

# ---- 4. Workflow 读写权限（Keep Running 需要 push 权限）----
Write-Host '[4/8] 设置 Workflow 权限为 Read and write...' -ForegroundColor Green
$r = Api 'PUT' "/repos/$fork/actions/permissions/workflow" @{ default_workflow_permissions = 'write' }
if ($r.code -ne 0) { Write-Host "      [警告] $($r.text)" -ForegroundColor Yellow } else { Write-Host '      OK' }

# ---- 5. 创建 environment: user ----
Write-Host '[5/8] 创建 environment: user...' -ForegroundColor Green
$r = Api 'PUT' "/repos/$fork/environments/user" $null
if ($r.code -ne 0) { Write-Host "      [警告] $($r.text)" -ForegroundColor Yellow } else { Write-Host '      OK' }

# ---- 6. 写入账号到 environment secret ----
Write-Host '[6/8] 写入账号 TY_ACCOUNTS...' -ForegroundColor Green
if ([string]::IsNullOrWhiteSpace($AccountsJson)) {
    Write-Host '  请输入天翼账号（密码掩码显示，不会回显）：' -ForegroundColor Yellow
    $list = @()
    $idx = 1
    while ($true) {
        $userName = Read-Host "  账号 #$idx（直接回车结束）"
        if ([string]::IsNullOrWhiteSpace($userName)) { break }
        $secure = Read-Host "  密码 #$idx" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        if ([string]::IsNullOrWhiteSpace($password)) { Write-Host '  密码为空，已跳过' -ForegroundColor Red; continue }
        $list += [pscustomobject]@{ userName = $userName.Trim(); password = $password.Trim() }
        $idx++
    }
    if ($list.Count -eq 0) { Write-Host '[错误] 未录入任何账号' -ForegroundColor Red; exit 1 }
    $AccountsJson = ConvertTo-Json -InputObject $list -Compress
    if ($list.Count -eq 1) { $AccountsJson = '[' + $AccountsJson + ']' }
}

# 校验 JSON
try { $parsed = $AccountsJson | ConvertFrom-Json } catch {
    Write-Host '[错误] AccountsJson 不是合法 JSON' -ForegroundColor Red
    exit 1
}

$secretResult = Gh 'secret' 'set' 'TY_ACCOUNTS' '--env' 'user' '--body' $AccountsJson '--repo' $fork
if ($secretResult.code -ne 0) {
    Write-Host "[错误] 写入 secret 失败: $($secretResult.text)" -ForegroundColor Red
    exit 1
}
Write-Host "      已写入 environment secret（账号数: $(@($parsed).Count)）"

# ---- 7. 启用 workflow ----
Write-Host '[7/8] 启用 workflow...' -ForegroundColor Green
$wfList = Gh 'workflow' 'list' '--all' '--repo' $fork '--json' 'id,name,path,state'
if ($wfList.code -eq 0) {
    try {
        $wfs = $wfList.text | ConvertFrom-Json
        foreach ($w in $wfs) {
            if ($w.state -ne 'active') {
                $en = Gh 'workflow' 'enable' $w.id '--repo' $fork
                if ($en.code -eq 0) { Write-Host "      已启用: $($w.name)" }
            } else {
                Write-Host "      已是启用状态: $($w.name)"
            }
        }
    } catch { Write-Host "      [警告] 解析 workflow 列表失败: $($wfList.text)" -ForegroundColor Yellow }
} else {
    Write-Host "      [警告] 读取 workflow 失败: $($wfList.text)" -ForegroundColor Yellow
}

# ---- 8. 触发首次运行 ----
if ($SkipRun) {
    Write-Host '[8/8] 跳过触发（-SkipRun）' -ForegroundColor Green
} else {
    Write-Host '[8/8] 触发首次运行...' -ForegroundColor Green
    $run = Gh 'workflow' 'run' 'run.yml' '--repo' $fork
    if ($run.code -ne 0) {
        Write-Host "      [警告] 触发失败: $($run.text)" -ForegroundColor Yellow
    } else {
        Write-Host '      已触发，等待 GitHub 排队...'
        Start-Sleep -Seconds 12
        $runs = Gh 'run' 'list' '--repo' $fork '--limit' '3' '--json' 'databaseId,status,conclusion,displayTitle,createdAt'
        if ($runs.code -eq 0) {
            $r = $runs.text | ConvertFrom-Json
            $latest = $r | Select-Object -First 1
            Write-Host "      最新运行: #$($latest.databaseId)  状态=$($latest.status)  结论=$($latest.conclusion)"
            Write-Host "      查看日志: gh run view $($latest.databaseId) --repo $fork --log"
        }
    }
}

Write-Host ''
Write-Host '=== 配置完成 ===' -ForegroundColor Cyan
Write-Host "仓库:      https://github.com/$fork"
Write-Host "Actions:   https://github.com/$fork/actions"
Write-Host "定时:      每天 UTC 02:35（北京时间 10:35），见 .github/workflows/run.yml"
Write-Host ''
Write-Host '说明：'
Write-Host '  - 账号已存为 environment `user` 的 secret，仓库代码里不含明文'
Write-Host '  - 工作流带 0-300 秒随机延迟，避开整点风控'
Write-Host '  - 首次运行需等待 1-3 分钟；若失败先看日志里的“账户名或密码错误 / 设备校验”'
Write-Host '  - 查看运行状态：gh run list --repo ' $fork
