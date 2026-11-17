#Requires -Version 5.1
<#
.SYNOPSIS
    Drawer Desktop —— 一个装 WSL 的抽屉。
.DESCRIPTION
    把 WSL 从"微软管理的发行版"变成"你管理的文件夹"。
    零安装、只占一个目录 + 一个注册表项、删掉即卸载。
    自研只有三件事：编排顺序、资源账本、便携语义。
    引擎（内核 / GPU / namespace / cgroup）全部来自 WSL 与 Linux。
.EXAMPLE
    .\box.ps1 init lab
    .\box.ps1 build lab
    .\box.ps1 up lab
    .\box.ps1 exec lab bash
    .\box.ps1 status lab
    .\box.ps1 down lab
    .\box.ps1 doctor
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Verb = 'help',
    [Parameter(Position = 1)] [string] $Box,
    [Parameter(Position = 2, ValueFromRemainingArguments = $true)] [string[]] $Rest
)
$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'SilentlyContinue'
$env:WSL_UTF8         = '1'
# ------------------------------------------------------------------ 常量
$ScriptRoot = $PSScriptRoot
$BoxesRoot  = if ($env:BOXRUN_HOME) { $env:BOXRUN_HOME } else { Join-Path (Split-Path $ScriptRoot -Parent) 'boxes' }
$BoxRunVersion = '1.0.0'
$KeepAwakePid = 'keepawake.pid'
# ------------------------------------------------------------------ 位置注册表
# 抽屉可以不放在 boxes\ 下：登记在 ~/.boxrun/boxes.json，按名字找路径
$RegistryDir  = Join-Path $env:USERPROFILE '.boxrun'
$RegistryFile = Join-Path $RegistryDir 'boxes.json'
$E = [char]27
if ($env:NO_COLOR) {
    $Fw = @{ Reset=''; Dim=''; Bold=''; Red=''; Green=''; Yellow=''; Cyan=''; Gray='' }
} else {
    $Fw = @{
        Reset  = "$E[0m";  Dim   = "$E[2m";  Bold  = "$E[1m"
        Red    = "$E[31m"; Green = "$E[32m"; Yellow= "$E[33m"
        Cyan   = "$E[36m"; Gray  = "$E[90m"
    }
}
# ------------------------------------------------------------------ 输出
# 统一输出格式：
#   boxrun 启动 lab        ← 标题 + 分隔线
#   ▸ 步骤
#     ✓ 成功
#     ! 警告
#     ✗ 失败
#       细节（缩进 4 格，灰色）
# ------------------------------------------------------------------ WSL 包装
# 注意：wsl -l -q 列的是「已注册」，不是「正在运行」。
# 判断运行必须用 --running；老版本 WSL 没有这个开关，退化到解析 -l -v 的 STATE 列。
# ------------------------------------------------------------------ 配置
# ------------------------------------------------------------------ guest 脚本
$GuestExec = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\exec.sh') -Raw -Encoding UTF8
$GuestWork = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\work.sh') -Raw -Encoding UTF8
$GuestGui = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\gui.sh') -Raw -Encoding UTF8
$GuestQuota = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\quota.sh') -Raw -Encoding UTF8
$GuestStatus = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\status.sh') -Raw -Encoding UTF8
$GuestAbout = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\about.sh') -Raw -Encoding UTF8
$GuestUsage = Get-Content -LiteralPath (Join-Path $ScriptRoot 'guest\usage.sh') -Raw -Encoding UTF8
# 重推全部 guest 脚本：build 时建立，up 时补齐（旧抽屉也能自愈到新版本）
# DataPath/Target 走 base64 写文件，不走命令行 —— Windows 路径的反斜杠在 argv 里活不下来
# ------------------------------------------------------------------ 显存闸
# gpu.vram = 0        → 不限制（纯账本）
# gpu.vram = N (MiB)  → LD_PRELOAD 拦 libcuda 的分配入口，累计超过 N 就返回 OOM
# 只对通过 box.ps1 exec 启动的进程生效，不是 MIG 那种硬件切分（见 PITFALLS 4.3）
# ------------------------------------------------------------------ 电源锚点
$KeepAwakeBody = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BoxRunAwake {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint f);
}
"@
[BoxRunAwake]::SetThreadExecutionState([uint32]'0x80000001') | Out-Null
try { while ($true) { Start-Sleep -Seconds 30 } }
finally { [BoxRunAwake]::SetThreadExecutionState([uint32]'0x80000000') | Out-Null }
'@
# ------------------------------------------------------------------ 生命周期
# 按本机规格给一套保守的默认配额：
#   CPU   = 逻辑核的 1/4（最多 8 核）
#   内存  = 总内存的 40%（最多 8G，且至少给系统留 4G）
#   进程  = 512
# 给抽屉放一个入口：双击打开管理器（图形界面是管理器里的一个按钮，不再单独开入口）
# 把任意目录登记成抽屉；可指定本地 rootfs 文件
# 扫描目录树，把已有的 box.yaml 目录登记进来
# 克隆抽屉：复制 vhdx + 改写名字 + 注册新发行版（秒级，不重装）
# 模板：只导出配置配方（几十 KB），别人拿去 init
# 开新东西前先看本机余量，避免把 Windows 拖进 swap/OOM
# 轻量实时用量：只读 cgroup，给界面做动态条用
# 统一的 apt 安装执行：脚本写文件再跑，避免 wsl 吃掉引号
# 删除抽屉：注销发行版 + 删目录（含 data/），不可恢复
# 抽屉清单（GUI 用）：名字 + 是否构建 + 是否运行
# ------------------------------------------------------------------ 状态
# ------------------------------------------------------------------ doctor
# ------------------------------------------------------------------ 菜单
# ------------------------------------------------------------------ 执行器
# ------------------------------------------------------------------ 桌面（xfce4）
# 文件管理器 ≠ 桌面。桌面环境（面板、窗口管理、右键菜单）是另一套东西，约 400 MB。
# 第一次点会装，之后直接起。
# ------------------------------------------------------------------ 图形（WSLg）
# 开图形/桌面之前确保抽屉已经按 up 的流程起来（配额、挂载、显存闸都在 up 里）
# 进程在抽屉里执行，窗口由 WSLg 画到 Windows 桌面 —— 箱内不需要装桌面环境。
# 前台跑（要看输出/等退出）用 exec；开窗口用 gui，它 nohup + 后台，不占终端。
# ------------------------------------------------------------------ 分发
# ---- 引擎模块 ----
. (Join-Path $ScriptRoot "lib\engine\output.ps1")
. (Join-Path $ScriptRoot "lib\engine\core.ps1")
. (Join-Path $ScriptRoot "lib\engine\wsl.ps1")
. (Join-Path $ScriptRoot "lib\engine\config.ps1")
. (Join-Path $ScriptRoot "lib\engine\guest.ps1")
. (Join-Path $ScriptRoot "lib\engine\base.ps1")
. (Join-Path $ScriptRoot "lib\engine\add.ps1")
. (Join-Path $ScriptRoot "lib\engine\build.ps1")
. (Join-Path $ScriptRoot "lib\engine\runtime.ps1")
. (Join-Path $ScriptRoot "lib\engine\desktop.ps1")
. (Join-Path $ScriptRoot "lib\engine\snapshots.ps1")
. (Join-Path $ScriptRoot "lib\engine\toolbox.ps1")
. (Join-Path $ScriptRoot "lib\engine\diagnostics.ps1")
. (Join-Path $ScriptRoot "lib\engine\templates.ps1")
. (Join-Path $ScriptRoot "lib\engine\collab.ps1")
. (Join-Path $ScriptRoot "lib\engine\api.ps1")

