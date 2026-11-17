# Drawer 引擎冒烟测试
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File test\smoke.ps1 [-Keep] [-SkipBuild]
# 退出码 0 = 全通过

param(
    [switch] $Keep,
    [switch] $SkipBuild,
    [switch] $WithRestore
)

$ErrorActionPreference = 'Stop'
$engine = Join-Path (Split-Path $PSScriptRoot -Parent) 'box.ps1'
if (-not (Test-Path -LiteralPath $engine)) { throw "找不到引擎: $engine" }

$name = 'smoke-' + (Get-Random -Maximum 99999)
$dir = Join-Path $env:TEMP ('drawer-' + $name)
$script:pass = 0
$script:fail = 0

function Run([string[]] $a) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine @a 2>&1 | Out-String
    return $out
}

function Assert([bool] $cond, [string] $label) {
    if ($cond) { $script:pass++; Write-Host ("  [PASS] " + $label) -ForegroundColor Green }
    else { $script:fail++; Write-Host ("  [FAIL] " + $label) -ForegroundColor Red }
}

try {
    Write-Host "== 准备 =="
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    Write-Host "== add =="
    $o = Run @('add', $dir, '-Name', $name)
    Assert (Test-Path (Join-Path $dir 'box.yaml')) '生成 box.yaml'
    Assert ($o -match $name -or $o.Length -gt 0) 'add 有输出'

    Write-Host "== devcontainer / env / ports =="
    $dc = Join-Path $dir '.devcontainer'
    New-Item -ItemType Directory -Force -Path $dc | Out-Null
    '{"containerEnv":{"SMOKE_DC":"yes"},"forwardPorts":[8123]}' |
        Set-Content -LiteralPath (Join-Path $dc 'devcontainer.json') -Encoding UTF8
    $y = Get-Content -LiteralPath (Join-Path $dir 'box.yaml') -Raw -Encoding UTF8
    $y = $y.TrimEnd() + "`nenv:`n  SMOKE_ENV: hello`n"
    Set-Content -LiteralPath (Join-Path $dir 'box.yaml') -Value $y -Encoding UTF8

    Write-Host "== build =="
    if (-not $SkipBuild) {
        $o = Run @('build', $name)
        Assert ($o -match '\[进度\]|完成|成功|✓' -or $LASTEXITCODE -eq 0) 'build 返回成功迹象'
    } else { Write-Host '  (跳过 build)' }

    if (-not $SkipBuild) {
        Write-Host "== up / exec =="
        $o = Run @('up', $name)
        $o = Run @('exec', $name, 'env')
        Assert ($o -match 'SMOKE_ENV=hello') 'box.yaml env 注入'
        Assert ($o -match 'SMOKE_DC=yes') 'devcontainer env 注入'

        Write-Host "== ports =="
        $o = Run @('ports', $name)
        Assert ($o -match '^\[' -or $o -match 'port') 'ports 返回 JSON'

        Write-Host "== about =="
        $o = Run @('about', $name)
        Assert ($o -match '"built":\s*true') 'about built=true'
        Assert ($o -match '"envCount":\s*2') 'about envCount=2'
        Assert ($o -match '"portsCfg":\s*"8123"') 'about portsCfg 含 devcontainer 端口'

        Write-Host "== snap / snap-list =="
        $o = Run @('snap', $name, 't1')
        $snapDir = Join-Path $dir 'state\snapshots'
        $snap = @(Get-ChildItem -LiteralPath $snapDir -File -EA SilentlyContinue | Where-Object { $_.Name -like 't1.*' })
        Assert ($snap.Count -ge 1) '快照文件存在'
        Assert (@($snap | Where-Object { $_.Name -like '*.sha256' }).Count -ge 1) '快照校验和已生成'
        $o = Run @('snap-list', $name)
        Assert ($o -match 't1') 'snap-list 列出 t1'

        Write-Host "== down =="
        $null = Run @('down', $name)
        $o = Run @('about', $name)
        Assert ($o -match '"running":\s*false') 'down 后 running=false'

        if ($WithRestore) {
            Write-Host "== snap-restore =="
            $o = Run @('snap-restore', $name, 't1')
            Assert ($o -match '校验和 OK|还原') '还原走校验'
            $o = Run @('about', $name)
            Assert ($o -match '"built":\s*true') '还原后 built=true'
        }
    }
}
finally {
    if (-not $Keep) {
        Write-Host "== 清理 =="
        $null = Run @('remove', $name, '-y')
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -EA SilentlyContinue }
    }
    Write-Host ""
    Write-Host ("结果: {0} 通过, {1} 失败" -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { exit 1 }
}
