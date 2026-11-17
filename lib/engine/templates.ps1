# engine/templates.ps1 — clone / template / 导出应用

function Invoke-Clone {
    param([string] $SrcName, [string] $NewName, [string] $TargetDir)

    if (-not $SrcName -or -not $NewName) { Write-Bad '用法: box.ps1 clone <源抽屉> <新名字> [-Dir <目录>]'; return }

    $srcDir = Get-BoxDir $SrcName
    $src = Get-BoxConfig -Dir $srcDir

    if (Test-Distro $NewName) { Write-Bad ("WSL 里已经有叫 {0} 的发行版" -f $NewName); return }
    if (Test-DistroRunning $src.Name) {
        Write-Warn ("先停止源抽屉 {0}" -f $src.Name)
        Write-Dim ("box.ps1 down {0}" -f $src.Name)
        return
    }

    if (-not $TargetDir) { $TargetDir = Join-Path $BoxesRoot $NewName }
    $dst = [IO.Path]::GetFullPath($TargetDir)
    if ((Test-Path -LiteralPath $dst) -and (Get-ChildItem -LiteralPath $dst -Force -EA SilentlyContinue)) {
        Write-Bad ("目标目录非空: " + $dst); return
    }

    $srcVhd = Get-ChildItem -LiteralPath $src.State -Filter '*.vhdx' -EA SilentlyContinue |
              Sort-Object Length -Descending | Select-Object -First 1
    if (-not $srcVhd) { Write-Bad ("源抽屉里找不到 vhdx: " + $src.State); return }

    Write-Step ("克隆 {0} → {1}" -f $src.Name, $NewName)
    foreach ($d in @($dst, (Join-Path $dst 'state'), (Join-Path $dst 'blobs'), (Join-Path $dst 'data'), (Join-Path $dst 'downloads'))) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    # 1) 复制配置并改名
    $yaml = Get-Content -LiteralPath (Join-Path $src.Dir 'box.yaml') -Raw -Encoding UTF8
    $yaml = $yaml -replace '(?m)^name:.*$', ("name: " + $NewName)
    Set-Content -LiteralPath (Join-Path $dst 'box.yaml') -Value $yaml -Encoding UTF8

    # 2) 复制 vhdx
    $dstVhd = Join-Path $dst 'clone.vhdx'
    Write-Step ("复制磁盘 {0:N0} MB" -f ($srcVhd.Length / 1MB))
    Copy-Item -LiteralPath $srcVhd.FullName -Destination $dstVhd -Force

    # 3) 注册
    Write-Step "注册新发行版"
    $imp = Invoke-Wsl -WslArgs @('--import', $NewName, (Join-Path $dst 'state'), $dstVhd, '--version', '2', '--vhd') -Quiet
    if ($imp.Code -ne 0) {
        foreach ($l in $imp.Out) { if ($l.Trim()) { Write-Dim $l } }
        Write-Bad "导入失败，清理目录"
        Remove-Item -LiteralPath $dst -Recurse -Force -EA SilentlyContinue
        return
    }

    Remove-Item -LiteralPath $dstVhd -Force -EA SilentlyContinue
    [void](Register-Box $NewName $dst)
    Write-Ok ("克隆完成: {0} → {1}" -f $src.Name, $dst)
    Write-Dim ("下一步: box.ps1 up {0}" -f $NewName)
}

