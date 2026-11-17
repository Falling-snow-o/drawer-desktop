# engine/add.ps1 — 登记/初始化抽屉

function Invoke-Add {
    param([string] $Path, [string] $Name, [string] $Image)

    if (-not $Path) { throw "用法: box.ps1 add <目录> [-Name 名字] [-Image 本地rootfs.tar.gz]" }
    $dir = [IO.Path]::GetFullPath($Path)
    $boxName = if ($Name) { $Name } else { Split-Path $dir -Leaf }

    # 目录权限自检：先确认能写，再往下建
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
        $probe = Join-Path $dir ('.boxrun-probe-' + [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
    } catch {
        Write-Bad ("目录不可写: " + $dir)
        Write-Dim ("原因: " + $_.Exception.Message)
        Write-Dim '换一个目录（建议在 D:\Acta\boxes 或用户目录下），或给当前用户授权：'
        Write-Dim ('icacls "' + $dir + '" /grant "' + $env:USERNAME + ':(OI)(CI)F" /T')
        return
    }

    if ($Image) {
        $imgFull = [IO.Path]::GetFullPath($Image)
        try { $fsr = [IO.File]::OpenRead($imgFull); $fsr.Dispose() }
        catch {
            Write-Bad ("rootfs 文件读不了: " + $imgFull)
            Write-Dim ("原因: " + $_.Exception.Message)
            Write-Dim "把它复制到普通目录（如 D:\Acta）再添加，或解除文件属性里的“阻止”"
            return
        }
    }

    foreach ($sub in @('state','blobs','data','downloads')) {
        $p = Join-Path $dir $sub
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p -ErrorAction Stop | Out-Null }
    }

    $yamlPath = Join-Path $dir 'box.yaml'
    if (-not (Test-Path -LiteralPath $yamlPath)) {
        $tpl = Join-Path $ScriptRoot 'examples\box.yaml'
        $yaml = Get-Content -LiteralPath $tpl -Raw -Encoding UTF8
        $yaml = $yaml -replace '(?m)^name:.*$', ("name: " + $boxName)
        if ($Image) {
            $img = [IO.Path]::GetFullPath($Image)
            if (-not (Test-Path -LiteralPath $img)) { throw ("找不到镜像文件: " + $img) }
            $yaml = $yaml -replace '(?m)^(\s*)image:.*$', ('$1image: ' + $img)
            $yaml = $yaml -replace '(?m)^(\s*)url:.*$',   '$1url: '
        }
        Set-Content -LiteralPath $yamlPath -Value $yaml -Encoding UTF8
    }

    [void](Register-Box $boxName $dir)
    Write-Ok ("已登记 {0} → {1}" -f $boxName, $dir)
    Write-Dim "下一步: box.ps1 build $boxName"
}

function Invoke-Init {
    param([string] $Name, [string] $Cpu, [string] $Memory, [string] $Pids)

    if (-not $Name) { throw "用法: box.ps1 init <name> [-cpu 核数] [-memory 6G] [-pids 512]" }
    $dir = Join-Path $BoxesRoot $Name
    if (Test-Path -LiteralPath $dir) { throw "已存在: $dir" }

    # 配额：没指定就按本机规格算一套
    $rec = Get-RecommendedQuota

    $cores = $rec.CpuCores
    if ($Cpu) { [void][int]::TryParse([string]$Cpu, [ref]$cores) }
    if ($cores -lt 1) { $cores = 1 }
    $cpuQuota = ('{0} 100000' -f ($cores * 100000))

    $mem = $rec.Memory
    if ($Memory -match '^\d+(\.\d+)?\s*G$') { $mem = ($Memory -replace '\s', '') }

    $pidsMax = $rec.Pids
    if ($Pids) { [void][int]::TryParse([string]$Pids, [ref]$pidsMax) }
    if ($pidsMax -lt 16) { $pidsMax = 16 }

    foreach ($d in @($dir, (Join-Path $dir 'state'), (Join-Path $dir 'blobs'), (Join-Path $dir 'data'), (Join-Path $dir 'downloads'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    $tpl  = Join-Path $ScriptRoot 'examples\box.yaml'
    if (Test-Path -LiteralPath $tpl) {
        $yaml = Get-Content -LiteralPath $tpl -Raw -Encoding UTF8
        $yaml = $yaml -replace '(?m)^name:.*$', ("name: " + $Name)
        $yaml = $yaml -replace '(?m)^(\s*)cpu:.*$',   ('$1cpu: '    + $cpuQuota)
        $yaml = $yaml -replace '(?m)^(\s*)memory:.*$', ('$1memory: ' + $mem)
        $yaml = $yaml -replace '(?m)^(\s*)pids:.*$',  ('$1pids: '   + $pidsMax)
        Set-Content -LiteralPath (Join-Path $dir 'box.yaml') -Value $yaml -Encoding UTF8
    } else {
        throw "缺少模板: $tpl"
    }

    Write-Ok "已创建: $dir"
    Write-Dim ("配额: {0} 核 / {1} 内存 / {2} 进程" -f $cores, $mem, $pidsMax)
    Write-Dim ("本机: {0} 逻辑核 / {1} GB 内存 —— 建议值按 1/4 核、40% 内存算" -f $rec.HostCores, $rec.HostRamGB)
    New-GuiShortcut -BoxDir $dir -BoxName $Name
    Write-Dim "下一步: box.ps1 build $Name"
}
