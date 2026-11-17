# engine/toolbox.ps1 — 由 box.ps1 dot-source 加载

function Get-Catalog {
    # 合并三处：内置 → 用户自定义 → 网络缓存
    $sources = @((Join-Path $ScriptRoot 'lib\catalog.json'))
    $user  = Join-Path $env:USERPROFILE '.boxrun\catalog.json'
    $cache = Join-Path $env:USERPROFILE '.boxrun\catalog-cache.json'
    foreach ($p in @($user, $cache)) { if (Test-Path -LiteralPath $p) { $sources += $p } }

    $merged = [ordered]@{ clean = @(); install = @(); plugin = @() }
    $seen = @{}
    foreach ($src in $sources) {
        try { $c = Get-Content -LiteralPath $src -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        foreach ($kind in @('clean','install','plugin')) {
            foreach ($it in @($c.$kind)) {
                if (-not $it -or -not $it.id) { continue }
                $k = "$kind/$($it.id)"
                if ($seen.ContainsKey($k)) { continue }
                $seen[$k] = $true
                $merged[$kind] += $it
            }
        }
    }
    return [pscustomobject]$merged
}

function Invoke-Catalog {
    $c = Get-Catalog
    if (-not $c) { Write-Bad "缺少 catalog.json"; return }

    Write-Head '可选清单'

    Write-Host ("{0}清理{1}   box.ps1 clean <box> -Only id1,id2" -f $Fw.Bold, $Fw.Reset)
    foreach ($i in $c.clean) {
        Write-Host ("  {0,-10} {1,-14} {2,-11} {3}" -f $i.id, $i.name, $i.size, $i.desc)
    }

    Write-Host ""
    Write-Host ("{0}安装{1}   box.ps1 install <box> id1,id2" -f $Fw.Bold, $Fw.Reset)
    foreach ($i in $c.install) {
        Write-Host ("  {0,-10} {1,-14} {2,-11} {3}" -f $i.id, $i.name, $i.size, $i.desc)
    }

    Write-Host ""
    Write-Host ("{0}插件市场{1}   box.ps1 plugin <box> id1,id2" -f $Fw.Bold, $Fw.Reset)
    foreach ($i in $c.plugin) {
        Write-Host ("  {0,-10} {1,-14} {2,-11} {3}" -f $i.id, $i.name, $i.size, $i.desc)
    }
    Write-Host ""
}

function Invoke-CatalogUpdate {
    param([string] $Url)
    if (-not $Url) { $Url = $env:BOXRUN_CATALOG_URL }
    if (-not $Url) {
        Write-Bad '用法: box.ps1 catalog-update <url>'
        Write-Dim '也可以设置环境变量 BOXRUN_CATALOG_URL'
        return
    }
    $cache = Join-Path $env:USERPROFILE '.boxrun\catalog-cache.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $cache) | Out-Null
    $tmp = "$cache.tmp"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
        $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
        Move-Item -LiteralPath $tmp -Destination $cache -Force
        $c = Get-Catalog
        Write-Ok ("目录已更新: {0}" -f $Url)
        Write-Dim ("清理 {0} 项 / 安装 {1} 项 / 插件 {2} 项" -f @($c.clean).Count, @($c.install).Count, @($c.plugin).Count)
    } catch {
        Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue
        Write-Bad ("更新失败: " + $_.Exception.Message)
    }
}

function Invoke-CatalogSources {
    $p = Join-Path $ScriptRoot 'lib\catalog-sources.json'
    if (-not (Test-Path -LiteralPath $p)) { Write-Output '{"sources":[]}'; return }
    Get-Content -LiteralPath $p -Raw -Encoding UTF8
}

function Invoke-CatalogReset {
    $cache = Join-Path $env:USERPROFILE '.boxrun\catalog-cache.json'
    if (Test-Path -LiteralPath $cache) {
        Remove-Item -LiteralPath $cache -Force
        Write-Ok '已删除网络缓存，恢复为内置目录'
    } else {
        Write-Dim '没有网络缓存，当前就是内置目录'
    }
}

function Invoke-Apt {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $pkgs = (($Rest -join ' ')).Trim()
    if (-not $pkgs) { Write-Bad '用法: box.ps1 apt <box> 包名...'; return }
    Ensure-BoxRunning -Cfg $cfg
    Invoke-AptSet -Cfg $cfg -Packages $pkgs -Label '安装软件包'
}

function Invoke-AptSet {
    param($Cfg, [string] $Packages, [string] $Post = '', [string] $Label = '安装')

    Write-Step ("{0}: {1}" -f $Label, $Packages)
    $body = @'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
[ -f /etc/boxrun/apt.env ] && . /etc/boxrun/apt.env
CACHEWIN="__CACHE__"
if [ -n "$CACHEWIN" ]; then
  mkdir -p /var/cache/apt/archives
  mountpoint -q /var/cache/apt/archives || mount -t drvfs "$CACHEWIN" /var/cache/apt/archives -o metadata,uid=0,gid=0,umask=022 2>/dev/null || true
  echo "CACHE=$CACHEWIN mounted=$(mountpoint -q /var/cache/apt/archives && echo yes || echo no)"
fi
MIRROR="${BOXRUN_APT_MIRROR:-tuna}"
case "$MIRROR" in
  official|none|"") HOST="" ;;
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
  timeout 180 apt-get update -qq >/tmp/boxrun-install.log 2>&1 || true
  timeout 1800 apt-get install -y -qq --no-install-recommends \
    -o Dpkg::Lock::Timeout=60 -o Acquire::http::Timeout=30 __PKGS__ >>/tmp/boxrun-install.log 2>&1
}
if try_install; then
  echo "APT_OK"
