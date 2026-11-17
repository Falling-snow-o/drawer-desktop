# engine/core.ps1 — 由 box.ps1 dot-source 加载

function Read-BoxRegistry {
    if (-not (Test-Path -LiteralPath $RegistryFile)) { return @() }
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $o = Get-Content -LiteralPath $RegistryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o -and $o.PSObject.Properties['boxes']) { return @($o.boxes) }
            if ($o -and $o.PSObject.Properties['name']) { return @($o) }
            return @($o)
        } catch {
            Start-Sleep -Milliseconds 40   # 正在被原子替换，重试
        }
    }
    return @()
}

# 不加锁的底层写入：先写临时文件再原子替换，读者永远看到完整 JSON
function Write-BoxRegistryRaw($list) {
    if (-not (Test-Path -LiteralPath $RegistryDir)) { New-Item -ItemType Directory -Force -Path $RegistryDir | Out-Null }
    if (@($list).Count -eq 0) {
        if (Test-Path -LiteralPath $RegistryFile) { Remove-Item -LiteralPath $RegistryFile -Force -ErrorAction SilentlyContinue }
        return
    }
    $tmp = $RegistryFile + '.tmp'
    (@{ boxes = @($list) } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $RegistryFile -Force
}

$script:RegistryMutexName = 'Local\drawer-registry'

function Invoke-BoxRegistryLocked([scriptblock] $Body) {
    $mtx = New-Object System.Threading.Mutex($false, $script:RegistryMutexName)
    $got = $false
    try {
        $got = $mtx.WaitOne(5000)
        if (-not $got) { throw '盒子注册表被占用，稍后重试' }
        return (& $Body)
    } finally {
        if ($got) { try { $mtx.ReleaseMutex() } catch { } }
        $mtx.Dispose()
    }
}

function Register-Box($name, $dir) {
    return Invoke-BoxRegistryLocked {
        $l = @(Read-BoxRegistry)
        $ex = $l | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($ex -and $ex.dir -ne $dir) { return $false }
        $l = @($l | Where-Object { $_.name -ne $name })
        $l += [pscustomobject]@{ name = $name; dir = $dir }
        Write-BoxRegistryRaw $l
        return $true
    }
}

function Unregister-Box($name) {
    Invoke-BoxRegistryLocked {
        Write-BoxRegistryRaw @(Read-BoxRegistry | Where-Object { $_.name -ne $name })
    } | Out-Null
}


# 按盒子的跨进程动作锁：CLI 和 GUI 同时操作同一个盒子时，第二个直接失败
function Lock-BoxAction([string] $Name, [int] $TimeoutMs = 0) {
    $safe = ($Name -replace '[^A-Za-z0-9_.-]', '_')
    if (-not $safe) { return $null }
    $mtx = New-Object System.Threading.Mutex($false, ('Local\drawer-box-' + $safe))
    try {
        if ($mtx.WaitOne($TimeoutMs)) { return $mtx }
    } catch { }
    try { $mtx.Dispose() } catch { }
    return $null
}

function Unlock-BoxAction($Mutex) {
    if (-not $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    try { $Mutex.Dispose() } catch { }
}
