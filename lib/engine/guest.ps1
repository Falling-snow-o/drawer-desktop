# engine/guest.ps1 — 由 box.ps1 dot-source 加载

function Push-GuestScript {
    param([string] $Distro, [string] $Path, [string] $Content)

    $norm = $Content -replace "`r`n", "`n"
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($norm))
    $dir  = $Path.Substring(0, $Path.LastIndexOf('/'))
    $cmd  = "mkdir -p '$dir' && echo '$b64' | base64 -d > '$Path' && chmod +x '$Path'"
    $r    = Invoke-Wsl -WslArgs @('-d', $Distro, '-u', 'root', '--', 'bash', '-c', $cmd) -Quiet
    if ($r.Code -ne 0) {
        throw ("写入 guest 脚本失败: {0}`n{1}" -f $Path, ($r.Out -join "`n"))
    }
}

function Set-GuestFile {
    param([string] $Distro, [string] $Path, [string] $Content)

    $norm = $Content -replace "`r`n", "`n"
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($norm))
    $cmd  = "mkdir -p '$(Split-Path -Parent $Path -ErrorAction SilentlyContinue)' 2>/dev/null; " +
            "echo '$b64' | base64 -d > '$Path'"
    # 用 dirname 更稳
    $cmd  = "mkdir -p `"`$(dirname '$Path')`" && echo '$b64' | base64 -d > '$Path'"
    $r = Invoke-Wsl -WslArgs @('-d', $Distro, '-u', 'root', '--', 'bash', '-c', $cmd) -Quiet
    if ($r.Code -ne 0) { throw ("写入失败: {0}`n{1}" -f $Path, ($r.Out -join "`n")) }
}

function Sync-GuestScripts {
    param([string] $Distro, [string] $DataPath, [string] $Target, [string] $DownloadsPath,
          [string] $Cpu, [string] $Mem, [string] $Pids)

    # 内容没变就跳过推送：每次 up 少 6-8 次 wsl 调用（省 2-3 秒）
    $sig = $GuestExec + $GuestWork + $GuestGui + $GuestQuota + $GuestStatus + $GuestAbout + $GuestUsage +
           ("|{0}|{1}|{2}|{3}|{4}|{5}" -f $DataPath, $Target, $DownloadsPath, $Cpu, $Mem, $Pids)
    $sha = [Security.Cryptography.SHA256]::Create()
    $hb = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sig))
    $ver = -join ($hb[0..7] | ForEach-Object { $_.ToString('x2') })

    $cur = Invoke-Wsl -WslArgs @('-d', $Distro, '-u', 'root', '--', 'cat', '/etc/boxrun/sync.ver') -Quiet
    if ((($cur.Out -join '').Trim() -eq $ver)) {
        Write-Dim 'guest 脚本未变化，跳过推送'
        return
    }

    Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-exec'   -Content $GuestExec
    Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-work'   -Content $GuestWork
    Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-gui'    -Content $GuestGui
    Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-quota'  -Content $GuestQuota
    Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-status' -Content $GuestStatus
Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-about' -Content $GuestAbout
    Push-GuestScript -Distro $Distro -Path '/usr/local/bin/boxrun-usage' -Content $GuestUsage

    if ($DataPath) { Set-GuestFile -Distro $Distro -Path '/etc/boxrun/work.src' -Content $DataPath }
    if ($Target)   { Set-GuestFile -Distro $Distro -Path '/etc/boxrun/work.dst' -Content $Target }
    if ($DownloadsPath) { Set-GuestFile -Distro $Distro -Path '/etc/boxrun/dl.src' -Content $DownloadsPath }

    # 配额值落盘：发行版重启后 boxrun-exec 靠它把 cgroup 重新建起来
    if ($Cpu -or $Mem -or $Pids) {
        $q = "export BOXRUN_CPU='{0}'`nexport BOXRUN_MEM='{1}'`nexport BOXRUN_PIDS='{2}'" -f $Cpu, $Mem, $Pids
        Set-GuestFile -Distro $Distro -Path '/etc/boxrun/quota.env' -Content $q
    }
    Set-GuestFile -Distro $Distro -Path '/etc/boxrun/sync.ver' -Content $ver
}

function Install-VramGate {
    param($Cfg)

    $envPath = '/etc/boxrun/vram.env'
    $mb = 0
    if ($Cfg.Vram) { [void][int]::TryParse([string]$Cfg.Vram, [ref]$mb) }

    if ($mb -le 0) {
        Invoke-Wsl -WslArgs @('-d', $Cfg.Name, '-u', 'root', '--', 'rm', '-f', $envPath) -Quiet | Out-Null
        Write-Dim "gpu.vram=0，不做显存限制"
        return
    }

    $src = Join-Path $ScriptRoot 'vram\boxrun-vram.c'
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warn "缺少 vram\boxrun-vram.c，跳过显存闸"
        return
    }

    Write-Step ("准备显存闸（{0} MiB）" -f $mb)
    $srcText = Get-Content -LiteralPath $src -Raw -Encoding UTF8
    Set-GuestFile -Distro $Cfg.Name -Path '/usr/local/src/boxrun-vram.c' -Content $srcText

    # 按源码哈希命名，编译一次就缓存；换了源码自然重新编
    $hash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.Substring(0, 10).ToLower()
    $so   = ('/usr/local/lib/boxrun-vram-{0}.so' -f $hash)

    $bash = @"