function Invoke-Template {
    param([string] $Action, [string] $Arg1, [string] $Arg2)

    $tplDir = Join-Path $ScriptRoot 'templates'
    if (-not (Test-Path -LiteralPath $tplDir)) { New-Item -ItemType Directory -Force -Path $tplDir | Out-Null }

    switch ($Action) {
        'export' {
            if (-not $Arg1) { Write-Bad '用法: box.ps1 template export <抽屉> [-Out 文件.tar.gz]'; return }
            $cfg = Get-BoxConfig -Dir (Get-BoxDir $Arg1)
            $outFile = if ($Arg2) { [IO.Path]::GetFullPath($Arg2) } else { Join-Path $tplDir ($cfg.Name + '.tar.gz') }

            $stage = Join-Path $env:TEMP ('boxrun-tpl-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $stage | Out-Null
            Copy-Item -LiteralPath (Join-Path $cfg.Dir 'box.yaml') -Destination (Join-Path $stage 'box.yaml')
            $meta = [pscustomobject]@{
                name = $cfg.Name; version = '1'; created = (Get-Date).ToString('s')
                packages = $cfg.Packages; image = $cfg.Image; url = $cfg.Url
            }
            $meta['version'] = '1.0.0'
        ($meta | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $stage 'template.json') -Encoding UTF8

            if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }
            & tar.exe -czf $outFile -C $stage .
            Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue
            Write-Ok ("模板已导出: " + $outFile)
            Write-Dim ("别人用: box.ps1 template apply """ + $outFile + """ <新名字>")
        }
        'list' {
            $files = @(Get-ChildItem -LiteralPath $tplDir -Filter '*.tar.gz' -EA SilentlyContinue)
            if ($files.Count -eq 0) { Write-Dim '还没有模板'; return }
            Write-Step "本机模板"
            foreach ($f in $files) { Write-Host ("  {0}  ({1:N0} KB)" -f $f.Name, ($f.Length / 1KB)) }
        }
        'apply' {
            if (-not $Arg1 -or -not $Arg2) { Write-Bad '用法: box.ps1 template apply <模板文件> <新抽屉名>'; return }
            if (-not (Test-Path -LiteralPath $Arg1)) { Write-Bad ("模板不存在: " + $Arg1); return }
            if (Test-Distro $Arg2) { Write-Bad ("名字已存在: " + $Arg2); return }

            $stage = Join-Path $env:TEMP ('boxrun-tpl-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $stage | Out-Null
            & tar.exe -xzf $Arg1 -C $stage
            $tplYaml = Join-Path $stage 'box.yaml'
            if (-not (Test-Path -LiteralPath $tplYaml)) { Write-Bad '模板里没有 box.yaml'; Remove-Item $stage -Recurse -Force; return }

            $dst = Join-Path $BoxesRoot $Arg2
            foreach ($d in @($dst, (Join-Path $dst 'state'), (Join-Path $dst 'blobs'), (Join-Path $dst 'data'), (Join-Path $dst 'downloads'))) {
                if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
            }
            $yaml = Get-Content -LiteralPath $tplYaml -Raw -Encoding UTF8
            $yaml = $yaml -replace '(?m)^name:.*$', ("name: " + $Arg2)
            Set-Content -LiteralPath (Join-Path $dst 'box.yaml') -Value $yaml -Encoding UTF8
            Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue

            [void](Register-Box $Arg2 $dst)
            Write-Ok ("已从模板创建: {0} → {1}" -f $Arg2, $dst)
            Write-Dim ("下一步: box.ps1 build {0}" -f $Arg2)
        }
        default { Write-Dim '用法: box.ps1 template list | export <抽屉> [-Out 文件] | apply <文件> <新名字>' }
    }
}

function Invoke-ExportApp {
    param([string]$Name, [string]$Command)
    if (-not $Name) { $Name = $Box }
    if (-not $Command) { $Command = 'xfce4-terminal' }
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $dir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Drawer'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lnkPath = Join-Path $dir (($Name -replace '[\\/:*?""<>|]', '_') + '.lnk')
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = (Join-Path $env:WINDIR 'System32\wsl.exe')
    $lnk.Arguments = "-d $($cfg.Name) -- $Command"
    $lnk.WorkingDirectory = $env:WINDIR
    $lnk.Description = "Drawer: $($Box) - $Name"
    $lnk.Save()
    Write-Host ("  快捷方式: " + $lnkPath) -ForegroundColor Green
}
