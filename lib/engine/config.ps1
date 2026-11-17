# engine/config.ps1 — 由 box.ps1 dot-source 加载

function ConvertFrom-MiniYaml {
    param([string] $Text)

    $root = @{}
    $cur  = $null
    foreach ($line in ($Text -split "\r?\n")) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -match '^\s*-\s')    { continue }
        if ($line -match '^(\s*)([A-Za-z0-9_.\-]+)\s*:\s*(.*)$') {
            $indent = $Matches[1].Length
            $key    = $Matches[2]
            $val    = $Matches[3].Trim().Trim('"').Trim("'")
            if ($indent -eq 0) {
                if ($val -eq '') {
                    $sub = @{}
                    $root[$key] = $sub
                    $cur = $sub
                } else {
                    $root[$key] = $val
                    $cur = $null
                }
            } elseif ($null -ne $cur) {
                $cur[$key] = $val
            }
        }
    }
    return $root
}

function Get-BoxDir {
    param([string] $Name)

    if (-not $Name) {
        $d = Get-Location
        while ($d) {
            if (Test-Path (Join-Path $d.Path 'box.yaml')) { return $d.Path }
            $d = $d.Parent
        }
        throw "未指定抽屉，且当前目录不是抽屉。用法: box.ps1 <verb> <name>"
    }
    if (Test-Path -LiteralPath $Name -PathType Container) { return (Resolve-Path -LiteralPath $Name).Path }

    $reg = Read-BoxRegistry | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if ($reg -and (Test-Path -LiteralPath $reg.dir)) { return $reg.dir }

    $c = Join-Path $BoxesRoot $Name
    if (Test-Path -LiteralPath $c -PathType Container) { return $c }
    throw "找不到抽屉 '$Name'（查找过 '$Name' 和 '$c'）"
}

function Get-BoxConfig {
    param([string] $Dir)

    $f = Join-Path $Dir 'box.yaml'
    if (-not (Test-Path -LiteralPath $f)) { throw "缺少配置文件: $f" }

    $raw = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    $y   = ConvertFrom-MiniYaml -Text $raw

    $d = if ($y['distro'] -is [hashtable]) { $y['distro'] } else { @{} }
    $q = if ($y['quota']  -is [hashtable]) { $y['quota']  } else { @{} }
    $g = if ($y['gpu']    -is [hashtable]) { $y['gpu']    } else { @{} }
    $s = if ($y['store']  -is [hashtable]) { $y['store']  } else { @{} }
    $p = if ($y['power']  -is [hashtable]) { $y['power']  } else { @{} }

    $name = if ($y['name']) { [string]$y['name'] } else { Split-Path $Dir -Leaf }
    $img  = if ($d['image']) { [string]$d['image'] } else { 'ubuntu-base-24.04.3-base-amd64.tar.gz' }
    $url  = if ($d['url'])   { [string]$d['url'] }
            else { 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz' }

    $obj = [pscustomobject]@{
        Name      = $name
        Dir       = $Dir
        State     = (Join-Path $Dir 'state')
        Data      = (Join-Path $Dir 'data')
        Downloads = (Join-Path $Dir 'downloads')
        Blobs     = (Join-Path $Dir 'blobs')
        Image     = $img
        Url       = $url
        Cpu       = if ($q['cpu'])    { [string]$q['cpu'] }    else { '400000 100000' }
        Memory    = if ($q['memory']) { [string]$q['memory'] } else { '12G' }
        Pids      = if ($q['pids'])   { [string]$q['pids'] }   else { '512' }
        Vram      = if ($g['vram'])   { [string]$g['vram'] }   else { '0' }
        StoreType = if ($s['type'])   { [string]$s['type'] }   else { 'bind' }
        StoreAt   = if ($s['target']) { [string]$s['target'] } else { '/work' }
        KeepAwake = if ($p['keep_awake']) { [string]$p['keep_awake'] } else { 'session' }
        Packages  = if ($d['packages']) { [string]$d['packages'] } else { '' }
        PortsCfg  = if ($y['ports']) { [string]$y['ports'] } else { '' }
        Env       = if ($y['env'] -is [hashtable]) { $y['env'] } else { @{} }
    }

    $dc = Join-Path $Dir '.devcontainer\devcontainer.json'
    if (Test-Path -LiteralPath $dc) {
        try {
            $dj = Get-Content -LiteralPath $dc -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($dj.containerEnv) {
                foreach ($pp in $dj.containerEnv.PSObject.Properties) { $obj.Env[$pp.Name] = [string]$pp.Value }
            }
            $fp = @()
            if ($dj.forwardPorts) { $fp += @($dj.forwardPorts) }
            if ($dj.appPort) { $fp += @($dj.appPort) }
            if ($fp.Count -gt 0) { $obj.PortsCfg = (($fp | ForEach-Object { [string]$_ }) -join ',') }
        } catch { [Console]::Error.WriteLine("[跳过] " + $_.Exception.Message) }
    }
    return $obj
}

function Get-Settings {
    $p = Join-Path $env:USERPROFILE '.boxrun\settings.json'
    $def = [pscustomobject]@{ version = 1; mirror = 'tuna'; useBase = $true; aptCache = $true; restic = $false; updateUrl = '' }
    if (-not (Test-Path -LiteralPath $p)) { return $def }
    try {
        $s = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $s.mirror) { $s | Add-Member -NotePropertyName mirror -NotePropertyValue 'tuna' }
        if ($null -eq $s.useBase) { $s | Add-Member -NotePropertyName useBase -NotePropertyValue $true }
        if ($null -eq $s.aptCache) { $s | Add-Member -NotePropertyName aptCache -NotePropertyValue $true }
        return $s
    } catch { return $def }
}

function Set-AptEnv {
    param($Cfg)
    $settings = Get-Settings
    $mirror = if ($env:BOXRUN_APT_MIRROR) { $env:BOXRUN_APT_MIRROR } else { $settings.mirror }
    try { Set-GuestFile -Distro $Cfg.Name -Path '/etc/boxrun/apt.env' -Content ("BOXRUN_APT_MIRROR=" + $mirror) } catch { [Console]::Error.WriteLine("[跳过] " + $_.Exception.Message) }
}

function Get-RecommendedQuota {
    $cores = 0
    $ramGb = 0
    try {
        $cores = [int](Get-CimInstance Win32_Processor -ErrorAction Stop |
                       Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $ramGb = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB
    } catch { [Console]::Error.WriteLine("[跳过] " + $_.Exception.Message) }

    if ($cores -le 0) { $cores = 8 }
    if ($ramGb -le 0) { $ramGb = 16 }

    $cpuCores = [int][math]::Floor($cores / 4)
    if ($cpuCores -lt 1) { $cpuCores = 1 }
    if ($cpuCores -gt 8) { $cpuCores = 8 }

    $memGb = [int][math]::Floor($ramGb * 0.4)
    if ($memGb -gt 8) { $memGb = 8 }
    if ($memGb -gt ($ramGb - 4)) { $memGb = [int][math]::Floor($ramGb - 4) }
    if ($memGb -lt 2) { $memGb = 2 }

    return [pscustomobject]@{
        CpuCores  = $cpuCores
        CpuQuota  = ('{0} 100000' -f ($cpuCores * 100000))
        Memory    = ('{0}G' -f $memGb)
        Pids      = 512
        HostCores = $cores
        HostRamGB = [math]::Round($ramGb, 1)
    }
}
