# engine/api.ps1 — 列表/信息/端口/用量

function Get-BoxList {
    $dirs = @()

    foreach ($r in (Read-BoxRegistry)) {
        if ($r.dir -and (Test-Path -LiteralPath $r.dir)) { $dirs += $r.dir }
    }
    if (Test-Path -LiteralPath $BoxesRoot) {
        foreach ($d in (Get-ChildItem -LiteralPath $BoxesRoot -Directory -EA SilentlyContinue)) {
            $dirs += $d.FullName
        }
    }

    $out = @()
    foreach ($dir in ($dirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'box.yaml'))) { continue }
        $cfg   = Get-BoxConfig -Dir $dir
        $built = Test-Distro $cfg.Name
        $running = $false
        if ($built) { $running = Test-DistroRunning $cfg.Name }
        $out += [pscustomobject]@{
            name    = $cfg.Name
            built   = $built
            running = $running
            dir     = $dir
        }
    }
    return $out
}

function Get-BoxInfo {
    param([string] $Dir, [switch] $Fast)

    if (-not $Dir) { $Dir = Get-BoxDir $Box }
    $cfg = Get-BoxConfig -Dir $Dir

    # 一次 wsl -l -v 同时拿到“注册”和“运行”两种状态，少起一个进程
    $built   = $false
    $running = $false
    $lv = Get-WslListCached
    foreach ($line in $lv) {
        $t = ([string]$line).Trim()
        if ($t -match '^\*?\s*(\S+)\s+(\S+)\s+(\d+)\s*$' -and $Matches[1] -eq $cfg.Name) {
            $built = $true
            if ($Matches[2] -eq 'Running' -or $Matches[2] -eq '运行中') { $running = $true }
        }
    }

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

    $info = [ordered]@{
        name        = $cfg.Name
        dir         = $cfg.Dir
        built       = $built
        running     = $running
        diskGB      = $diskGb
        dataGB      = $dataGb
        storeAt     = $cfg.StoreAt
        vramMB      = 0
        kernel      = ''
        uptimeSec   = 0
        memNowGB    = 0
        memMaxGB    = 0
        cpuMax      = ''
        cpuCores    = 0
        cgPresent   = $false
        pidsNow     = 0
        pidsMax     = 0
        packages    = $cfg.Packages
        gpu         = $false
        cuda        = $false
        workMounted = $false
    }

    $mb = 0
    if ($cfg.Vram -and [int]::TryParse([string]$cfg.Vram, [ref]$mb)) { $info.vramMB = $mb }

    if ($running) {
        $s  = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-status') -Quiet
        $kv = @{}
        foreach ($l in $s.Out) { if ($l -match '^([a-z_]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] } }

        if ($kv['kernel'])      { $info.kernel = $kv['kernel'] }
        if ($kv['uptime'])      { $info.uptimeSec = [int][double]$kv['uptime'] }
        if ($kv['cg_mem_now'])  { $info.memNowGB = [math]::Round([double]$kv['cg_mem_now'] / 1GB, 2) }
        if ($kv['cg_mem_max'] -and $kv['cg_mem_max'] -ne 'max') {
            $info.memMaxGB = [math]::Round([double]$kv['cg_mem_max'] / 1GB, 2)
        }
        if ($kv['cg_cpu'])      { $info.cpuMax = $kv['cg_cpu'] }
        $info.cgPresent = ($kv['cg_present'] -eq 'yes')
        if ($info.cpuMax -match '^(\d+)\s+(\d+)$') {
            $qq = [double]$Matches[1]
            $pp = [double]$Matches[2]
            if ($pp -gt 0) { $info.cpuCores = [math]::Round($qq / $pp, 2) }
        }
        if ($kv['cg_pids_now']) { $info.pidsNow = [int]$kv['cg_pids_now'] }
        if ($kv['cg_pids_max']) { $info.pidsMax = [int]$kv['cg_pids_max'] }
        $info.gpu         = ($kv['gpu_dev'] -eq 'yes')
        $info.cuda        = ($kv['cuda_lib'] -eq 'yes')
        $info.workMounted = ($kv['work_mount'] -eq 'yes')
    }

    # 停止时也把配额配置带上（GUI 不用显示一排破折号）
    if (-not $running) {
        $memG = 0
        if ($cfg.Memory -match '^(\d+(?:\.\d+)?)\s*([GgMm])$') {
            $memG = [double]$Matches[1]
            if ($Matches[2] -match '[Mm]') { $memG = [math]::Round($memG / 1024, 2) }
        }
        $info.memMaxGB = $memG
        $info.cpuMax   = [string]$cfg.Cpu
        $info.pidsMax  = [int]$cfg.Pids
    }

    return [pscustomobject]$info
}

function Invoke-About {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $info = Get-BoxInfo -Dir $cfg.Dir
    $obj = [ordered]@{
        name       = $cfg.Name
        dir        = $cfg.Dir
        built      = [bool]$info.built
        running    = [bool]$info.running
        kernel     = $info.kernel
        uptimeSec  = $info.uptimeSec
        cpuCores   = $info.cpuCores
        memNowGB   = $info.memNowGB
        memMaxGB   = $info.memMaxGB
        diskGB     = $info.diskGB
        vramMB     = $info.vramMB
        gpu        = [bool]$info.gpu
        cuda       = [bool]$info.cuda
        packages   = $info.packages
        workMounted = [bool]$info.workMounted
        portsCfg   = $cfg.PortsCfg
        envCount   = @($cfg.Env.Keys).Count
        state      = $cfg.State
        data       = $cfg.Data
        downloads  = $cfg.Downloads
    }

    $aboutFile = Join-Path $cfg.State 'about.json'
    if (Test-Path -LiteralPath $aboutFile) {
        try {
            $stored = Get-Content -LiteralPath $aboutFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $stored.PSObject.Properties) {
                if (-not $obj.Contains($p.Name) -or -not $obj[$p.Name]) { $obj[$p.Name] = $p.Value }
            }
        } catch { [Console]::Error.WriteLine("[跳过] " + $_.Exception.Message) }
    }

    $guestFilled = $false
    if ($info.running) {
        $g = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-about') -Quiet
        foreach ($l in $g.Out) {
            $t = $l.Trim()
            if (-not $t -or $t -notmatch '=') { continue }
            $parts = $t.Split('=', 2)
            if ($parts.Count -eq 2) { $obj[$parts[0]] = $parts[1] }
        }
            $guestFilled = $true
    }

    if ($info.running -and $guestFilled) {
        try {
            $keep = [ordered]@{}
            foreach ($k in @('os','os_id','os_ver','kernel','arch','cpu','mem_total','pkgs','mirror','desktop','compositor')) {
                if ($obj.Contains($k) -and $obj[$k]) { $keep[$k] = $obj[$k] }
            }
            if ($keep.Count -gt 0) { ($keep | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Join-Path $cfg.State 'about.json') -Encoding UTF8 }
        } catch { [Console]::Error.WriteLine("[跳过] " + $_.Exception.Message) }
    }

    $snapDir = Join-Path $cfg.State 'snapshots'
    $snaps = @(Get-ChildItem -LiteralPath $snapDir -File -EA SilentlyContinue)
    if (-not $info.running -and $cfg.Cpu) {
        $q = ($cfg.Cpu -split ' ')[0]
        if ($q -match '^\d+$') { $obj['cpuCores'] = [int]([double]$q / 100000) }
    }
    $obj['snapshotCount'] = $snaps.Count
    $obj['snapshotMB'] = [math]::Round((($snaps | Measure-Object Length -Sum).Sum) / 1MB, 0)

    Write-Output ($obj | ConvertTo-Json -Compress -Depth 4)
}

function Invoke-Ports {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not (Test-DistroRunning $cfg.Name)) { Ensure-BoxRunning -Cfg $cfg }

    $items = @()
    $seen = @{}
    foreach ($procFile in @('/proc/net/tcp', '/proc/net/tcp6')) {
        $r = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'cat', $procFile) -Quiet
        foreach ($line in $r.Out) {
            $t = $line.Trim()
            if (-not $t -or $t -match '^sl') { continue }
            $f = $t -split '\s+'
            if ($f.Count -lt 4) { continue }
            if ($f[3] -ne '0A') { continue }
            $hex = ($f[1] -split ':')[-1]
            try { $port = [Convert]::ToInt32($hex, 16) } catch { continue }
            if ($seen.ContainsKey($port)) { continue }
            $seen[$port] = $true
            $items += [pscustomobject]@{ port = $port }
        }
    }
    $items = @($items | Sort-Object port)
    Write-Output (ConvertTo-Json -InputObject $items -Compress -Depth 3)
}

function Invoke-Usage {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not (Test-DistroRunning $cfg.Name)) {
        Write-Output '{"running":false}'
        return
    }

    $r = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-usage') -Quiet
    $parts = (($r.Out -join ' ').Trim() -split '\s+')

    $totalKB = 0.0; $availKB = 0.0; $procN = 0
    if ($parts.Count -ge 3) {
        [void][double]::TryParse($parts[0], [ref]$totalKB)
        [void][double]::TryParse($parts[1], [ref]$availKB)
        [void][int]::TryParse($parts[2], [ref]$procN)
    }

    $usedMB  = [math]::Round(($totalKB - $availKB) / 1024.0, 1)
    $totalMB = [math]::Round($totalKB / 1024.0, 0)
    if ($usedMB -lt 0) { $usedMB = 0 }

    [pscustomobject]@{
        running  = $true
        memMB    = $usedMB
        memMaxMB = $totalMB
        pids     = $procN
        pidsMax  = 0
    } | ConvertTo-Json -Compress
}
