# engine/desktop.ps1 — 由 box.ps1 dot-source 加载

function Invoke-Desktop {
    param([string] $Dir)

    $boxDir = if ($Dir) { $Dir } else { Get-BoxDir $Box }
    $cfg = Get-BoxConfig -Dir $boxDir

    if (-not (Test-Distro $cfg.Name)) {
        Write-Bad ("抽屉 {0} 还没构建" -f $cfg.Name)
        return
    }


    $rest      = ($Rest -join ' ')
    $probeMode = $rest -match '\-Probe'
    $force     = $rest -match '\-Restart'

    if ($probeMode) {
        $chk = Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
            'command -v Xephyr >/dev/null 2>&1 && command -v xfwm4 >/dev/null 2>&1 && echo yes || echo no'
        ) -Quiet
        $needInstall = (($chk.Out -join '') -notmatch 'yes')
        $json = if ($needInstall) { '{"needInstall":true}' } else { '{"needInstall":false}' }
        Write-Output $json
        return
    }
    Ensure-BoxRunning -Cfg $cfg
    if (-not (Assert-HostCapacity -What '再开一个桌面')) { return }
    # 已在运行就不重复拉起（避免多套 Xephyr/XFCE 叠着卡）
    if (-not $force) {
        $runChk = Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
            'pgrep -x Xephyr >/dev/null 2>&1 && pgrep -x xfwm4 >/dev/null 2>&1 && echo running || echo stopped'
        ) -Quiet
        if (($runChk.Out -join '') -match 'running') {
            Write-Ok "桌面已经在运行（要重启用 desktop <name> -Restart）"
            return
        }
    }


    $autoYes = (($Rest -join ' ') -match '\-y')
    $need = 'xfce4 xserver-xephyr x11-utils xdotool arc-theme papirus-icon-theme xclip pulseaudio-utils xfce4-pulseaudio-plugin'

    $probe = Invoke-Wsl -WslArgs @(
        '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
        'command -v Xephyr >/dev/null 2>&1 && command -v xfwm4 >/dev/null 2>&1 && echo yes || echo no'
    ) -Quiet

    if (($probe.Out -join '') -notmatch 'yes') {
        Write-Warn ("抽屉 {0} 里还没有桌面组件（xfce4 + Xephyr，约 400 MB）" -f $cfg.Name)
        $ans = if ($autoYes) { 'y' } else { Read-Host "    现在安装？(y/N)" }
        if ($ans -ne 'y') {
            Write-Dim "用法: box.ps1 desktop <name> [-y]"
            return
        }

    Set-AptEnv -Cfg $cfg
    Write-Host "[阶段] 首次安装桌面组件（约 2-5 分钟）"
        Write-Step "安装桌面组件（首次约 2-5 分钟）"
        $inst = @"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
timeout 180 apt-get update -qq >/tmp/boxrun-desktop.log 2>&1 || true
timeout 1800 apt-get install -y -qq --no-install-recommends -o Dpkg::Lock::Timeout=60 -o Acquire::http::Timeout=30 $need >>/tmp/boxrun-desktop.log 2>&1
"@
        Set-GuestFile -Distro $cfg.Name -Path '/tmp/boxrun-desktop-install.sh' -Content $inst
        $r = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '/tmp/boxrun-desktop-install.sh') -Quiet
        if ($r.Code -ne 0) { Write-Bad "安装失败（箱内 /tmp/boxrun-desktop.log）"; return }
        Write-Ok "桌面组件已装好"
    }

    # 关键：在 WSLg 的 :0 上开一个嵌套 X 服务器 :1，整个桌面画进一个窗口
    Write-Step ("在 {0} 里启动桌面窗口" -f $cfg.Name)
    $runFile = Join-Path $ScriptRoot 'lib\desktop-xfce.sh'
    if (-not (Test-Path -LiteralPath $runFile)) {
        Write-Bad "缺少 desktop-guest.sh"
        return
    }
    # 壁纸走 /work 挂载（大文件不能塞命令行）
    $wall = Join-Path $ScriptRoot 'lib\wall.png'
    if ((Test-Path -LiteralPath $wall) -and (Test-Path -LiteralPath $cfg.Data)) {
        Copy-Item -LiteralPath $wall -Destination (Join-Path $cfg.Data 'boxrun-wall.png') -Force -ErrorAction SilentlyContinue
    }

    Set-GuestFile -Distro $cfg.Name -Path '/etc/boxrun/boxname' -Content $cfg.Name
    $rres = if ($env:BOXRUN_DESKTOP_RES) { $env:BOXRUN_DESKTOP_RES } else { '1600x1000' }
    Set-GuestFile -Distro $cfg.Name -Path '/etc/boxrun/desktop.res' -Content $rres
    $desktopBody = Get-Content -LiteralPath $runFile -Raw -Encoding UTF8
    Set-GuestFile -Distro $cfg.Name -Path '/usr/local/bin/boxrun-desktop.sh' -Content $desktopBody

    # 守护脚本：Xephyr/xfwm4 意外退出时自动重启桌面
    $watchBody = @'
