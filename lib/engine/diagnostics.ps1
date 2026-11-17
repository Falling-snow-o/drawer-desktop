# engine/diagnostics.ps1 — status / doctor / scan

function Invoke-Status {
    param([string] $Dir)

    if (-not $Dir) { $Dir = Get-BoxDir $Box }
    $cfg     = Get-BoxConfig -Dir $Dir
    $running = Test-DistroRunning $cfg.Name

    $diskGb = 0
    if (Test-Path -LiteralPath $cfg.State) {
        $v = Get-ChildItem -LiteralPath $cfg.State -Filter '*.vhdx' -EA SilentlyContinue |
             Sort-Object Length -Descending | Select-Object -First 1
        if ($v) { $diskGb = [math]::Round($v.Length / 1GB, 2) }
    }

    # 递归统计 data/ 在数据多时很慢，快速模式直接跳过（GUI 显示 —）
    $dataGb = 0
    if (-not $Fast -and (Test-Path -LiteralPath $cfg.Data)) {
        $sum = (Get-ChildItem -LiteralPath $cfg.Data -Recurse -File -EA SilentlyContinue |
                Measure-Object Length -Sum).Sum
        if ($sum) { $dataGb = [math]::Round($sum / 1GB, 2) }
    } elseif ($Fast) {
        $dataGb = -1
    }

    Write-Host ""
    Write-Host ("{0}{1}{2}  ·  boxrun" -f $Fw.Bold, $cfg.Name, $Fw.Reset)
    Write-Host ("-" * 50)

    $built = Test-Distro $cfg.Name
    if (-not $built) {
        Write-Host ("  状态        {0}△ 未构建{1}  （先执行 build）" -f $Fw.Yellow, $Fw.Reset)
    } elseif ($running) {
        Write-Host ("  状态        {0}● 运行中{1}" -f $Fw.Green, $Fw.Reset)
    } else {
        Write-Host ("  状态        {0}○ 已停止{1}" -f $Fw.Gray, $Fw.Reset)
    }
    Write-Host ("  根盘        {0} GB" -f $diskGb)
    Write-Host ("  数据        {0} GB  →  {1}" -f $dataGb, $cfg.StoreAt)
    if ($cfg.Vram -and $cfg.Vram -ne '0') {
        Write-Host ("  显存闸      {0} MiB  （LD_PRELOAD，只拦 exec 起的进程）" -f $cfg.Vram)
    }

    if ($running) {
        $s = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-status') -Quiet
        $kv = @{}
        foreach ($l in $s.Out) {
            if ($l -match '^([a-z_]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] }
        }
        if ($kv.ContainsKey('cg_mem_max') -and $kv['cg_mem_max'] -ne 'max' -and [double]$kv['cg_mem_max'] -gt 0) {
            $now = [double]$kv['cg_mem_now']
            $max = [double]$kv['cg_mem_max']
            $pct = [math]::Round(100 * $now / $max, 1)
            Write-Host ("  内存上限    {0:N1} / {1:N1} GB  ({2}%)" -f ($now/1GB), ($max/1GB), $pct)
        }
        if ($kv.ContainsKey('cg_cpu')) {
            $cores = ''
            if ($kv['cg_cpu'] -match '^(\d+)\s+(\d+)$' -and [double]$Matches[2] -gt 0) {
                $cores = ('  （约 {0} 核）' -f [math]::Round([double]$Matches[1] / [double]$Matches[2], 2))
            }
            Write-Host ("  CPU 上限    {0}{1}" -f $kv['cg_cpu'], $cores)
        }
        if ($kv.ContainsKey('cg_pids_now')) { Write-Host ("  进程        {0} / {1}" -f $kv['cg_pids_now'], $kv['cg_pids_max']) }
        if ($kv.ContainsKey('kernel'))      { Write-Host ("  内核        {0}" -f $kv['kernel']) }
        if ($kv.ContainsKey('uptime')) {
            $up = [double]$kv['uptime']
            Write-Host ("  已运行      {0} 天 {1} 小时" -f [int]($up/86400), [int](($up % 86400)/3600))
        }
        $gd = if ($kv['gpu_dev'] -eq 'yes') { "✓ /dev/dxg" } else { "✗ 无" }
        $cl = if ($kv['cuda_lib'] -eq 'yes') { "✓ libcuda" } else { "✗ 无" }
        Write-Host ("  GPU 直通    {0}   {1}" -f $gd, $cl)
        if ($kv.ContainsKey('work_mount')) {
            $wm = if ($kv['work_mount'] -eq 'yes') { "✓ 已挂载" } else { "✗ 未挂载" }
            Write-Host ("  数据挂载    {0}   {1}" -f $wm, $cfg.StoreAt)
        }
        if ($kv.ContainsKey('cg_present') -and $kv['cg_present'] -eq 'no') {
            Write-Host ("  {0}配额未生效{1}（发行版重启过；下次 exec/up 会自动重建）" -f $Fw.Yellow, $Fw.Reset)
        }
    }

    if (Get-Command nvidia-smi -EA SilentlyContinue) {
        $g = & nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>$null
        if ($g) {
            $p = "$g" -split ',\s*'
            if ($p.Count -ge 3) {
                Write-Host ("  显存(全局)  {0} / {1} MiB    GPU {2}%" -f $p[0], $p[1], $p[2])
            }
        }
    }

    Write-Host ("-" * 50)
    Write-Host ""
}

function Invoke-Doctor {
    Write-Host ""
    Write-Host ("{0}Drawer Desktop doctor{1}  {2}v{3}{4}" -f $Fw.Bold, $Fw.Reset, $Fw.Gray, $BoxRunVersion, $Fw.Reset)
    Write-Host ("-" * 56)
    $script:bad = 0

    function Chk {
        param([string] $Name, [bool] $Ok, [string] $Detail)
        if ($Ok) {
            Write-Host ("  {0}OK{1}   {2,-24} {3}{4}{5}" -f $Fw.Green, $Fw.Reset, $Name, $Fw.Gray, $Detail, $Fw.Reset)
        } else {
            Write-Host ("  {0}FAIL{1} {2,-24} {3}{4}{5}" -f $Fw.Red, $Fw.Reset, $Name, $Fw.Gray, $Detail, $Fw.Reset)
            $script:bad++
        }
    }

    # 1 WSL
    $v   = Invoke-Wsl -WslArgs @('--version') -Quiet
    $txt = ($v.Out -join "`n")
    $ok  = ($v.Code -eq 0) -and ($txt -match 'WSL')
    $num = '?'
    if ($txt -match '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)') { $num = $Matches[1] }
    Chk 'WSL 已安装' $ok ("v" + $num)

    # 2 发行版（--running 之外，-l -v 必须真的能列出；E_ACCESSDENIED 会在这里暴露）
    $lv = Invoke-Wsl -WslArgs @('-l', '-v') -Quiet
    $ds = @(Get-DistroList)
    Chk 'WSL 发行版可枚举' ($lv.Code -eq 0) ("共 {0} 个: {1}" -f $ds.Count, ($ds -join ', '))

    # 3 全局 .wslconfig 未被本工具改动
    $wsc = Join-Path $env:USERPROFILE '.wslconfig'
    $touched = $false
    if (Test-Path -LiteralPath $wsc) {
        $c = Get-Content -LiteralPath $wsc -Raw -EA SilentlyContinue
        if ($c -match 'boxrun') { $touched = $true }
    }
    $dt = if ($touched) { '发现 boxrun 标记，应该清掉' } else { '干净（本工具不写它）' }
    Chk '.wslconfig 未被改动' (-not $touched) $dt

    # 4 portproxy 残留
    $pp = & netsh interface portproxy show v4tov4 2>&1 | Out-String
    $ppN = 0
    foreach ($l in ($pp -split "\r?\n")) {
        if ($l -match '^\s*(\d+\.\d+\.\d+\.\d+|0\.0\.0\.0)\s+\d+') { $ppN++ }
    }
    $dt = if ($ppN -gt 0) { "$ppN 条（publish 用过的请核对）" } else { '无' }
    Chk 'portproxy 无残留' ($ppN -eq 0) $dt

    # 5 幽灵注册项
    $ghost = @()
    $lx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (Test-Path $lx) {
        foreach ($k in (Get-ChildItem $lx -EA SilentlyContinue)) {
            $n = $k.GetValue('DistributionName')
            $p = $k.GetValue('BasePath')
            if ($n -and $p -and $n -notlike 'docker-desktop*') {
                $local = ($p -replace '^\\\\\?\\', '') -replace '\\base$', ''
                if (-not (Test-Path -LiteralPath $local)) { $ghost += $n }
            }
        }
    }
    $dt = if ($ghost.Count -gt 0) { ($ghost -join ', ') } else { '无' }
    Chk '无孤儿注册项' ($ghost.Count -eq 0) $dt

    # 6 GPU
    if (Get-Command nvidia-smi -EA SilentlyContinue) {
        $g = & nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>$null
        Chk 'nvidia-smi 可用' ($LASTEXITCODE -eq 0) ("$g")
    } else {
        Chk 'nvidia-smi 可用' $false '未找到'
    }

    # 7 锚点进程
    $aw = @()
    $stale = $false
    if (Test-Path -LiteralPath $BoxesRoot) {
        foreach ($b in (Get-ChildItem -LiteralPath $BoxesRoot -Directory -EA SilentlyContinue)) {
            $f = Join-Path $b.FullName 'state\keepawake.pid'
            if (Test-Path -LiteralPath $f) {
                $id = (Get-Content -LiteralPath $f -EA SilentlyContinue | Select-Object -First 1)
                if ($id -and (Get-Process -Id $id -EA SilentlyContinue)) { $aw += ("{0}:{1}" -f $b.Name, $id) }
                elseif ($id) { $aw += ("{0}:失联" -f $b.Name); $stale = $true }
            }
        }
    }
    $dt = if ($aw.Count -gt 0) { ($aw -join ', ') } else { '无' }
    Chk '锚点进程一致' (-not $stale) $dt

    # 8 每个抽屉：目录隔离 / 已注册 / data 可写
    if (Test-Path -LiteralPath $BoxesRoot) {
        foreach ($b in (Get-ChildItem -LiteralPath $BoxesRoot -Directory -EA SilentlyContinue)) {
            $y = Join-Path $b.FullName 'box.yaml'
            if (-not (Test-Path -LiteralPath $y)) { continue }
            $st = Join-Path $b.FullName 'state'
            $da = Join-Path $b.FullName 'data'
            $bad = $da.ToLower().StartsWith($st.ToLower() + '\')
            $dt = if ($bad) { 'data/ 在 state/ 下 —— unregister 会删掉它！' } else { 'ok' }
            Chk ("抽屉 {0} 目录隔离" -f $b.Name) (-not $bad) $dt

            $reg = Test-Distro $b.Name
            $dt2 = if ($reg) { '已注册' } else { '未注册（先 build）' }
            Chk ("抽屉 {0} 已注册" -f $b.Name) $reg $dt2

            $dw = $false
            try {
                if (-not (Test-Path -LiteralPath $da)) { New-Item -ItemType Directory -Force -Path $da | Out-Null }
                $dp = Join-Path $da '.write-probe'
                Set-Content -LiteralPath $dp -Value 'x' -ErrorAction Stop
                Remove-Item -LiteralPath $dp -Force -ErrorAction Stop
                $dw = $true
            } catch { }
            Chk ("抽屉 {0} data/ 可写" -f $b.Name) $dw $da
        }
    }

    # 9 抽屉根目录可写（不存在则创建，这是本工具自己的目录）
    if (-not (Test-Path -LiteralPath $BoxesRoot)) {
        New-Item -ItemType Directory -Force -Path $BoxesRoot | Out-Null
    }
    $writable = $false
    try {
        $probe = Join-Path $BoxesRoot '.write-probe'
        Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
        $writable = $true
    } catch { }
    Chk '抽屉根目录可写' $writable $BoxesRoot

    Write-Host ("-" * 56)
    if ($script:bad -eq 0) { Write-Host ("  {0}全部通过{1}" -f $Fw.Green, $Fw.Reset) }
    else                   { Write-Host ("  {0}{1} 项异常{2}" -f $Fw.Red, $script:bad, $Fw.Reset) }
    Write-Host ""
}

function Invoke-Scan {
    param([string] $Root, [int] $Depth = 4)

    if (-not $Root) { $Root = (Get-Location).Path }
    $rootFull = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $rootFull)) { Write-Bad ("目录不存在: " + $rootFull); return }

    Write-Step ("扫描 " + $rootFull + "（深度 " + $Depth + "）")

    $found = New-Object System.Collections.ArrayList
    $walk = $null
    $walk = {
        param($dir, $d)
        if ($d -gt $Depth) { return }
        if (Test-Path -LiteralPath (Join-Path $dir 'box.yaml')) { [void]$found.Add($dir); return }
        foreach ($sub in (Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
            if ($sub.Name -in @('state','blobs','data','downloads','node_modules','.git','examples','templates','Windows','Program Files','$Recycle.Bin','System Volume Information')) { continue }
            & $walk $sub.FullName ($d + 1)
        }
    }
    & $walk $rootFull 0

    if ($found.Count -eq 0) { Write-Warn '没找到含 box.yaml 的目录'; return }

    $reg = @(Read-BoxRegistry)
    $added = 0
    foreach ($dir in $found) {
        if ($reg | Where-Object { $_.dir -eq $dir }) { Write-Dim ("已登记: " + $dir); continue }
        try {
            $cfg = Get-BoxConfig -Dir $dir
            if (Register-Box $cfg.Name $dir) {
                Write-Ok ("发现: " + $cfg.Name + " → " + $dir)
                $added++
            } else {
                Write-Warn ("名字冲突，跳过: " + $cfg.Name + "（" + $dir + "）")
            }
        } catch { Write-Warn ("读取失败: " + $dir) }
    }
    Write-Ok ("扫描完成：发现 " + $found.Count + " 个，新登记 " + $added + " 个")
}
