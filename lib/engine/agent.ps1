# engine/agent.ps1 — Agent 任务：宿主目录事务 + 步骤记录
# 用法:
#   box.ps1 agent <box> begin <hostDir> [name]
#   box.ps1 agent <box> exec  <taskId> <command>
#   box.ps1 agent <box> end   <taskId> commit|rollback
#   box.ps1 agent <box> list
#   box.ps1 agent <box> show  <taskId>

function Get-AgentRoot {
    $root = Join-Path $env:LOCALAPPDATA 'Drawer\tasks'
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
    return $root
}

function Read-AgentTask([string] $Id) {
    $f = Join-Path (Join-Path (Get-AgentRoot) $Id) 'task.json'
    if (-not (Test-Path -LiteralPath $f)) { throw ("找不到任务: " + $Id) }
    return Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-AgentTask($Task) {
    $dir = Join-Path (Get-AgentRoot) $Task.id
    $json = $Task | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $dir 'task.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-AgentStep($Task, $Step) {
    $dir = Join-Path (Get-AgentRoot) $Task.id
    $line = $Step | ConvertTo-Json -Compress -Depth 6
    Add-Content -LiteralPath (Join-Path $dir 'steps.jsonl') -Value $line -Encoding UTF8
}

function Invoke-AgentGit($Task, [string[]] $GitArgs) {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { return [pscustomobject]@{ Code = 127; Out = @('git not found') } }
    $base = @(
        '-c', 'user.name=Drawer Agent',
        '-c', 'user.email=agent@localhost',
        ('--git-dir=' + (Join-Path $Task.dir 'track.git')),
        ('--work-tree=' + (Join-Path $Task.dir 'work'))
    ) + $GitArgs
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & git.exe @base 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $code; Out = @($out | ForEach-Object { "$_" }) }
}

function Set-AgentWork($Task, [string] $Path) {
    $cfg = Get-BoxConfig -Dir (Get-BoxDir $Task.box)
    Set-GuestFile -Distro $cfg.Name -Path '/etc/boxrun/work.src' -Content $Path
    Invoke-Wsl -WslArgs @(
        '-d', $cfg.Name, '-u', 'root', '--', 'bash', '-c',
        'umount -l /work 2>/dev/null || true; rm -rf /work 2>/dev/null || true; mkdir -p /work; /usr/local/bin/boxrun-work >/dev/null 2>&1 || true'
    ) -Quiet | Out-Null
}

