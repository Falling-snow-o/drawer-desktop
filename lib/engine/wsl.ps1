# engine/wsl.ps1 — 由 box.ps1 dot-source 加载

function Invoke-Wsl {
    param([string[]] $WslArgs, [switch] $Quiet)

    # wsl 往 stderr 写东西时，$ErrorActionPreference='Stop' 会把它变成终止错误；
    # 这里临时放宽，让调用方只看退出码
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw  = & wsl.exe @WslArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    $lines = @()
    foreach ($l in $raw) {
        $s = "$l"
        $s = $s -replace "`0", ''
        $s = $s -replace [string][char]0xFEFF, ''
        $lines += $s
    }
    if (-not $Quiet -and $code -ne 0) {
        $txt = ($lines -join "`n").Trim()
        if ($txt) { Write-Dim $txt }
    }
    return [pscustomobject]@{ Code = $code; Out = $lines }
}

function Get-DistroList {
    $r   = Invoke-Wsl -WslArgs @('-l', '-q') -Quiet
    $raw = ($r.Out -join "`n")
    if (-not $raw) { return @() }
    $out = @()
    foreach ($p in ($raw -split "\r?\n")) {
        $t = $p.Trim()
        if ($t) { $out += $t }
    }
    return $out
}

function Test-Distro {
    param([string] $Name)
    return ((Get-DistroList) -contains $Name)
}

function Get-RunningDistroList {
    $r = Invoke-Wsl -WslArgs @('-l', '--running', '-q') -Quiet
    if ($r.Code -eq 0) {
        $out = @()
        foreach ($p in (($r.Out -join "`n") -split "\r?\n")) {
            $t = $p.Trim()
            if ($t) { $out += $t }
        }
        return $out
    }

    $out = @()
    $r2 = Invoke-Wsl -WslArgs @('-l', '-v') -Quiet
    foreach ($p in (($r2.Out -join "`n") -split "\r?\n")) {
        $t = $p.Trim()
        if ($t -match '^\*?\s*(\S+)\s+(\S+)\s+(\d+)\s*$') {
            $state = $Matches[2]
            if ($state -eq 'Running' -or $state -eq '运行中') { $out += $Matches[1] }
        }
    }
    return $out
}

function Test-DistroRunning {
    param([string] $Name)
    return ((Get-RunningDistroList) -contains $Name)
}

# 短缓存：GUI 每次 info 都会查发行版列表，1.2 秒内复用，省一次 wsl 进程
$script:WslListCache = $null
function Get-WslListCached {
    param([int] $TtlMs = 1200)
    if ($script:WslListCache) {
        $age = ([DateTime]::UtcNow - $script:WslListCache.T).TotalMilliseconds
        if ($age -lt $TtlMs) { return $script:WslListCache.Out }
    }
    $r = Invoke-Wsl -WslArgs @('-l', '-v') -Quiet
    $script:WslListCache = @{ T = [DateTime]::UtcNow; Out = $r.Out }
    return $r.Out
}
