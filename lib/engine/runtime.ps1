# engine/runtime.ps1 — 由 box.ps1 dot-source 加载

function Invoke-Up {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not (Assert-HostCapacity -What '启动')) { return }
    if (-not (Test-Distro $cfg.Name)) {
        Write-Bad ("抽屉 {0} 还没构建" -f $cfg.Name)
        Write-Dim ("先执行: box.ps1 build {0}" -f $cfg.Name)
        return
    }

    $r = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'true')
    if ($r.Code -ne 0) { throw ("启动失败`n{0}" -f ($r.Out -join "`n")) }

    # 下载目录：Windows 侧先建好，否则 drvfs 挂不上
    if (-not (Test-Path -LiteralPath $cfg.Downloads)) {
        New-Item -ItemType Directory -Force -Path $cfg.Downloads | Out-Null
    }

    Write-Step "同步 guest 脚本"
    if ($cfg.StoreType -eq 'bind') {
        Sync-GuestScripts -Distro $cfg.Name -DataPath $cfg.Data -Target $cfg.StoreAt -DownloadsPath $cfg.Downloads `
                          -Cpu $cfg.Cpu -Mem $cfg.Memory -Pids $cfg.Pids
    } else {
        Sync-GuestScripts -Distro $cfg.Name -Cpu $cfg.Cpu -Mem $cfg.Memory -Pids $cfg.Pids
        # store 不是 bind 时清掉旧配置，免得 exec 又把 /work 挂上
        Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--',
            'rm', '-f', '/etc/boxrun/work.src', '/etc/boxrun/work.dst'
        ) -Quiet | Out-Null
    }

    Write-Step "应用配额"
    $q = Invoke-Wsl -WslArgs @(
        '-d', $cfg.Name, '-u', 'root', '--', 'env',
        ("BOXRUN_CPU={0}"  -f $cfg.Cpu),
        ("BOXRUN_MEM={0}"  -f $cfg.Memory),
        ("BOXRUN_PIDS={0}" -f $cfg.Pids),
        '/usr/local/bin/boxrun-quota'
    ) -Quiet
    if ($q.Code -eq 0) {
        $cores = ''
        if ($cfg.Cpu -match '^(\d+)\s+(\d+)$' -and [double]$Matches[2] -gt 0) {
            $cores = (' / {0} 核' -f [math]::Round([double]$Matches[1] / [double]$Matches[2], 2))
        }
        Write-Ok ("配额已应用：{0}{1} / 内存 {2} / 进程 {3}" -f $cfg.Cpu, $cores, $cfg.Memory, $cfg.Pids)
    } else {
        Write-Warn ("配额应用失败（返回 {0}），箱内可能没有 cgroup v2" -f $q.Code)
    }

    if ($cfg.StoreType -eq 'bind') {
        if (-not (Test-Path -LiteralPath $cfg.Data)) {
            New-Item -ItemType Directory -Force -Path $cfg.Data | Out-Null
        }
        Write-Step ("挂载 data → {0}" -f $cfg.StoreAt)
        $m = Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-work'
        ) -Quiet
        if ($m.Code -eq 0) {
            Write-Ok ("data → {0}，downloads → /downloads 已挂载" -f $cfg.StoreAt)
        } else {
            Write-Warn ("挂载失败（返回 {0}），箱内 {1} 不可用" -f $m.Code, $cfg.StoreAt)
            foreach ($l in $m.Out) { if ($l.Trim()) { Write-Dim $l } }
        }
    }

    Install-VramGate -Cfg $cfg

    Start-KeepAwake -Cfg $cfg
    Write-Ok ("{0} 已就绪" -f $cfg.Name)
    Write-Dim ("box.ps1 exec {0} bash" -f $cfg.Name)
}

function Invoke-Down {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)

    Write-Step "sync 刷盘（漏了这一步 ext4 会损坏）"
    Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'sync') -Quiet | Out-Null

    Invoke-Wsl -WslArgs @('--terminate', $cfg.Name) -Quiet | Out-Null
    Start-Sleep -Seconds 2
    Stop-KeepAwake -Cfg $cfg

    $stamp = [ordered]@{ clean_exit = $true; at = (Get-Date).ToString('o') }
    ($stamp | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $cfg.State 'runtime.json') -Encoding UTF8

    # 没有别的发行版在跑，就顺手关掉整个 WSL 虚拟机 —— 否则 vmmemWSL 会一直占着内存
    $others = @(Get-RunningDistroList | Where-Object { $_ -and $_ -ne $cfg.Name })
    if ($others.Count -eq 0) {
        Write-Step "释放 WSL 虚拟机"
        Invoke-Wsl -WslArgs @('--shutdown') -Quiet | Out-Null
        Write-Ok "已关闭 WSL 虚拟机（vmmemWSL 释放）"
    } else {
        Write-Dim ("其它发行版还在跑（{0}），保留虚拟机" -f ($others -join ', '))
    }

    Write-Ok "已停止（数据保留）"
}

function Invoke-Exec {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not (Test-Distro $cfg.Name)) {
        Write-Bad ("抽屉 {0} 还没构建（WSL 里没有这个发行版）" -f $cfg.Name)
        Write-Dim ("先执行: box.ps1 build {0}" -f $cfg.Name)
        return
    }

    Ensure-BoxRunning -Cfg $cfg

    $cmd = @('bash')
    if ($Rest -and $Rest.Count -gt 0) { $cmd = $Rest }

    if ($cfg.Env -and $cfg.Env.Count -gt 0) {
        $envList = @()
        foreach ($k in $cfg.Env.Keys) { $envList += ("{0}={1}" -f $k, $cfg.Env[$k]) }
        $cmd = @('env') + $envList + $cmd
    }

    $wslArgs = @('-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-exec') + $cmd
    & wsl.exe @wslArgs
}

function Invoke-Restore {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $opts = ($Rest -join ' ')
    $cacheOnly = $opts -match '\-CacheOnly'
    $keepGui   = $opts -match '\-KeepGui'

    if ($cacheOnly) { Invoke-Clean -Dir $cfg.Dir; return }

    if ($keepGui) { Write-Dim "保留桌面：重建后会重新预装 pcmanfm / xfce4 / Xephyr" }
    Write-Dim "丢失: 箱内其它软件与配置改动"
    Write-Dim ("保留: {0} 和 {1}" -f $cfg.Data, $cfg.Downloads)

    $yes = $opts -match '\-y'
    if (-not $yes) {
        $ans = Read-Host "确认恢复？(y/N)"
        if ($ans -ne 'y') { Write-Warn "已取消"; return }
    }

    Invoke-Wsl -WslArgs @('--terminate',  $cfg.Name) -Quiet | Out-Null
    Stop-KeepAwake -Cfg $cfg
    Invoke-Wsl -WslArgs @('--unregister', $cfg.Name) -Quiet | Out-Null
    Write-Ok "旧环境已清除"

    $extra = ''
    if ($keepGui) { $extra = 'pcmanfm xfce4 xserver-xephyr x11-utils' }

    Invoke-Build -ExtraPackages $extra
    Write-Ok "恢复完成（data/ 和 downloads/ 未动）"
}

function Invoke-Remove {
    param([string] $Name, [switch] $Yes)

    if (-not $Name) { throw "用法: box.ps1 remove <name> [-y]" }
    $dir = Get-BoxDir $Name
    $cfg = Get-BoxConfig -Dir $dir

    if (-not $Yes) {
        Write-Warn ("将删除抽屉 {0}" -f $cfg.Name)
        Write-Dim ("目录: {0}" -f $dir)
        Write-Dim "会注销 WSL 发行版（连 vhdx）并删除整个目录，包含 data/，不可恢复。"
        $ans = Read-Host "确认请输入 yes"
        if ($ans -ne 'yes') { Write-Dim "已取消"; return }
    }

    Write-Step ("删除 {0}" -f $cfg.Name)
    Stop-KeepAwake -Cfg $cfg

    if (Test-Distro $cfg.Name) {
        Invoke-Wsl -WslArgs @('--terminate', $cfg.Name) -Quiet | Out-Null
        Start-Sleep -Milliseconds 500
        Write-Step "注销发行版"
        $r = Invoke-Wsl -WslArgs @('--unregister', $cfg.Name) -Quiet
        if ($r.Code -ne 0) { Write-Warn ("注销返回 {0}（可能本来就没注册）" -f $r.Code) }
    } else {
        Write-Dim "没有已注册的发行版，跳过注销"
    }

    if (Test-Path -LiteralPath $dir) {
        Write-Step "删除目录"
        Remove-Item -LiteralPath $dir -Recurse -Force
    }

    Unregister-Box $cfg.Name
    Write-Ok ("{0} 已删除" -f $cfg.Name)
}

function Invoke-Rename {
    param([string] $NewName)

    $oldCfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    if (-not $NewName) { throw "用法: box.ps1 rename <旧名> <新名>" }
    if ($NewName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,30}$') { throw "名字不合法（字母数字开头，最长 31）" }
    if (Test-Distro $NewName) { throw "已存在同名发行版: $NewName" }

    $dir = $oldCfg.Dir
    $parent = Split-Path $dir -Parent
    $newDir = Join-Path $parent $NewName
    if (Test-Path -LiteralPath $newDir) { throw "目录已存在: $newDir" }

    Write-Step ("重命名 {0} → {1}" -f $oldCfg.Name, $NewName)
    Invoke-Wsl -WslArgs @('--terminate', $oldCfg.Name) -Quiet | Out-Null

    $tar = Join-Path $env:TEMP ('boxrun-rename-' + [guid]::NewGuid().ToString('N') + '.tar')
    $r = Invoke-Wsl -WslArgs @('--export', $oldCfg.Name, $tar)
    if ($r.Code -ne 0) { throw ("导出失败`n" + ($r.Out -join "`n")) }
    Write-Host "[进度] 40%"

    Invoke-Wsl -WslArgs @('--unregister', $oldCfg.Name) -Quiet | Out-Null
    Move-Item -LiteralPath $dir -Destination $newDir

    $yf = Join-Path $newDir 'box.yaml'
    if (Test-Path -LiteralPath $yf) {
        $y = Get-Content -LiteralPath $yf -Raw -Encoding UTF8
        if ($y -match '(?m)^name:') { $y = [regex]::Replace($y, '(?m)^name:.*$', ("name: " + $NewName)) }
        else { $y = ("name: " + $NewName + "`n" + $y) }
        Set-Content -LiteralPath $yf -Value $y -Encoding UTF8
    }

    $stateDir = Join-Path $newDir 'state'
    if (Test-Path -LiteralPath $stateDir) { Remove-Item -LiteralPath $stateDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $imp = Invoke-Wsl -WslArgs @('--import', $NewName, $stateDir, $tar, '--version', '2')
    Remove-Item -LiteralPath $tar -Force -EA SilentlyContinue
    if ($imp.Code -ne 0) { throw ("导入失败`n" + ($imp.Out -join "`n")) }

    Unregister-Box $oldCfg.Name
    Register-Box $NewName $newDir | Out-Null
    Write-Host "[进度] 100%"
    Write-Ok ("已重命名: {0} → {1}" -f $oldCfg.Name, $NewName)
}