else
  echo "APT_RETRY_OFFICIAL"
  set_mirror ""
  if try_install; then echo "APT_OK"; else
    echo "APT_FAILED"; tail -n 15 /tmp/boxrun-install.log; exit 1
  fi
fi
__POST__
'@
    Set-AptEnv -Cfg $Cfg
    $aptCache = Join-Path $env:USERPROFILE '.boxrun\apt-cache'
    if (-not (Test-Path -LiteralPath $aptCache)) { New-Item -ItemType Directory -Force -Path $aptCache | Out-Null }
    $cachePath = if ((Get-Settings).aptCache) { ($aptCache -replace '\\', '/') } else { '' }
    $body = $body.Replace('__CACHE__', $cachePath)
    $body = $body.Replace('__PKGS__', $Packages).Replace('__POST__', $Post)
    Set-GuestFile -Distro $Cfg.Name -Path '/tmp/boxrun-install.sh' -Content $body
    $mtx = New-Object System.Threading.Mutex($false, 'Local\drawer-apt-cache')
    [void]$mtx.WaitOne(900000)
    try {
        $r = Invoke-Wsl -WslArgs @('-d', $Cfg.Name, '-u', 'root', '--', 'bash', '/tmp/boxrun-install.sh') -Quiet
    } finally {
        try { $mtx.ReleaseMutex() } catch { }
        $mtx.Dispose()
    }
    foreach ($l in $r.Out) { if ($l.Trim()) { Write-Dim $l } }
    if (($r.Out -join ' ') -match 'APT_OK' -and $r.Code -eq 0) {
        Write-Ok "$Label 完成"
    } else {
        Write-Bad "$Label 失败（箱内 /tmp/boxrun-install.log）"
    }
}

function Invoke-Install {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $ids = (($Rest -join ' ')).Trim()
    if (-not $ids) { Write-Bad "用法: box.ps1 install <box> id1,id2（用 box.ps1 catalog 看清单）"; return }

    if (-not (Test-DistroRunning $cfg.Name)) { Invoke-Up }

    $cat = Get-Catalog
    $pkgs = @()
    foreach ($id in ($ids -split ',')) {
        $it = $cat.install | Where-Object { $_.id -eq $id.Trim() }
        if ($it) { $pkgs += $it.apt } else { Write-Warn ("未知安装项: " + $id) }
    }
    if (-not $pkgs) { return }
    Invoke-AptSet -Cfg $cfg -Packages ($pkgs -join ' ') -Label '安装'
}

function Invoke-Plugin {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $ids = (($Rest -join ' ')).Trim()
    if (-not $ids) { Write-Bad "用法: box.ps1 plugin <box> id1,id2（用 box.ps1 catalog 看插件）"; return }

    if (-not (Test-DistroRunning $cfg.Name)) { Invoke-Up }

    $cat = Get-Catalog
    $apt = @(); $post = @(); $names = @()
    foreach ($id in ($ids -split ',')) {
        $it = $cat.plugin | Where-Object { $_.id -eq $id.Trim() }
        if ($it) {
            if ($it.apt)  { $apt  += $it.apt }
            if ($it.post) { $post += $it.post }
            $names += $it.name
        } else { Write-Warn ("未知插件: " + $id) }
    }
    if (-not $apt -and -not $post) { return }

    Invoke-AptSet -Cfg $cfg -Packages ($apt -join ' ') -Post ($post -join "`n") -Label ('插件 ' + ($names -join ' + '))
}

function Invoke-CacheClear {
    $dir = Join-Path $env:USERPROFILE '.boxrun\apt-cache'
    if (-not (Test-Path -LiteralPath $dir)) { Write-Dim '缓存目录不存在'; return }
    $sum = (Get-ChildItem -LiteralPath $dir -Recurse -File -EA SilentlyContinue | Measure-Object Length -Sum).Sum
    Get-ChildItem -LiteralPath $dir -Recurse -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue
    Write-Ok ("已清空 apt 缓存（释放 {0:N0} MB）" -f (($sum / 1MB)))
}

function Invoke-Clean {
    param([string] $Dir, [string] $Only)

    $boxDir = if ($Dir) { $Dir } else { Get-BoxDir $Box }
    $cfg = Get-BoxConfig -Dir $boxDir

    $wasRunning = Test-DistroRunning $cfg.Name
    if (-not $wasRunning) { Invoke-Up }

    $cat = Get-Catalog
    $cmds = @()
    if ($Only) {
        foreach ($id in ($Only -split ',')) {
            $it = $cat.clean | Where-Object { $_.id -eq $id.Trim() }
            if ($it) { $cmds += $it.cmd; Write-Dim ("清理项: " + $it.name) }
            else { Write-Warn ("未知清理项: " + $id) }
        }
    } else {
        $cmds = @($cat.clean | ForEach-Object { $_.cmd })
        Write-Dim ("未指定 -Only，清理全部 " + $cmds.Count + " 项")
    }
    if (-not $cmds) { return }

    Write-Step "清理缓存（不动已装软件、data、downloads）"
    $body = @"
#!/bin/bash
before=`$(df -m / | awk 'NR==2{print `$4}')
$($cmds -join "`n")
after=`$(df -m / | awk 'NR==2{print `$4}')
echo "freed_mb=`$((after-before))"
df -h / | tail -1
"@
    Set-GuestFile -Distro $cfg.Name -Path '/tmp/boxrun-clean.sh' -Content $body
    $r = Invoke-Wsl -WslArgs @('-d', $cfg.Name, '-u', 'root', '--', 'bash', '/tmp/boxrun-clean.sh') -Quiet
    foreach ($l in $r.Out) { if ($l.Trim()) { Write-Dim $l } }
    Write-Ok "缓存已清理"

    if (-not $wasRunning) {
        Write-Dim '清理前抽屉是停的，重新停掉'
        Invoke-Down
    }
}