# 被 GUI 的常驻引擎 dot-source 时，只加载函数与变量，不执行分发
if ($env:DRAWER_DAEMON -eq '1') { return }

$v = $Verb.ToLower()
# 每个动作先打一个统一标题，后面只跟步骤和结果
$verbTitle = @{
    init = '创建抽屉'; build = '构建抽屉'; up = '启动'; down = '停止'
    restore = '恢复初始'; clean = '清理缓存'; snap = '快照'; exec = '进入'
    gui = '图形界面'; desktop = '桌面'; remove = '删除抽屉'; link = '重建入口'
}
if ($verbTitle.ContainsKey($v) -and $Box) {
    Write-Head ("{0} {1}" -f $verbTitle[$v], $Box)
} elseif ($verbTitle.ContainsKey($v)) {
    Write-Head $verbTitle[$v]
}

# 会改动盒子状态的动作：同一盒子同一时间只允许一个
$actionVerbs = @('build','up','down','remove','rm','rename','snap','snap-restore','snap-delete',
                 'restore','clean','install','uninstall')
$actionLock = $null
if ($Box -and ($actionVerbs -contains $v)) {
    $actionLock = Lock-BoxAction $Box 0
    if (-not $actionLock) {
        Write-Bad ("「" + $Box + "」正在执行另一个操作，稍后再试")
        Write-Dim '如果是上次异常退出，等几秒或检查是否有残留的 box.ps1 进程'
        exit 2
    }
}

