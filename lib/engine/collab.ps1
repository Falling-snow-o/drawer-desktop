# engine/collab.ps1 — 协同模式：data/ 用 git，环境用包清单

function Invoke-CollabGit {
    param([string] $Dir, [string[]] $GitArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Dir @GitArgs 2>&1 | ForEach-Object { [string]$_ }
    } finally {
        $ErrorActionPreference = $old
    }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = @($out) }
}

function Get-CollabDataDir {
    param($Cfg)
    return $Cfg.Data
}

function Get-CollabStateDir {
    param($Cfg)
    $d = Join-Path $Cfg.State 'collab'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    return $d
}

function Get-CollabManifestPath {
    param($Cfg)
    return Join-Path (Get-CollabStateDir $Cfg) 'packages.txt'
}

function Get-CollabPackages {
    param($Cfg)
    if (-not (Test-Distro $Cfg.Name)) { return $null }
    $r = Invoke-Wsl -WslArgs @('-d', $Cfg.Name, '-u', 'root', '--', 'dpkg', '--get-selections') -Quiet
    if ($r.Code -ne 0) { return $null }
    $list = @()
    foreach ($line in $r.Out) {
        $t = ([string]$line).Trim()
        if (-not $t) { continue }
        $parts = $t -split '\s+'
        if ($parts.Count -ge 2 -and $parts[1] -eq 'install') { $list += $parts[0] }
    }
    return @($list | Sort-Object -Unique)
}

function Save-CollabManifest {
    param($Cfg)
    $pkgs = Get-CollabPackages $Cfg
    if ($null -eq $pkgs) { Write-Warn '抽屉未构建，跳过环境清单'; return $false }
    $file = Get-CollabManifestPath $Cfg
    Set-Content -LiteralPath $file -Value ($pkgs -join "`n") -Encoding UTF8
    Write-Ok ("环境清单已保存: " + $pkgs.Count + " 个包")
    return $true
}

