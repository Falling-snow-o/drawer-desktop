# test/collab-smoke.ps1 —— 协同模式端到端：两个抽屉 + 本地裸仓库
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root 'box.ps1'
$pass = 0; $fail = 0
function Check($cond, $name) {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "  [FAIL] $name" -ForegroundColor Red }
}
function Run($argsArr) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engine @argsArr 2>&1
    return ($out -join "`n")
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Write-Host '未安装 git，跳过协同测试' -ForegroundColor Yellow
    exit 0
}

$suffix = Get-Random -Maximum 99999
$a = "cs-a-$suffix"
$b = "cs-b-$suffix"
$da = Join-Path $env:TEMP $a
$db = Join-Path $env:TEMP $b
$bare = Join-Path $env:TEMP ("cs-$suffix.git")

try {
    & git init --bare -q $bare
    Check ($LASTEXITCODE -eq 0) '创建本地裸仓库'

    $null = Run @('add', $da, '-Name', $a)
    $null = Run @('add', $db, '-Name', $b)
    Check (Test-Path (Join-Path $da 'data')) '抽屉 A 数据目录'
    Check (Test-Path (Join-Path $db 'data')) '抽屉 B 数据目录'

    # A 初始化并推送
    $out = Run @('collab', $a, 'init', $bare)
    Check ($out -match '已推送到') 'A 初始化并推送'

    Set-Content -LiteralPath (Join-Path $da 'data\shared.txt') -Value 'shared' -Encoding UTF8
    $out = Run @('collab', $a, 'sync', '-m', 'a: shared')
    Check ($out -match '已同步到远端') 'A 同步共享文件'

    # B 克隆
    $out = Run @('collab', $b, 'clone', $bare)
    Check ($out -match '已从远端克隆') 'B 从远端克隆'
    Check (Test-Path (Join-Path $db 'data\shared.txt')) 'B 拿到共享文件'

    # B 改并推送
    Set-Content -LiteralPath (Join-Path $db 'data\bob.txt') -Value 'bob' -Encoding UTF8
    $out = Run @('collab', $b, 'commit', '-m', 'b: bob')
    Check ($out -match '已提交') 'B 提交'
    $out = Run @('collab', $b, 'push')
    Check ($out -match '已推送') 'B 推送'

    # A 合并
    $null = Run @('collab', $a, 'fetch')
    $out = Run @('collab', $a, 'merge', 'master')
    Check ($out -match '已合并') 'A 合并 B 的提交'
    Check (Test-Path (Join-Path $da 'data\bob.txt')) '合并后 A 有 bob.txt'

    # A 反向同步，B 拉取
    Set-Content -LiteralPath (Join-Path $da 'data\alice.txt') -Value 'alice' -Encoding UTF8
    $out = Run @('collab', $a, 'sync', '-m', 'a: alice')
    Check ($out -match '已同步到远端') 'A 再同步'
    $out = Run @('collab', $b, 'pull')
    Check ($out -match '已拉取') 'B 拉取'
    Check (Test-Path (Join-Path $db 'data\alice.txt')) 'B 拿到 alice.txt'

    # 分支 / 标签 / 贮藏
    $out = Run @('collab', $a, 'branch', '-c', 'feature')
    Check ($out -match '分支已切换') '新建并切换分支'
    $out = Run @('collab', $a, 'branch')
    Check ($out -match '\*\s*feature') '分支列表标记当前'

    $out = Run @('collab', $a, 'tag', 'v-test')
    Check ($out -match '已打标签') '打标签'

    Set-Content -LiteralPath (Join-Path $da 'data\wip.txt') -Value 'wip' -Encoding UTF8
    $out = Run @('collab', $a, 'stash')
    Check ($out -match '已贮藏') '贮藏改动'
    $out = Run @('collab', $a, 'stash', 'list')
    Check ($out -match 'stash@') '贮藏列表'
    $out = Run @('collab', $a, 'stash', 'pop')
    Check ($out -match '已恢复') '恢复贮藏'

    # 状态可读
    $out = Run @('collab', $a, 'status')
    Check ($out -match '##') '状态输出分支'
}
finally {
    foreach ($n in @($a, $b)) {
        try { $null = Run @('remove', $n, '-y') } catch { }
    }
    Remove-Item -LiteralPath $da, $db, $bare -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("结果: {0} 通过, {1} 失败" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
