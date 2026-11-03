#requires -Version 5.1
<#
.SYNOPSIS
    交互式配置天翼云盘账号，写入项目根目录 .env。

.DESCRIPTION
    - 支持录入多个账号（序号 1..N）
    - 密码掩码输入
    - 自动保留 .env 中已配置的推送通道（SENDKEY、TELEGRAM_* 等）
    - 密码含特殊字符时自动加引号，避免 dotenv 解析出错

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$envPath = Join-Path $root '.env'

Write-Host ''
Write-Host '=== 天翼云盘自动签到 · 账号配置 ===' -ForegroundColor Cyan
Write-Host "配置文件: $envPath"
Write-Host ''

function Read-Masked([string]$Prompt) {
    Write-Host $Prompt -NoNewline
    try {
        $sb = New-Object System.Text.StringBuilder
        while ($true) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Enter) { break }
            if ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($sb.Length -gt 0) {
                    [void]$sb.Remove($sb.Length - 1, 1)
                    Write-Host "`b `b" -NoNewline
                }
                continue
            }
            [void]$sb.Append($key.KeyChar)
            Write-Host '*' -NoNewline
        }
        Write-Host ''
        return $sb.ToString()
    } catch {
        # 非交互终端（重定向输入）时回退到普通读取
        return (Read-Host $Prompt)
    }
}

function Format-EnvValue([string]$Value) {
    if ($Value -eq $null) { return '' }
    if ($Value -match '^[A-Za-z0-9@._\-/+=:]+$') { return $Value }   # 无需引号
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

# ---- 读取旧配置，保留非账号项 ----
$kept = @()
if (Test-Path $envPath) {
    $kept = Get-Content $envPath -Encoding UTF8 | Where-Object {
        $_.Trim() -ne '' -and $_ -notmatch '^TY_' -and $_ -notmatch '^#'
    }
}

# ---- 录入账号 ----
$accounts = New-Object System.Collections.ArrayList
$i = 1
while ($true) {
    Write-Host "--- 第 $i 个账号 ---" -ForegroundColor Yellow
    $userName = Read-Host '天翼账号（手机号/邮箱，直接回车结束录入）'
    if ([string]::IsNullOrWhiteSpace($userName)) { break }
    $password = Read-Masked '密码（输入时不显示）: '
    if ([string]::IsNullOrWhiteSpace($password)) {
        Write-Host '密码为空，已跳过该账号。' -ForegroundColor Red
        continue
    }
    [void]$accounts.Add([pscustomobject]@{
        index    = $i
        userName = $userName.Trim()
        password = $password.Trim()
    })
    $i++
}

if ($accounts.Count -eq 0) {
    Write-Host '未录入任何账号，配置未修改。' -ForegroundColor Red
    exit 1
}

# ---- 生成 .env ----
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# 本文件由 setup.ps1 生成于 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('# 注意：内含明文凭据，.gitignore 已忽略，请勿提交到任何仓库')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# ===== 账号 =====')
foreach ($acc in $accounts) {
    [void]$sb.AppendLine("TY_USERNAME_$($acc.index)=$(Format-EnvValue $acc.userName)")
    [void]$sb.AppendLine("TY_PASSWORD_$($acc.index)=$(Format-EnvValue $acc.password)")
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# ===== 推送 / 调试（保持原样）=====')
if ($kept.Count -eq 0) {
    [void]$sb.AppendLine('SENDKEY=')
    [void]$sb.AppendLine('TELEGRAM_BOT_TOKEN=')
    [void]$sb.AppendLine('TELEGRAM_CHAT_ID=')
    [void]$sb.AppendLine('WECOM_BOT_KEY=')
    [void]$sb.AppendLine('WECOM_BOT_TELPHONE=')
    [void]$sb.AppendLine('WX_PUSHER_APP_TOKEN=')
    [void]$sb.AppendLine('WX_PUSHER_UID=')
    [void]$sb.AppendLine('PUSH_PLUS_TOKEN=')
    [void]$sb.AppendLine('SHOWDOC_KEY=')
    [void]$sb.AppendLine('BARK_KEY=')
    [void]$sb.AppendLine('BARK_SERVER=')
    [void]$sb.AppendLine('WPUSH_APIKEY=')
    [void]$sb.AppendLine('WPUSH_CHANNEL=')
    [void]$sb.AppendLine('WPUSH_TOPIC_CODE=')
    [void]$sb.AppendLine('CLOUD189_VERBOSE=0')
} else {
    foreach ($line in $kept) { [void]$sb.AppendLine($line) }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envPath, $sb.ToString(), $utf8NoBom)

Write-Host ''
Write-Host "已写入 $($accounts.Count) 个账号 -> $envPath" -ForegroundColor Green
foreach ($acc in $accounts) {
    $masked = $acc.userName
    if ($masked.Length -gt 6) {
        $masked = $masked.Substring(0, 3) + ('*' * ([Math]::Min(6, $masked.Length - 6))) + $masked.Substring($masked.Length - 3)
    }
    Write-Host ("  #{0} {1}" -f $acc.index, $masked)
}
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host '  1) 立即试跑    powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1'
Write-Host '  2) 注册定时任务 powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Time 10:35'
