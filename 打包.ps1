# 打包：一个自解压安装包 dist\boxrun-setup.exe
# 用法: powershell -ExecutionPolicy Bypass -File 打包.ps1

param([switch] $SkipTest, [switch] $FullTest)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
$app = Join-Path $dist 'app'
$stage = Join-Path $dist 'payload'
$dotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
if (-not (Test-Path $dotnet)) { $dotnet = 'dotnet' }

if ($FullTest) {
    Write-Host '[0/5] 界面冒烟（针对已安装版本，-FullTest）'
    $exe = Join-Path $env:LOCALAPPDATA 'Drawer\Drawer.exe'
    if (-not (Test-Path $exe)) {
        Write-Host '  跳过：还没安装 Drawer' -ForegroundColor Yellow
    } else {
        if (@(Get-Process Drawer -EA SilentlyContinue).Count -eq 0) {
            Start-Process $exe
            Start-Sleep -Seconds 7
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test\gui-smoke.ps1')
        if ($LASTEXITCODE -ne 0) { throw '界面冒烟失败，已中止打包' }
    }
}

if (-not $SkipTest) {
    Write-Host '[0/5] 冒烟测试（跳过用 -SkipTest）'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test\smoke.ps1')
    if ($LASTEXITCODE -ne 0) { throw '冒烟测试失败，已中止打包' }
}

Write-Host "[1/5] 清理 dist"
Remove-Item $dist -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory -Force -Path $app, $stage | Out-Null

Write-Host "[2/5] 编译管理器"
& $dotnet publish (Join-Path $root 'gui\BoxRun.csproj') -c Release -r win-x64 `
    --self-contained false -p:PublishSingleFile=true -o $app -v quiet
if ($LASTEXITCODE -ne 0) { throw '编译 BoxRun 失败' }

Write-Host "[3/5] 收集引擎与资源"
Copy-Item "$app\*" $stage -Recurse -Force
foreach ($item in @('box.ps1','boxrun.ico','README.md','PITFALLS.md')) {
    Copy-Item (Join-Path $root $item) $stage -Force
}
foreach ($dir in @('lib','vram','examples','guest')) {
    Copy-Item (Join-Path $root $dir) $stage -Recurse -Force
}

Write-Host "[4/5] 生成 payload.zip"
$payload = Join-Path $root 'installer\payload.zip'
Remove-Item $payload -Force -EA SilentlyContinue
Compress-Archive -Path "$stage\*" -DestinationPath $payload -Force

Write-Host "[5/5] 编译安装包"
$setupOut = Join-Path $dist 'setup'
& $dotnet publish (Join-Path $root 'installer\Installer.csproj') -c Release -r win-x64 `
    --self-contained false -p:PublishSingleFile=true -o $setupOut -v quiet
if ($LASTEXITCODE -ne 0) { throw '编译安装包失败' }

Copy-Item (Join-Path $setupOut 'drawer-setup.exe') (Join-Path $dist 'drawer-setup.exe') -Force
Remove-Item $stage -Recurse -Force -EA SilentlyContinue
Remove-Item $setupOut -Recurse -Force -EA SilentlyContinue

$exe = Join-Path $dist 'drawer-setup.exe'
Write-Host ("完成: {0}  ({1:N0} KB)" -f $exe, ((Get-Item $exe).Length / 1KB))