try {
switch ($v) {
    'scan'    {
        $dep = 4
        if (($Rest -join ' ') -match '\-Depth\s+(\d+)') { $dep = [int]$Matches[1] }
        Invoke-Scan -Root $Box -Depth $dep
        break
    }
    'clone'   {
        $new = if ($Rest.Count -gt 0) { $Rest[0] } else { '' }
        $dir = ''
        for ($i=0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq '-Dir') { $dir = $Rest[$i + 1] } }
        Invoke-Clone -SrcName $Box -NewName $new -TargetDir $dir
        break
    }
    'template' {
        $a1 = ''; $a2 = ''
        if ($Rest.Count -gt 0) { $a1 = $Rest[0] }
        for ($i=0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq '-Out') { $a2 = $Rest[$i + 1] } }
        if (-not $a2 -and $Rest.Count -gt 1) { $a2 = $Rest[1] }
        Invoke-Template -Action $Box -Arg1 $a1 -Arg2 $a2
        break
    }
    'add'     {
        $image = ''; $bname = ''
        for ($i = 0; $i -lt $Rest.Count; $i++) {
            if ($Rest[$i] -eq '-Image') { $image = $Rest[$i + 1]; $i++ }
            elseif ($Rest[$i] -eq '-Name') { $bname = $Rest[$i + 1]; $i++ }
        }
        Invoke-Add -Path $Box -Name $bname -Image $image
        break
    }
    'init'    {
        $opt = @{}
        for ($i = 0; $i -lt $Rest.Count; $i++) {
            $k = [string]$Rest[$i]
            if ($k -eq '-cpu' -or $k -eq '-cores')        { $opt.Cpu    = $Rest[$i + 1]; $i++ }
            elseif ($k -eq '-memory' -or $k -eq '-mem')   { $opt.Memory = $Rest[$i + 1]; $i++ }
            elseif ($k -eq '-pids')                        { $opt.Pids   = $Rest[$i + 1]; $i++ }
        }
        Invoke-Init -Name $Box -Cpu $opt.Cpu -Memory $opt.Memory -Pids $opt.Pids
        break
    }
    'link'    {
        $d = Get-BoxDir $Box
        $c0 = Get-BoxConfig -Dir $d
        New-GuiShortcut -BoxDir $d -BoxName $c0.Name
        break
    }
    'build'   { Invoke-Build -Force:(($Rest -join ' ') -match '\-Force') -Fresh:(($Rest -join ' ') -match '\-Fresh'); break }
    'make-base' { Invoke-MakeBase -SrcBox $Box; break }
    'up'      { Invoke-Up; break }
    'down'    { Invoke-Down; break }
    'restore' { Invoke-Restore; break }
    'clean'   {
        $only = ''
        if (($Rest -join ' ') -match '\-Only\s+([^\s]+)') { $only = $Matches[1] }
        Invoke-Clean -Only $only
        break
    }
    'catalog' { Invoke-Catalog; break }
    'catalog-update' { $u = if ($Rest) { $Rest[0] } elseif ($Box) { $Box } else { '' }; Invoke-CatalogUpdate -Url $u; break }
    'catalog-sources' { Invoke-CatalogSources; break }
    'catalog-reset'   { Invoke-CatalogReset; break }
    'cache-clear' { Invoke-CacheClear; break }
    'ports'       { Invoke-Ports; break }
    'collab'      { Invoke-Collab; break }
    'rename'      { Invoke-Rename -NewName $Rest[0]; break }
    'export-app'  { Invoke-ExportApp -Name $Rest[0] -Command $Rest[1]; break }
    'about'       { Invoke-About; break }
    'apt'            { Invoke-Apt; break }
    'usage'   { Invoke-Usage; break }
    'api'     {
        $what = if ($Box) { $Box } else { 'help' }
        $arg  = if ($Rest -and $Rest.Count -gt 0) { $Rest[0] } else { '' }
        switch ($what) {
            'list'    { ConvertTo-Json -Compress -Depth 5 -InputObject ([pscustomobject]@{ boxes = @(Get-BoxList) }) }
            'info'    { (Get-BoxInfo -Dir (Get-BoxDir $arg)) | ConvertTo-Json -Compress -Depth 5 }
            'catalog' { ConvertTo-Json -Compress -Depth 6 -InputObject (Get-Catalog) }
            default   { Write-Bad '用法: box.ps1 api list | api info <box> | api catalog' }
        }
        break
    }
    'install' { Invoke-Install; break }
    'plugin'  { Invoke-Plugin; break }
    'snap'    { if ($Rest -and $Rest.Count -gt 0) { Invoke-Snap -Tag $Rest[0] } else { Invoke-Snap }; break }
    'snap-list'    { Invoke-SnapList; break }
    'snap-restore' { Invoke-SnapRestore -Tag ($Rest | Select-Object -First 1); break }
    'snap-delete'  { Invoke-SnapDelete -Tag ($Rest | Select-Object -First 1); break }
    'remove'  { Invoke-Remove -Name $Box -Yes:(($Rest -join ' ') -match '\-y'); break }
    'rm'      { Invoke-Remove -Name $Box -Yes:(($Rest -join ' ') -match '\-y'); break }
    'list'    { ConvertTo-Json -Compress -Depth 4 -InputObject ([pscustomobject]@{ boxes = @(Get-BoxList) }); break }
    'status'  { Invoke-Status; break }
    'ps'      { Invoke-Status; break }
    'info'    { Get-BoxInfo -Fast:(($Rest -join ' ') -match '\-fast') | ConvertTo-Json -Compress; break }
    'exec'    { Invoke-Exec; break }
    'gui'     { Invoke-Gui; break }
    'desktop' { Invoke-Desktop; break }
    'doctor'  { Invoke-Doctor; break }
    'version' { Write-Host ("Drawer Desktop v{0}" -f $BoxRunVersion); break }
    'help' { Get-Help $PSCommandPath -Detailed; break }
    default {
        Write-Bad ("未知命令: {0}" -f $Verb)
        Write-Host ""
        Write-Host @"
Drawer Desktop —— 一个装 WSL 的抽屉
  init <name>          创建抽屉（默认配额按本机规格算：1/4 核、40% 内存）
                      可加 -cpu 4 -memory 6G -pids 512 自行指定
  build <name>         下载 rootfs → wsl --import → 加固隔离
  up <name>            启动 + 同步 guest 脚本 + cgroup 配额 + 挂载 data + 起电源锚点
  exec <name> [cmd]    在抽屉里执行（默认 bash），进 cgroup、按需补挂 data
  gui <name> [cmd]     在 Windows 桌面开图形窗口（不带程序 = pcmanfm 文件管理器）
  desktop <name> [-y]  开完整桌面（xfce4，首次自动安装约 400 MB）
  status <name>        资源账本（可在运行中查看真实配额占用）
  ps <name>            status 的别名
  down <name>          sync → terminate → 撤锚点
  restore <name> [-y] [-KeepGui] [-CacheOnly]
                       恢复初始：默认全清（保留 data/downloads）
                       -KeepGui 重建后自动装回桌面；-CacheOnly 只清缓存不重建
  clean <name> [-Only id1,id2]   清理缓存（先看 catalog 选）
  add <目录> [-Name 名] [-Image 本地rootfs]   把任意目录登记成抽屉
  catalog             列出可清理 / 可安装 / 可装插件
  api list|info|catalog   对外 JSON 接口（GUI/脚本用）
  install <name> <id> 安装预设（dev/python/node/desktop/ssh/docker）
  plugin <name> <id>  装插件（py-ds/node-dev/desktop/sshd/jupyter）
  snap <name> <tag>    全量快照
  remove <name> [-y]   删除抽屉（注销发行版 + 删目录，含 data/）
  list                 列出抽屉（JSON，给界面用）
  doctor               自检
  link <name>          重建"图形界面"入口（.cmd + .lnk）
  menu                 交互菜单
  version              打印版本
第一次:
  .\box.ps1 init lab
  .\box.ps1 build lab
  .\box.ps1 up lab
  .\box.ps1 exec lab bash
"@
    }
}
} catch {
    Write-Host ""
    $msg = if ($_.Exception.Message) { $_.Exception.Message } else { '未知错误' }
    Write-Bad $msg
    if ($msg -match '找不到抽屉') { Write-Dim '用 box.ps1 list 查看现有抽屉' }
    if ($msg -match '还没构建')     { Write-Dim '先执行 box.ps1 build <name>' }
    if ($env:BOXRUN_DEBUG -and $_.InvocationInfo) {
        Write-Dim (($_.InvocationInfo.PositionMessage -replace "`r?`n", ' ').Trim())
    }
    Write-Host ""
    exit 1
} finally {
    Unlock-BoxAction $actionLock
}