#!/bin/bash
miss=0
while true; do
    sleep 10
    if pgrep -x Xephyr >/dev/null 2>&1 && pgrep -x xfwm4 >/dev/null 2>&1; then
        miss=0
    else
        miss=$((miss+1))
    fi
    if [ "$miss" -ge 3 ]; then
        /usr/local/bin/boxrun-desktop.sh >>/tmp/boxrun-watch.log 2>&1
        miss=0
    fi
done
'@
    Set-GuestFile -Distro $cfg.Name -Path '/usr/local/bin/boxrun-desktop-watch.sh' -Content $watchBody
    Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
        'chmod +x /usr/local/bin/boxrun-desktop.sh /usr/local/bin/boxrun-desktop-watch.sh; systemctl stop boxrun-desktop-watch 2>/dev/null || true') -Quiet | Out-Null

    $r2 = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '/usr/local/bin/boxrun-desktop.sh') -Quiet
    $watchStart = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
        'systemd-run --unit=boxrun-desktop-watch --collect /usr/local/bin/boxrun-desktop-watch.sh') -Quiet
    if ($watchStart.Code -ne 0) {
        Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
            'setsid /usr/local/bin/boxrun-desktop-watch.sh >/dev/null 2>&1 < /dev/null &') -Quiet | Out-Null
    }
    foreach ($l in $r2.Out) { if ($l.Trim()) { Write-Host ("    " + $l) } }

    if (($r2.Out -join ' ') -match 'window=1') {
        Write-Ok ("桌面已开：一个 {0} 的窗口，里面是完整的 XFCE" -f $rres)
    } else {
        Write-Warn "桌面可能没起来，日志：/tmp/boxrun-xephyr.log"
    }
}

