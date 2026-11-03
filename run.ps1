#requires -Version 5.1
<#
.SYNOPSIS
    一键运行天翼云盘自动签到，带占位检查与运行历史记录。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
#>

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# 控制台切到 UTF-8，避免中文日志乱码
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $env:PYTHONIOENCODING = 'utf-8'
} catch { }

$envPath = Join-Path $root '.env'
if (-not (Test-Path $envPath)) {
    Write-Host '[错误] 缺少 .env，请先运行 setup.ps1' -ForegroundColor Red
    exit 2
}

$envText = Get-Content $envPath -Raw -Encoding UTF8
if ($envText -match 'your_account|your_password') {
    Write-Host '[错误] .env 仍是模板占位值，请先运行 setup.ps1 填写真实账号' -ForegroundColor Red
    exit 2
}

if (-not (Test-Path (Join-Path $root 'node_modules'))) {
    Write-Host '[信息] 首次运行，安装依赖...' -ForegroundColor Yellow
    & npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[错误] npm install 失败' -ForegroundColor Red
        exit 3
    }
}

$logDir = Join-Path $root '.logs'
if (-not (Test-Path $logDir)) { [void](New-Item -ItemType Directory -Path $logDir) }
$history = Join-Path $logDir 'run-history.log'

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host "===== 天翼云盘签到 $stamp =====" -ForegroundColor Cyan

& node --unhandled-rejections=strict ./src/app.js 2>&1 | ForEach-Object { Write-Host $_ }
$code = $LASTEXITCODE

$result = if ($code -eq 0) { 'OK' } else { "FAIL($code)" }
Add-Content -Path $history -Value ("[{0}] {1}" -f $stamp, $result) -Encoding UTF8

Write-Host "===== 结束: $result =====" -ForegroundColor Cyan
exit $code