function Invoke-Agent {
    $action = if ($Rest.Count -gt 0) { [string]$Rest[0] } else { 'list' }

    switch ($action) {
        'begin' {
            $hostDir = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }
            if (-not $hostDir -or -not (Test-Path -LiteralPath $hostDir)) { throw '用法: box.ps1 agent <box> begin <hostDir> [name]' }
            $hostDir = (Resolve-Path -LiteralPath $hostDir).Path
            $name = if ($Rest.Count -gt 2) { [string]$Rest[2] } else { (Split-Path $hostDir -Leaf) }
            $cfg = Get-BoxConfig -Dir (Get-BoxDir $Box)
            if (-not (Test-Distro $cfg.Name)) { throw ('抽屉还没构建: ' + $cfg.Name) }

            $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + (Get-Random -Maximum 9999)
            $dir = Join-Path (Get-AgentRoot) $id
            $work = Join-Path $dir 'work'
            New-Item -ItemType Directory -Force -Path $work | Out-Null

            & robocopy $hostDir $work /E /XD .git /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
            if ($LASTEXITCODE -ge 8) { throw ('复制目录失败: ' + $hostDir) }

            $task = [pscustomobject]@{
                id = $id; box = $cfg.Name; name = $name; host = $hostDir
                dir = $dir; work = $work
                status = 'running'; started = (Get-Date).ToString('s')
                baseline = ''; seq = 0
            }

            & git.exe init --bare -q (Join-Path $dir 'track.git') | Out-Null
            $r = Invoke-AgentGit $task @('add', '-A')
            if ($r.Code -ne 0) { throw ('git add 失败: ' + ($r.Out -join "`n")) }
            $r = Invoke-AgentGit $task @('commit', '-q', '--allow-empty', '-m', 'baseline')
            if ($r.Code -ne 0) { throw ('git commit 失败: ' + ($r.Out -join "`n")) }
            $task.baseline = (Invoke-AgentGit $task @('rev-parse', 'HEAD')).Out[0]

            Write-AgentTask $task
            Ensure-BoxRunning -Cfg $cfg
            Set-AgentWork $task $work
            Write-Ok ('任务已开始: ' + $id)
            Write-Dim ('工作目录: ' + $hostDir + '  ->  /work（暂存）')
            Write-Output (ConvertTo-Json -Compress -InputObject $task)
        }

        'exec' {
            $id = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }
            $cmd = if ($Rest.Count -gt 2) { ($Rest[2..($Rest.Count - 1)] -join ' ') } else { '' }
            if (-not $id -or -not $cmd) { throw '用法: box.ps1 agent <box> exec <taskId> <command>' }
            $task = Read-AgentTask $id
            if ($task.status -ne 'running') { throw ('任务已结束: ' + $task.status) }
            $cfg = Get-BoxConfig -Dir (Get-BoxDir $task.box)

            Ensure-BoxRunning -Cfg $cfg
            Set-AgentWork $task $task.work

            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-Wsl -WslArgs @(
                '-d', $cfg.Name, '-u', 'root', '--', '/usr/local/bin/boxrun-exec',
                'bash', '-lc', ('cd /work && ' + $cmd)
            ) -Quiet
            $sw.Stop()
            $out = ($r.Out -join "`n").TrimEnd()

            $task.seq = [int]$task.seq + 1
            $prev = (Invoke-AgentGit $task @('rev-parse', 'HEAD')).Out[0]
            Invoke-AgentGit $task @('add', '-A') | Out-Null
            Invoke-AgentGit $task @('commit', '-q', '--allow-empty', '-m', ('step ' + $task.seq)) | Out-Null
            $head = (Invoke-AgentGit $task @('rev-parse', 'HEAD')).Out[0]

            $changed = @()
            $diffStat = ''
            if ($prev -and $head) {
                $changed = @((Invoke-AgentGit $task @('diff', '--name-only', ($prev + '..' + $head))).Out | Where-Object { $_ })
                $diffStat = ((Invoke-AgentGit $task @('diff', '--stat', ($prev + '..' + $head))).Out -join "`n").Trim()
            }

            $tail = if ($out.Length -gt 8000) { $out.Substring($out.Length - 8000) } else { $out }
            $step = [pscustomobject]@{
                seq = $task.seq; cmd = $cmd; exit = $r.Code
                ms = [int]$sw.ElapsedMilliseconds; changed = $changed
                diff = $diffStat; output = $tail; at = (Get-Date).ToString('s')
            }
            Add-AgentStep $task $step
            Write-AgentTask $task

            Write-Ok ('步骤 ' + $task.seq + ' 完成，exit=' + $r.Code + '，改动 ' + $changed.Count + ' 个文件')
            if ($out) { Write-Host $out }
            Write-Output (ConvertTo-Json -Compress -InputObject $step)
        }

        'end' {
            $id = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }
            $mode = if ($Rest.Count -gt 2) { [string]$Rest[2] } else { '' }
            if (-not $id -or $mode -notin @('commit', 'rollback')) { throw '用法: box.ps1 agent <box> end <taskId> commit|rollback' }
            $task = Read-AgentTask $id
            if ($task.status -ne 'running') { throw ('任务已结束: ' + $task.status) }
            $cfg = Get-BoxConfig -Dir (Get-BoxDir $task.box)

            if ($mode -eq 'commit') {
                $head = (Invoke-AgentGit $task @('rev-parse', 'HEAD')).Out[0]
                $names = @((Invoke-AgentGit $task @('diff', '--name-status', ($task.baseline + '..' + $head))).Out | Where-Object { $_ })
                $applied = 0
                foreach ($line in $names) {
                    $parts = $line -split "`t"
                    if ($parts.Count -lt 2) { continue }
                    $st = $parts[0]
                    if ($st -eq 'D') {
                        $dst = Join-Path $task.host $parts[1]
                        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
                        $applied++
                    } elseif ($st -like 'R*' -and $parts.Count -ge 3) {
                        $old = Join-Path $task.host $parts[1]
                        $new = Join-Path $task.host $parts[2]
                        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
                        New-Item -ItemType Directory -Force -Path (Split-Path $new -Parent) | Out-Null
                        Copy-Item -LiteralPath (Join-Path $task.work $parts[2]) -Destination $new -Force
                        $applied++
                    } else {
                        $src = Join-Path $task.work $parts[1]
                        $dst = Join-Path $task.host $parts[1]
                        if (Test-Path -LiteralPath $src) {
                            New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
                            Copy-Item -LiteralPath $src -Destination $dst -Force
                            $applied++
                        }
                    }
                }
                $task.status = 'committed'
                $task | Add-Member -NotePropertyName applied -NotePropertyValue $applied -Force
                Write-Ok ('已提交到宿主目录，应用 ' + $applied + ' 个文件改动')
            } else {
                $task.status = 'rolledback'
                Write-Ok '已回滚，宿主目录未改动'
            }

            $task | Add-Member -NotePropertyName ended -NotePropertyValue ((Get-Date).ToString('s')) -Force
            Write-AgentTask $task
            Set-AgentWork $task $cfg.Data
            Write-Output (ConvertTo-Json -Compress -InputObject $task)
        }

        'list' {
            $items = @()
            foreach ($d in Get-ChildItem (Get-AgentRoot) -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
                $f = Join-Path $d.FullName 'task.json'
                if (-not (Test-Path -LiteralPath $f)) { continue }
                try { $items += Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
            }
            Write-Output (ConvertTo-Json -Compress -Depth 6 -InputObject @($items))
        }

        'show' {
            $id = if ($Rest.Count -gt 1) { [string]$Rest[1] } else { '' }
            $task = Read-AgentTask $id
            $steps = @()
            $sf = Join-Path (Join-Path (Get-AgentRoot) $id) 'steps.jsonl'
            if (Test-Path -LiteralPath $sf) {
                foreach ($l in Get-Content -LiteralPath $sf -Encoding UTF8) {
                    if ($l.Trim()) { $steps += $l | ConvertFrom-Json }
                }
            }
            Write-Output (ConvertTo-Json -Compress -Depth 8 -InputObject ([pscustomobject]@{ task = $task; steps = @($steps) }))
        }

        default {
            Write-Bad ('未知 agent 动作: ' + $action)
            Write-Dim '可用: begin / exec / end / list / show'
        }
    }
}
