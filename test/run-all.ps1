# 一键回归：引擎冒烟 + 界面冒烟（需要已安装 Drawer）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File test\run-all.ps1 [-SkipEngine] [-SkipGui]
param(
    [switch] $SkipEngine,
    [switch] $SkipGui
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0

if (-not $SkipEngine) {
    Write-Host "==== 引擎冒烟 ====" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke.ps1')
    if ($LASTEXITCODE -ne 0) { $fail++ }
}

if (-not $SkipGui) {
    Write-Host "==== 界面冒烟 ====" -ForegroundColor Cyan
    $exe = Join-Path $env:LOCALAPPDATA 'Drawer\Drawer.exe'
    if (-not (Test-Path $exe)) {
        Write-Host "  [SKIP] 未安装 Drawer（先跑 dist\drawer-setup.exe）" -ForegroundColor Yellow
    } else {
        if (@(Get-Process Drawer -EA SilentlyContinue).Count -eq 0) {
            Start-Process $exe
            Start-Sleep -Seconds 7
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'gui-smoke.ps1')
        if ($LASTEXITCODE -ne 0) { $fail++ }
    }
}

Write-Host ""
if ($fail -eq 0) { Write-Host "全部通过" -ForegroundColor Green; exit 0 }
Write-Host ("有 {0} 组失败" -f $fail) -ForegroundColor Red
exit 1
