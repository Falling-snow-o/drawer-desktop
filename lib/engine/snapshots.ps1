# engine/snapshots.ps1 — 由 box.ps1 dot-source 加载

function Assert-SnapTag([string] $Tag) {
    if (-not $Tag) { throw '快照名不能为空' }
    if ($Tag.Length -gt 64) { throw '快照名太长（最多 64 字符）' }
    if ($Tag -match '[\\/:*?"<>|]' -or $Tag -match '\.\.' -or $Tag -match '^[.\s]+$') {
        throw ('非法的快照名: ' + $Tag + '（不能包含路径分隔符、.. 或特殊字符）')
    }
    return $Tag
}

function Get-Restic {
    $local = Join-Path $env:USERPROFILE '.boxrun\tools\restic.exe'
    if (Test-Path -LiteralPath $local) { return [pscustomobject]@{ Source = $local } }
    return Get-Command restic.exe -ErrorAction SilentlyContinue
}

function Get-ResticRepo($Cfg) {
    return Join-Path $Cfg.State 'restic'
}

function Get-ResticPass {
    $f = Join-Path $env:USERPROFILE '.boxrun\restic.pass'
    if (-not (Test-Path -LiteralPath $f)) {
        $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        $rnd = -join (1..28 | ForEach-Object { $alphabet[(Get-Random -Maximum $alphabet.Length)] })
        Set-Content -LiteralPath $f -Value $rnd -Encoding ASCII
    }
    return $f
}

function Invoke-Snap {
    param([string] $Tag)

    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not $Tag) { throw "用法: box.ps1 snap <name> <tag>" }
    $Tag = Assert-SnapTag $Tag

    $snapDir = Join-Path $cfg.State 'snapshots'
    if (-not (Test-Path -LiteralPath $snapDir)) { New-Item -ItemType Directory -Force -Path $snapDir | Out-Null }
    $plain = Join-Path $snapDir ("{0}.tar" -f $Tag)
    if (Test-Path -LiteralPath $plain) { throw ("快照已存在: " + $Tag + "（换个名字或先 snap-delete）") }
    $out = $plain

    Write-Step ("快照 {0} → {1}" -f $cfg.Name, $Tag)
    Write-Dim "全量导出（WSL 原生 vhdx 没有增量快照）"
    Write-Host "[进度] 10%"

    Invoke-Wsl -WslArgs @('--terminate', $cfg.Name) -Quiet | Out-Null
    $r = Invoke-Wsl -WslArgs @('--export', $cfg.Name, $plain)
    if ($r.Code -ne 0) { throw ("导出失败`n{0}" -f ($r.Out -join "`n")) }

    $settings = Get-Settings
    $restic = Get-Restic
    if ($settings.restic -and $restic) {
        $repo = Get-ResticRepo $cfg
        $pass = Get-ResticPass
        if (-not (Test-Path -LiteralPath $repo)) {
            Write-Dim "初始化 restic 仓库…"
            & $restic.Source -r $repo --password-file $pass init *> $null
        }
        Write-Dim "restic 增量备份（去重）…"
        $cmd = '"' + $restic.Source + '" -r "' + $repo + '" --password-file "' + $pass +
               '" backup --stdin --stdin-filename snapshot.tar --tag snap:' + $Tag + ' < "' + $plain + '"'
        $outR = cmd /c $cmd 2>&1
        if ($LASTEXITCODE -eq 0) {
            Remove-Item -LiteralPath $plain -Force -EA SilentlyContinue
            Write-Host "[进度] 100%"
            Write-Ok ("已备份到 restic: " + $Tag)
            return
        }
        Write-Dim "restic 失败，回退 tar"
    }

    $zstd = Get-Command zstd.exe -EA SilentlyContinue
    if ($zstd) {
        Write-Dim "zstd 压缩中…"
        $zst = ("{0}.zst" -f $plain)
        & $zstd.Source -q -19 -f -- $plain -o $zst
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $zst)) {
            Remove-Item -LiteralPath $plain -Force -EA SilentlyContinue
            $out = $zst
        }
    }

    $mb = [math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 0)
    $h = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash
    Set-Content -LiteralPath ($out + '.sha256') -Value ($h + '  ' + (Split-Path $out -Leaf)) -Encoding ASCII
    Write-Host "[进度] 100%"
    Write-Ok ("已保存: {0} ({1} MB)" -f $out, $mb)
}

