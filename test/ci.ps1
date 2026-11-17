# 持续集成：语法检查 + 编译（不跑 WSL 冒烟，CI runner 没有嵌套虚拟化）
# 本地加 -Smoke 可连引擎冒烟一起跑
param([switch] $Smoke)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0

Write-Host "== 1. PowerShell 语法检查 =="
$psFiles = Get-ChildItem $root -Recurse -Filter *.ps1 -File |
    Where-Object { $_.FullName -notmatch '\\(dist|obj|bin|payload|node_modules)\\' }
foreach ($f in $psFiles) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $fail++
        Write-Host ("  [FAIL] {0}" -f $f.FullName.Replace($root + '\', '')) -ForegroundColor Red
        $errors | Select-Object -First 3 | ForEach-Object { Write-Host ("         " + $_.Message) }
    }
}
if ($fail -eq 0) { Write-Host ("  [PASS] {0} 个脚本语法正常" -f $psFiles.Count) -ForegroundColor Green }

Write-Host "== 2. 编译 GUI =="
$dotnet = 'dotnet'
$local = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
if (Test-Path $local) { $dotnet = $local }
& $dotnet build (Join-Path $root 'gui\BoxRun.csproj') -c Release -v quiet
if ($LASTEXITCODE -ne 0) { $fail++; Write-Host '  [FAIL] GUI 编译失败' -ForegroundColor Red }
else { Write-Host '  [PASS] GUI 编译通过' -ForegroundColor Green }

Write-Host "== 3. 编译安装器 =="
& $dotnet build (Join-Path $root 'installer\Installer.csproj') -c Release -v quiet
if ($LASTEXITCODE -ne 0) { $fail++; Write-Host '  [FAIL] 安装器编译失败' -ForegroundColor Red }
else { Write-Host '  [PASS] 安装器编译通过' -ForegroundColor Green }

if ($Smoke) {
    Write-Host "== 4. 引擎冒烟 =="
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke.ps1')
    if ($LASTEXITCODE -ne 0) { $fail++ }
}

Write-Host ""
if ($fail -eq 0) { Write-Host 'CI 通过' -ForegroundColor Green; exit 0 }
Write-Host ("CI 失败：{0} 项" -f $fail) -ForegroundColor Red
exit 1