function Invoke-Gui {
    param([string] $Dir)

    $boxDir = if ($Dir) { $Dir } else { Get-BoxDir $Box }
    $cfg = Get-BoxConfig -Dir $boxDir

    if (-not (Test-Distro $cfg.Name)) {
        Write-Bad ("抽屉 {0} 还没构建" -f $cfg.Name)
        Write-Dim ("先执行: box.ps1 build {0}" -f $cfg.Name)
        return
    }

    # -y = 不问，直接装（界面调用时用；非交互宿主里 Read-Host 会直接报错）

    $rest = ($Rest -join ' ')
    if ($rest -match '\-Probe') {
        $chk = Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
            'command -v pcmanfm >/dev/null 2>&1 && echo yes || echo no'
        ) -Quiet
        $needInstall = (($chk.Out -join '') -notmatch 'yes')
        $json = if ($needInstall) { '{"needInstall":true}' } else { '{"needInstall":false}' }
        Write-Output $json
        return
    }
    Ensure-BoxRunning -Cfg $cfg
    if (-not (($Rest -join ' ') -match '\-Restart')) {
        $runChk = Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
            'pgrep -x pcmanfm >/dev/null 2>&1 && echo running || echo stopped'
        ) -Quiet
        if (($runChk.Out -join '') -match 'running') {
            Write-Ok '图形界面已经在运行'
            return
        }
    }

    $autoYes = (($Rest -join ' ') -match '\-y')
    $cmd = @()
    foreach ($a in $Rest) { if ($a -ne '-y') { $cmd += $a } }

    if (-not $cmd -or $cmd.Count -eq 0) {
        # 不带参数 = 一键打开文件管理器
        $probe = Invoke-Wsl -WslArgs @(
            '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
            'command -v pcmanfm >/dev/null 2>&1 && echo yes || echo no'
        ) -Quiet

        if (($probe.Out -join '') -notmatch 'yes') {
            Write-Warn ("抽屉 {0} 里还没有图形文件管理器 pcmanfm" -f $cfg.Name)
            $ans = if ($autoYes) { 'y' } else { Read-Host "    现在安装？(y/N)" }
            if ($ans -eq 'y') {
                Write-Step "安装 pcmanfm"
                $i = Invoke-Wsl -WslArgs @(
                    '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
                    'mkdir -p /usr/sbin; printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d; export DEBIAN_FRONTEND=noninteractive; timeout 120 apt-get update -qq >/tmp/boxrun-apt.log 2>&1 || true; timeout 300 apt-get install -y -qq --no-install-recommends -o Dpkg::Lock::Timeout=60 pcmanfm >>/tmp/boxrun-apt.log 2>&1'
                ) -Quiet
                if ($i.Code -ne 0) {
                    Write-Bad "安装失败"
                    foreach ($l in $i.Out) { if ($l.Trim()) { Write-Dim $l } }
                    return
                }
                Write-Ok "pcmanfm 已装好"
            } else {
                Write-Dim "用法: box.ps1 gui <name> <程序> [参数...]"
                return
            }
        }
        # 默认走 X11：Wayland 下部分 GTK 程序不出窗口（PITFALLS 7.5）
        $cmd = @('env', 'GDK_BACKEND=x11', 'pcmanfm', '/')
    }

    Write-Step ("在 {0} 里启动图形程序: {1}" -f $cfg.Name, ($cmd -join ' '))
    $r = Invoke-Wsl -WslArgs (@(
        '-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-gui'
    ) + $cmd) -Quiet

    foreach ($l in $r.Out) { if ($l.Trim()) { Write-Host ("    " + $l) } }

    if ($r.Code -eq 0) {
        Write-Ok "窗口由 WSLg 画在 Windows 桌面上，进程还在抽屉里"
        Write-Dim "关掉窗口就等于结束进程；日志: /tmp/boxrun-gui.log"
    } else {
        Write-Warn ("启动失败（返回 {0}）" -f $r.Code)
    }
}

function New-GuiShortcut {
    param([string] $BoxDir, [string] $BoxName)

    $ico = Join-Path $ScriptRoot 'boxrun.ico'
    $csExe = Join-Path $env:LOCALAPPDATA 'boxrun\BoxRun.exe'
    if (-not (Test-Path -LiteralPath $csExe)) { $csExe = Join-Path $env:USERPROFILE 'boxrun\BoxRun.exe' }
    if (-not (Test-Path -LiteralPath $csExe)) { return }

    $startLnk = Join-Path $BoxDir '启动.lnk'
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($startLnk)
        $sc.TargetPath = $csExe
        $sc.Arguments = ''
        $sc.WorkingDirectory = $BoxDir
        if (Test-Path -LiteralPath $ico) { $sc.IconLocation = $ico + ',0' }
        $sc.Description = 'boxrun 管理器'
        $sc.Save()
        Write-Dim ("已创建: {0}" -f $startLnk)
    } catch {
        Write-Dim "快捷方式创建失败（不影响使用）"
    }
}