function Invoke-SnapList {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $snapDir = Join-Path $cfg.State 'snapshots'
    $items = @()

    $restic = Get-Restic
    $repo = Get-ResticRepo $cfg
    if ($restic -and (Test-Path -LiteralPath $repo)) {
        try {
            $pass = Get-ResticPass
            $js = (& $restic.Source -r $repo --password-file $pass snapshots --json 2>$null | Out-String)
            foreach ($sn in ($js | ConvertFrom-Json)) {
                $tag = (($sn.tags | Where-Object { $_ -like 'snap:*' }) | Select-Object -First 1)
                if ($tag) { $tag = $tag.Substring(5) } else { $tag = [string]$sn.short_id }
                $mb = 0
                try {
                    $st = (& $restic.Source -r $repo --password-file $pass stats $sn.id --json 2>$null | Out-String)
                    $stj = $st | ConvertFrom-Json
                    if ($stj.total_size) { $mb = [math]::Round($stj.total_size / 1MB, 0) }
                } catch { }
                $items += [pscustomobject]@{
                    tag = [string]$tag; file = 'restic'; sizeMB = $mb
                    created = ([datetime]$sn.time).ToString('yyyy-MM-dd HH:mm')
                    path = ''
                }
            }
        } catch { }
    }
    if (Test-Path -LiteralPath $snapDir) {
        foreach ($f in Get-ChildItem -LiteralPath $snapDir -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending) {
            $items += [pscustomobject]@{
                tag     = $f.Name -replace '\.tar(\.gz)?$', ''
                file    = $f.Name
                path    = $f.FullName
                sizeMB  = [math]::Round($f.Length / 1MB, 0)
                created = $f.LastWriteTime.ToString('s')
            }
        }
    }
    Write-Output (ConvertTo-Json -InputObject $items -Depth 4 -Compress)
}

function Invoke-SnapDelete {
    param([string] $Tag)
    if (-not $Tag) { throw "用法: box.ps1 snap-delete <name> <tag>" }
    $Tag = Assert-SnapTag $Tag

    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $restic = Get-Restic
    $repo = Get-ResticRepo $cfg
    if ($restic -and (Test-Path -LiteralPath $repo)) {
        $pass = Get-ResticPass
        $js = (& $restic.Source -r $repo --password-file $pass snapshots --json 2>$null | Out-String) | ConvertFrom-Json
        $hit = $js | Where-Object { $_.tags -contains ('snap:' + $Tag) } | Select-Object -First 1
        if ($hit) {
            & $restic.Source -r $repo --password-file $pass forget $hit.id --prune *> $null
            if ($LASTEXITCODE -eq 0) { Write-Ok ("已删除 restic 快照: " + $Tag); return }
            throw "restic forget 失败"
        }
    }

    $snapDir = Join-Path $cfg.State 'snapshots'
    $file = Get-ChildItem -LiteralPath $snapDir -File -EA SilentlyContinue |
            Where-Object { $_.Name -like ($Tag + '.tar*') -and $_.Name -notlike '*.sha256' } |
            Select-Object -First 1
    if (-not $file) { throw ("找不到快照: " + $Tag) }
    Remove-Item -LiteralPath $file.FullName -Force
    Remove-Item -LiteralPath ($file.FullName + '.sha256') -Force -EA SilentlyContinue
    Write-Ok ("已删除快照: " + $Tag)
}