#!/bin/bash
set -e
SRC=/usr/local/src/boxrun-vram.c
SO=$so
if [ -f "`$SO" ]; then echo cached; exit 0; fi
export DEBIAN_FRONTEND=noninteractive
command -v gcc >/dev/null 2>&1 || { timeout 120 apt-get update -qq >/dev/null 2>&1 || true; timeout 300 apt-get install -y -qq --no-install-recommends -o Dpkg::Lock::Timeout=60 gcc libc6-dev >/dev/null 2>&1 || true; }
mkdir -p /usr/local/lib
gcc -O2 -fPIC -shared -o "`$SO" "`$SRC" -ldl -lpthread
echo built
"@
    Set-GuestFile -Distro $Cfg.Name -Path '/tmp/boxrun-vram-build.sh' -Content $bash

    $build = Invoke-Wsl -WslArgs @(
        '-d', $Cfg.Name, '-u', 'root', '--', 'bash', '/tmp/boxrun-vram-build.sh'
    ) -Quiet

    if ($build.Code -ne 0 -or -not ($build.Out -join ' ')) {
        Write-Warn "显存闸编译失败，本次不启用"
        foreach ($l in $build.Out) { if ($l.Trim()) { Write-Dim $l } }
        return
    }

    Set-GuestFile -Distro $Cfg.Name -Path $envPath -Content (
        "export BOXRUN_VRAM_MB={0}`nexport LD_PRELOAD={1}" -f $mb, $so
    )
    Write-Ok ("显存闸已启用：{0} MiB（拦 cuMemAlloc 系列，超了返回 CUDA OOM）" -f $mb)
}

function Start-KeepAwake {
    param($Cfg)

    if ($Cfg.KeepAwake -eq 'off') { Write-Dim "keep_awake=off，不持有唤醒声明"; return }

    if (-not (Test-Path -LiteralPath $Cfg.State)) { New-Item -ItemType Directory -Force -Path $Cfg.State | Out-Null }
    $pidFile = Join-Path $Cfg.State $KeepAwakePid

    if (Test-Path -LiteralPath $pidFile) {
        $old = (Get-Content -LiteralPath $pidFile -EA SilentlyContinue | Select-Object -First 1)
        if ($old -and (Get-Process -Id $old -EA SilentlyContinue)) {
            Write-Dim "锚点已在运行 (pid $old)"
            return
        }
    }

    $tmp = Join-Path $env:TEMP ("boxrun-awake-{0}.ps1" -f $Cfg.Name)
    Set-Content -LiteralPath $tmp -Value $KeepAwakeBody -Encoding UTF8

    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File', $tmp) `
        -WindowStyle Hidden -PassThru

    Set-Content -LiteralPath $pidFile -Value $proc.Id -Encoding ASCII
    Write-Ok "锚点已起 (pid $($proc.Id)) —— 息屏不睡眠"
}

function Stop-KeepAwake {
    param($Cfg)

    $pidFile = Join-Path $Cfg.State $KeepAwakePid
    if (-not (Test-Path -LiteralPath $pidFile)) { return }

    $old = (Get-Content -LiteralPath $pidFile -EA SilentlyContinue | Select-Object -First 1)
    if ($old) {
        $p = Get-Process -Id $old -EA SilentlyContinue
        if ($p) {
            Stop-Process -Id $old -Force -EA SilentlyContinue
            Write-Ok "锚点已撤 (pid $old)"
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -EA SilentlyContinue
}

function Install-GuestExtras {
    param($Cfg)
    # 基础镜像里没有的小工具：幂等补装，失败只警告
    try {
        Set-AptEnv -Cfg $Cfg
        $script = @'
#!/bin/bash
need=""
for p in wslu; do
    dpkg -s "$p" >/dev/null 2>&1 || need="$need $p"
done
[ -z "$need" ] && { echo "EXTRAS_OK"; exit 0; }
export DEBIAN_FRONTEND=noninteractive
try_install() {
    timeout 240 apt-get install -y -qq --no-install-recommends -o Dpkg::Lock::Timeout=60 $need >/dev/null 2>&1
}
try_install || { timeout 120 apt-get update -qq >/dev/null 2>&1 || true; try_install; } || true
dpkg -s wslu >/dev/null 2>&1 && echo "EXTRAS_OK" || echo "EXTRAS_FAIL"
'@
        Set-GuestFile -Distro $Cfg.Name -Path '/tmp/boxrun-extras.sh' -Content $script
        $r = Invoke-Wsl -WslArgs @('-d', $Cfg.Name, '-u', 'root', '--', 'bash', '/tmp/boxrun-extras.sh') -Quiet
        if (($r.Out -join "`n") -match 'EXTRAS_OK') {
            Write-Dim "基础小工具已就绪（wslu）"
        } else {
            Write-Dim "基础小工具补装失败（不影响使用，可在工具箱手动装 wslu）"
        }
    } catch {
        Write-Dim ("基础小工具补装跳过: " + $_.Exception.Message)
    }
}

function Ensure-BoxRunning {
    param($Cfg)
    if (Test-DistroRunning $Cfg.Name) { return }
    Write-Dim ("抽屉 {0} 没在跑，先执行 up" -f $Cfg.Name)
    Invoke-Up
}
