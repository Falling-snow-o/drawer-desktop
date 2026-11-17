# engine/base.ps1 — 基础镜像与宿主容量

function Invoke-MakeBase {
    param([string] $SrcBox)
    if (-not $SrcBox) { Write-Bad '用法: box.ps1 make-base <已构建的抽屉>'; return }
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $SrcBox)
    $cache = Join-Path $env:USERPROFILE '.boxrun'
    if (-not (Test-Path -LiteralPath $cache)) { New-Item -ItemType Directory -Force -Path $cache | Out-Null }
    $out = Join-Path $cache 'base-dev.tar.gz'
    Write-Step ("导出基础镜像 ← {0}" -f $cfg.Name)
    Write-Dim '之后新建抽屉直接用它，跳过 rootfs 下载与预装'
    Invoke-Wsl -WslArgs @('--terminate', $cfg.Name) -Quiet | Out-Null
    $r = Invoke-Wsl -WslArgs @('--export', $cfg.Name, $out)
    if ($r.Code -ne 0) { throw ("导出失败`n{0}" -f ($r.Out -join "`n")) }
    $mb = [math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 0)
    Write-Ok ("基础镜像已保存: {0} ({1} MB)" -f $out, $mb)
}

function Assert-HostCapacity {
    param([string] $What = '启动')

    $force = (($Rest -join ' ') -match '\-Force')
    if ($force) { Write-Dim '已指定 -Force，跳过资源检查'; return $true }

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    } catch { return $true }

    $running = @(Get-BoxList | Where-Object { $_.running })
    Write-Dim ("本机内存 可用 {0} / {1} GB；运行中的抽屉 {2} 个" -f $freeGB, $totalGB, $running.Count)

    if ($freeGB -lt 2.0) {
        Write-Bad ("可用内存只剩 {0} GB，再{1}可能把本机拖死" -f $freeGB, $What)
        Write-Dim '先停掉不用的抽屉（box.ps1 down <name>），确认要继续就加 -Force'
        return $false
    }
    if ($running.Count -ge 3) {
        Write-Bad ("已经有 {0} 个抽屉在跑，再开容易吃满内存" -f $running.Count)
        Write-Dim '先停掉不用的抽屉，确认要继续就加 -Force'
        return $false
    }
    return $true
}
