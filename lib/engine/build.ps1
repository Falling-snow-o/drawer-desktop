# engine/build.ps1 — 构建抽屉

function Invoke-Build {
    param([switch] $Force, [switch] $Fresh, [string] $ExtraPackages)

    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)

    foreach ($d in @($cfg.State, $cfg.Blobs, $cfg.Data, $cfg.Downloads)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    $baseTar = Join-Path $env:USERPROFILE '.boxrun\base-dev.tar.gz'
    $settings = Get-Settings
    $useBase = (-not $Fresh) -and $settings.useBase -and (Test-Path -LiteralPath $baseTar) -and ($cfg.Image -notmatch '^[A-Za-z]:')
    if ($useBase) {
        $img = $baseTar
        Write-Dim ("使用预烘基础镜像: {0}" -f $baseTar)
    } else {

    # --- 1. rootfs ---
    # image 是绝对路径就用本地文件（可以放任意位置），否则按名字去 blobs/ 找并下载
    if ($cfg.Image -match '^[A-Za-z]:[\\/]' -or $cfg.Image -match '^/') {
        $img = $cfg.Image
        if (-not (Test-Path -LiteralPath $img)) { throw ("镜像文件不存在: " + $img) }
        Write-Dim ("使用本地镜像: " + $img)
    } else {
        $img = Join-Path $cfg.Blobs $cfg.Image
    }
    if (-not (Test-Path -LiteralPath $img)) {
        Write-Step "下载 rootfs"
        Write-Dim $cfg.Url
        try {
            Invoke-WebRequest -Uri $cfg.Url -OutFile $img -UseBasicParsing
            $mb = [math]::Round((Get-Item -LiteralPath $img).Length / 1MB, 1)
            Write-Ok ("下载完成 ({0} MB)" -f $mb)
        } catch {
            throw ("下载失败: {0}`n请手动下载后放到: {1}" -f $_.Exception.Message, $img)
        }
    } else {
        $mb = [math]::Round((Get-Item -LiteralPath $img).Length / 1MB, 0)
        Write-Dim ("rootfs 已存在 ({0} MB)" -f $mb)
    }

    Write-Host "[进度] 25%"
    }
    # --- 2. 注册 ---
    if (Test-Distro $cfg.Name) {
        if (-not $Force) {
            Write-Warn ("发行版 '{0}' 已存在，跳过 import（重建加 -Force）" -f $cfg.Name)
            return
        }
        Write-Step "注销旧发行版"
        Invoke-Wsl -WslArgs @('--terminate',  $cfg.Name) -Quiet | Out-Null
        Invoke-Wsl -WslArgs @('--unregister', $cfg.Name) -Quiet | Out-Null
    }

    Write-Host "[进度] 40%"
    Write-Step ("wsl --import → {0}" -f $cfg.State)
    $r = Invoke-Wsl -WslArgs @('--import', $cfg.Name, $cfg.State, $img, '--version', '2')
    if ($r.Code -ne 0) {
        # wsl 失败时会把目标目录一并清掉，重建以便重试
        if (-not (Test-Path -LiteralPath $cfg.State)) {
            New-Item -ItemType Directory -Force -Path $cfg.State | Out-Null
        }
        $hint = ''
        if (($r.Out -join "`n") -match 'HYPERV_NOT_INSTALLED|HCS_E_HYPERV') {
            $hint = @"

诊断: 这台机器的 Windows hypervisor 没有运行（不是 WSL 没装）。
      先确认这两条:
        (Get-CimInstance Win32_ComputerSystem).HypervisorPresent      # 必须是 True
        Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinHvPlatformHost'

      常见原因: 装了 VMware / VirtualBox 并关掉了 hypervisorlaunchtype。
      修复(管理员 + 重启): 见 README.md 顶部，或跑 box.ps1 doctor
"@
        }
        throw ("import 失败`n{0}{1}" -f ($r.Out -join "`n"), $hint)
    }
    Write-Ok "已注册"

    # --- 3. guest 配置 ---
    Write-Step "写入 guest 脚本"
    if ($cfg.StoreType -eq 'bind') {
        Sync-GuestScripts -Distro $cfg.Name -DataPath $cfg.Data -Target $cfg.StoreAt -DownloadsPath $cfg.Downloads `
                          -Cpu $cfg.Cpu -Mem $cfg.Memory -Pids $cfg.Pids
    } else {
        Sync-GuestScripts -Distro $cfg.Name -Cpu $cfg.Cpu -Mem $cfg.Memory -Pids $cfg.Pids
    }

    $wslconf = "[boot]`nsystemd=true`n`n[interop]`nenabled=false`nappendWindowsPath=false`n`n[automount]`nenabled=false`n"
    Set-GuestFile -Distro $cfg.Name -Path '/etc/wsl.conf' -Content $wslconf
    Write-Ok "隔离已加固（interop / automount 关闭）"

    Install-GuestExtras -Cfg $cfg

    $pkgs = $cfg.Packages
    if ($ExtraPackages) { $pkgs = (($pkgs + " " + $ExtraPackages).Trim()) }

    if ($pkgs -and -not $useBase) {
        Set-AptEnv -Cfg $cfg
        Write-Host "[阶段] 安装预置包（首次较慢）"
    Write-Step ("构建期预装: {0}" -f $pkgs)

        # 脚本写文件再执行：wsl.exe 会吃掉命令行里的引号和反斜杠，长脚本走 base64 更稳
        $pre = @'
#!/bin/bash
need=""
for p in __PKGS__;
do
    dpkg -s "$p" >/dev/null 2>&1 || need="$need $p"
done
# 固定附带：wslu（wslview/wslpath）+ zstd（快照压缩）
for p in wslu zstd; do
    dpkg -s "$p" >/dev/null 2>&1 || need="$need $p"
done
if [ -z "$need" ]; then echo "all-installed"; exit 0; fi
mkdir -p /usr/sbin
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
[ -f /etc/boxrun/apt.env ] && . /etc/boxrun/apt.env
export DEBIAN_FRONTEND=noninteractive
MIRROR="${BOXRUN_APT_MIRROR:-tuna}"
case "$MIRROR" in
  official|"none"|"") HOST="" ;;
  tuna)   HOST="mirrors.tuna.tsinghua.edu.cn" ;;
  aliyun) HOST="mirrors.aliyun.com" ;;
  ustc)   HOST="mirrors.ustc.edu.cn" ;;
  *)      HOST="$MIRROR" ;;
