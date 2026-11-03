#requires -Version 5.1
<#
.SYNOPSIS
    注册 / 删除 Windows 计划任务，让签到每天自动执行。

.PARAMETER Time
    每天执行时间（HH:mm），默认 10:35。

.PARAMETER Remove
    删除已注册的计划任务。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Time 10:35
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Remove
#>

param(
    [string]$Time = '10:35',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskName = 'Cloud189Checkin'

if ($Remove) {
    schtasks /Query /TN $taskName > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        schtasks /Delete /TN $taskName /F | Out-Null
        Write-Host "已删除计划任务: $taskName" -ForegroundColor Green
    } else {
        Write-Host "计划任务不存在: $taskName" -ForegroundColor Yellow
    }
    exit 0
}

if ($Time -notmatch '^\d{1,2}:\d{2}$') {
    Write-Host "[错误] 时间格式应为 HH:mm，例如 10:35" -ForegroundColor Red
    exit 1
}

$runScript = Join-Path $root 'run.ps1'
if (-not (Test-Path $runScript)) {
    Write-Host "[错误] 未找到 $runScript" -ForegroundColor Red
    exit 1
}

$action = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runScript

schtasks /Create /TN $taskName /TR $action /SC DAILY /ST $Time /RL LIMITED /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[错误] 创建计划任务失败' -ForegroundColor Red
    exit 1
}

Write-Host "已注册计划任务: $taskName，每天 $Time 执行" -ForegroundColor Green
Write-Host ''
Write-Host '查看状态:  schtasks /Query /TN Cloud189Checkin /V /FO LIST'
Write-Host '立即测试:  schtasks /Run  /TN Cloud189Checkin'
Write-Host '删除任务:  powershell -NoProfile -ExecutionPolicy Bypass -File .\install-task.ps1 -Remove'
Write-Host ''
Write-Host '提示：计划任务在用户登录后运行；若需未登录也执行，请改用 -RU <用户> -RP <密码> 参数注册。' -ForegroundColor Yellow