function Invoke-Collab {
    $action = if ($Rest.Count -gt 0) { [string]$Rest[0] } else { 'status' }
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
    $data = Get-CollabDataDir $cfg

    if (-not (Test-Path -LiteralPath $data)) { throw ("data 目录不存在: " + $data) }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { throw '未找到 git.exe，请先安装 Git for Windows' }

    switch ($action) {
        'init' {
            $remote = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }

            if (-not (Test-Path -LiteralPath (Join-Path $data '.git'))) {
                $r = Invoke-CollabGit $data @('init', '-q')
                if ($r.Code -ne 0) { throw ("git init 失败: " + ($r.Out -join "`n")) }
                Write-Ok 'data/ 已初始化 git 仓库'
            }

            # 仓库级身份（不依赖全局 git 配置）
            Invoke-CollabGit $data @('config', 'user.name', 'Drawer Collab') | Out-Null
            Invoke-CollabGit $data @('config', 'user.email', 'collab@localhost') | Out-Null

            $r = Invoke-CollabGit $data @('add', '-A')
            if ($r.Code -ne 0) { throw ("git add 失败: " + ($r.Out -join "`n")) }

            $r = Invoke-CollabGit $data @('commit', '-q', '--allow-empty', '-m', 'drawer: 初始化协同仓库')
            if ($r.Code -eq 0) {
                $head = Invoke-CollabGit $data @('rev-parse', '--short', 'HEAD')
                Write-Ok ("已提交: " + $head.Out)
            } elseif (($r.Out -join "`n") -match 'nothing to commit') {
                Write-Dim '没有需要提交的改动'
            } else {
                Write-Warn ("提交失败: " + ($r.Out -join "`n"))
            }

            Write-Dim ('remote 参数: ' + $remote)
            if ($remote) {
                $existing = Invoke-CollabGit $data @('remote', 'get-url', 'origin')
                if ($existing.Code -eq 0) { Invoke-CollabGit $data @('remote', 'remove', 'origin') | Out-Null }
                $r = Invoke-CollabGit $data @('remote', 'add', 'origin', $remote)
                if ($r.Code -ne 0) { throw ("添加远端失败: " + ($r.Out -join "`n")) }
                Write-Dim ("远端: " + $remote)
                $brr = Invoke-CollabGit $data @('branch', '--show-current')
                $br = $brr.Out
                $r = Invoke-CollabGit $data @('push', '-u', 'origin', $br)
                if ($r.Code -ne 0) { Write-Warn ("推送失败（可稍后 collab sync）: " + ($r.Out -join "`n")) }
                else { Write-Ok ("已推送到 " + $remote) }
            }

            Save-CollabManifest $cfg | Out-Null
        }

        'status' {
            $r = Invoke-CollabGit $data @('status', '--short', '--branch')
            foreach ($l in $r.Out) { Write-Host $l }
            $rr = Invoke-CollabGit $data @('remote', 'get-url', 'origin')
            $remote = $rr.Out
            if ($remote) { Write-Dim ("远端: " + $remote) } else { Write-Dim '未配置远端（collab init <box> <remote>）' }

            $mf = Get-CollabManifestPath $cfg
            if (Test-Path -LiteralPath $mf) {
                $pkgs = Get-CollabPackages $cfg
                if ($pkgs) {
                    $base = @(Get-Content -LiteralPath $mf -Encoding UTF8)
                    $diff = Compare-Object -ReferenceObject $base -DifferenceObject $pkgs
                    if ($diff) { Write-Dim ("环境相对基线有 " + @($diff).Count + " 项差异（collab env-diff）") }
                    else { Write-Dim '环境与基线一致' }
                }
            }
        }

        'sync' {
            $msg = 'drawer: sync'
            for ($i = 1; $i -lt $Rest.Count; $i++) {
                if ($Rest[$i] -eq '-m' -and $i + 1 -lt $Rest.Count) { $msg = [string]$Rest[$i + 1]; $i++ }
            }

            Invoke-CollabGit $data @('add', '-A') | Out-Null
            $r = Invoke-CollabGit $data @('commit', '-q', '-m', $msg)
            if ($r.Code -eq 0) { Write-Ok ("已提交: " + $msg) } else { Write-Dim '没有需要提交的改动' }

            $rr = Invoke-CollabGit $data @('remote', 'get-url', 'origin')
            $remote = $rr.Out
            if ($remote) {
                $brr = Invoke-CollabGit $data @('branch', '--show-current')
                $br = $brr.Out
                $r = Invoke-CollabGit $data @('pull', '--rebase', 'origin', $br)
                if ($r.Code -ne 0) { Write-Warn ("拉取冲突，先手动解决: " + ($r.Out -join "`n")); return }
                $r = Invoke-CollabGit $data @('push', 'origin', $br)
                if ($r.Code -ne 0) { Write-Warn ("推送失败: " + ($r.Out -join "`n")); return }
                Write-Ok '已同步到远端'
            } else {
                Write-Dim '未配置远端，仅本地提交'
            }

            Save-CollabManifest $cfg | Out-Null
        }

        'env-save' {
            Save-CollabManifest $cfg | Out-Null
        }

        'env-diff' {
            $mf = Get-CollabManifestPath $cfg
            if (-not (Test-Path -LiteralPath $mf)) { Write-Bad '还没有基线，先 collab env-save'; return }
            $pkgs = Get-CollabPackages $cfg
            if ($null -eq $pkgs) { Write-Bad '抽屉未构建，无法读取包清单'; return }
            $base = @(Get-Content -LiteralPath $mf -Encoding UTF8)
            $diff = Compare-Object -ReferenceObject $base -DifferenceObject $pkgs
            if (-not $diff) { Write-Ok '环境与基线一致'; return }
            foreach ($d in $diff) {
                if ($d.SideIndicator -eq '=>') { Write-Host ("  + " + $d.InputObject) }
                else { Write-Host ("  - " + $d.InputObject) }
            }
        }

        'env-apply' {
            $file = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }
            if (-not $file -or -not (Test-Path -LiteralPath $file)) { Write-Bad '用法: collab <box> env-apply <清单文件>'; return }
            $want = @(Get-Content -LiteralPath $file -Encoding UTF8 | Where-Object { $_.Trim() })
            $have = Get-CollabPackages $cfg
            if ($null -eq $have) { Write-Bad '抽屉未构建'; return }
            $missing = @($want | Where-Object { $have -notcontains $_ })
            if (-not $missing) { Write-Ok '环境已满足清单'; return }
            Write-Step ("补装 " + $missing.Count + " 个包")
            Invoke-AptSet -Cfg $cfg -Packages ($missing -join ' ') -Label '协同补装'
            Save-CollabManifest $cfg | Out-Null
        }

        'merge' {
            $branch = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }
            if (-not $branch) { Write-Bad '用法: collab <box> merge <远端分支>'; return }
            $rr = Invoke-CollabGit $data @('remote', 'get-url', 'origin')
            $remote = $rr.Out
            if (-not $remote) { Write-Bad '未配置远端'; return }

            $r = Invoke-CollabGit $data @('fetch', 'origin')
            if ($r.Code -ne 0) { Write-Bad ("fetch 失败: " + ($r.Out -join "`n")); return }

            $r = Invoke-CollabGit $data @('merge', '--no-edit', ("origin/" + $branch))
            if ($r.Code -ne 0) {
                Write-Warn '合并有冲突，需要手动解决：'
                $cr = Invoke-CollabGit $data @('diff', '--name-only', '--diff-filter=U')
                $conf = $cr.Out
                foreach ($c in $conf) { Write-Host ("  ! " + $c) }
                Write-Dim ("在 " + $data + " 里解决后 git add/commit")
            } else {
                Write-Ok ("已合并 origin/" + $branch)
            }
        }

        default {
            Write-Bad ("未知 collab 动作: " + $action)
            Write-Dim '可用: init / status / sync / env-save / env-diff / env-apply / merge'
        }
    }
}