esac
set_mirror() {
  host="$1"
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if [ -n "$host" ]; then
      sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu#http://$host/ubuntu#g" "$f"
    else
      sed -i -E "s#https?://[^/ ]+/ubuntu#http://archive.ubuntu.com/ubuntu#g" "$f"
    fi
  done
}
[ -n "$HOST" ] && { set_mirror "$HOST"; echo "MIRROR=$HOST"; }
try_install() {
  timeout 180 apt-get update -qq >/tmp/boxrun-build.log 2>&1 || true
  timeout 1800 apt-get install -y -qq --no-install-recommends \
    -o Dpkg::Lock::Timeout=60 -o Acquire::http::Timeout=30 $need >>/tmp/boxrun-build.log 2>&1
}
if try_install; then
  echo "PREINSTALL_OK"
else
  echo "PREINSTALL_RETRY_OFFICIAL"
  set_mirror ""
  if try_install; then echo "PREINSTALL_OK"; else
    echo "PREINSTALL_FAILED"; tail -n 15 /tmp/boxrun-build.log; exit 1
  fi
fi
'@
        $pre = $pre.Replace('__PKGS__', $pkgs)
        Set-GuestFile -Distro $cfg.Name -Path '/tmp/boxrun-preinstall.sh' -Content $pre
        $mtx = New-Object System.Threading.Mutex($false, 'Local\drawer-apt-cache')
        [void]$mtx.WaitOne(1800000)
        try {
            $inst = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '/tmp/boxrun-preinstall.sh') -Quiet
        } finally {
            try { $mtx.ReleaseMutex() } catch { }
            $mtx.Dispose()
        }
        if ($inst.Code -eq 0) {
            if (($inst.Out -join ' ') -match 'all-installed') { Write-Ok "预装包已存在，跳过" }
            else { Write-Ok "预装完成" }
        } else {
            Write-Warn "预装失败（抽屉还是可用的，之后可手动 apt install）"
        }
    }
    Write-Host "[进度] 90%"
    Write-Step "重启使配置生效"
    Invoke-Wsl -WslArgs @('--terminate', $cfg.Name) -Quiet | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "[进度] 100%"
    # 没启动时也能看系统信息：把 guest 的 os-release 等存一份到 state
    try {
        $g = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-about') -Quiet
        $map = [ordered]@{}
        foreach ($l in $g.Out) {
            $t = $l.Trim(); if (-not $t -or $t -notmatch '=') { continue }
            $p = $t.Split('=', 2); if ($p.Count -eq 2) { $map[$p[0]] = $p[1] }
        }
        if ($map.Count -gt 0) { ($map | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Join-Path $cfg.State 'about.json') -Encoding UTF8 }
    } catch { [Console]::Error.WriteLine("[跳过] " + $_.Exception.Message) }

    Write-Ok "build 完成"
    Write-Dim ("下一步: box.ps1 up {0}" -f $cfg.Name)
}