function Invoke-SnapRestore {
    param([string] $Tag)

    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not $Tag) { throw "用法: box.ps1 snap-restore <name> <tag>" }
    $Tag = Assert-SnapTag $Tag

    $snapDir = Join-Path $cfg.State 'snapshots'
    $restic = Get-Restic
    $repo = Get-ResticRepo $cfg
    if ($restic -and (Test-Path -LiteralPath $repo)) {
        try {
            $pass = Get-ResticPass
            $js = (& $restic.Source -r $repo --password-file $pass snapshots --json 2>$null | Out-String) | ConvertFrom-Json
            $hit = $js | Where-Object { $_.tags -contains ('snap:' + $Tag) } | Select-Object -First 1
            if ($hit) {
                Write-Step ("从 restic 还原 {0} ← {1}" -f $cfg.Name, $Tag)
                $tmpTar = Join-Path $env:TEMP ('boxrun-restic-' + [guid]::NewGuid().ToString('N') + '.tar')
                $cmd = '"' + $restic.Source + '" -r "' + $repo + '" --password-file "' + $pass +
                       '" dump ' + $hit.id + ' /snapshot.tar > "' + $tmpTar + '"'
                $null = cmd /c $cmd 2>&1
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmpTar)) { throw "restic dump 失败" }

                Invoke-Wsl -WslArgs @('--terminate', $cfg.Name) -Quiet | Out-Null
                Stop-KeepAwake -Cfg $cfg
                Invoke-Wsl -WslArgs @('--unregister', $cfg.Name) -Quiet | Out-Null
                if (Test-Path -LiteralPath $cfg.State) {
                    Get-ChildItem -LiteralPath $cfg.State -Force -EA SilentlyContinue |
                        Where-Object { $_.Name -ne 'restic' -and $_.Name -ne 'snapshots' } |
                        Remove-Item -Recurse -Force -EA SilentlyContinue
                }
                New-Item -ItemType Directory -Force -Path $cfg.State | Out-Null
                $imp = Invoke-Wsl -WslArgs @('--import', $cfg.Name, $cfg.State, $tmpTar, '--version', '2')
                Remove-Item -LiteralPath $tmpTar -Force -EA SilentlyContinue
                if ($imp.Code -ne 0) { throw ("导入失败`n" + ($imp.Out -join "`n")) }
                Write-Ok "restic 还原完成"
                return
            }
        } catch { Write-Dim ("restic 还原跳过: " + $_.Exception.Message) }
    }

    $file = Get-ChildItem -LiteralPath $snapDir -File -EA SilentlyContinue |
            Where-Object { $_.Name -eq ($Tag + '.tar') -or $_.Name -eq ($Tag + '.tar.gz') -or $_.Name -eq ($Tag + '.tar.zst') } |
            Select-Object -First 1
    if (-not $file) { throw ("找不到快照: " + $Tag) }

    if ($file.Extension -eq '.zst') {
        $zstd = Get-Command zstd.exe -EA SilentlyContinue
        if (-not $zstd) { throw "该快照是 zstd 压缩，需要 zstd.exe 才能还原" }
        $tmp = Join-Path $env:TEMP ($file.BaseName)
        & $zstd.Source -d -f -q -- $file.FullName -o $tmp
        if ($LASTEXITCODE -ne 0) { throw "zstd 解压失败" }
        $file = Get-Item -LiteralPath $tmp
    }

    $sha = $file.FullName + '.sha256'
    if (Test-Path -LiteralPath $sha) {
        $want = (Get-Content -LiteralPath $sha -Raw).Trim().Split(' ')[0]
        $got = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        if ($want -and $want -ne $got) {
            throw ("快照校验失败（文件可能损坏）：`n  期望 {0}`n  实际 {1}" -f $want, $got)
        }
        Write-Dim "校验和 OK"
    } else {
        Write-Dim "（旧快照没有校验文件，跳过校验）"
    }

    Write-Step ("还原 {0} ← {1} ({2} MB)" -f $cfg.Name, $file.Name, [math]::Round($file.Length / 1MB, 0))
    Write-Dim "当前系统会被替换，data/ 和 downloads/ 不动"
    Write-Host "[进度] 10%"

    Invoke-Wsl -WslArgs @('--terminate',  $cfg.Name) -Quiet | Out-Null
    Stop-KeepAwake -Cfg $cfg
    Invoke-Wsl -WslArgs @('--unregister', $cfg.Name) -Quiet | Out-Null
    Write-Host "[进度] 35%"

    if (Test-Path -LiteralPath $cfg.State) {
        Get-ChildItem -LiteralPath $cfg.State -Force -EA SilentlyContinue |
            Where-Object { $_.Name -ne 'snapshots' } |
            Remove-Item -Recurse -Force -EA SilentlyContinue
    } else {
        New-Item -ItemType Directory -Force -Path $cfg.State | Out-Null
    }
    Write-Host "[进度] 50%"

    $r = Invoke-Wsl -WslArgs @('--import', $cfg.Name, $cfg.State, $file.FullName, '--version', '2')
    if ($r.Code -ne 0) {
        foreach ($l in $r.Out) { if ($l.Trim()) { Write-Dim $l } }
        throw "导入快照失败"
    }
    Write-Host "[进度] 85%"

    [void](Register-Box $cfg.Name $cfg.Dir)
    Sync-GuestScripts -Distro $cfg.Name -DataPath $cfg.Data -Target $cfg.StoreAt -DownloadsPath $cfg.Downloads `
        -Cpu $cfg.Cpu -Mem $cfg.Memory -Pids $cfg.Pids 2>$null
    Write-Host "[进度] 100%"
    Write-Ok ("快照已还原: {0}" -f $cfg.Name)
    Write-Dim ("下一步: box.ps1 up {0}" -f $cfg.Name)
}
