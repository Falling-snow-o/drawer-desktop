# engine/core.ps1 — 由 box.ps1 dot-source 加载

function Read-BoxRegistry {
    if (-not (Test-Path -LiteralPath $RegistryFile)) { return @() }
    try {
        $o = Get-Content -LiteralPath $RegistryFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($o -and $o.PSObject.Properties['boxes']) { return @($o.boxes) }
        if ($o -and $o.PSObject.Properties['name']) { return @($o) }
        return @($o)
    } catch { return @() }
}

function Save-BoxRegistry($list) {
    if (-not (Test-Path -LiteralPath $RegistryDir)) { New-Item -ItemType Directory -Force -Path $RegistryDir | Out-Null }
    if (@($list).Count -eq 0) {
        if (Test-Path -LiteralPath $RegistryFile) { Remove-Item -LiteralPath $RegistryFile -Force }
        return
    }
    (@{ boxes = @($list) } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
}

function Register-Box($name, $dir) {
    $l = @(Read-BoxRegistry)
    $ex = $l | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($ex -and $ex.dir -ne $dir) { return $false }
    $l = @($l | Where-Object { $_.name -ne $name })
    $l += [pscustomobject]@{ name = $name; dir = $dir }
    Save-BoxRegistry $l
    return $true
}

function Unregister-Box($name) {
    Save-BoxRegistry @(Read-BoxRegistry | Where-Object { $_.name -ne $name })
}
