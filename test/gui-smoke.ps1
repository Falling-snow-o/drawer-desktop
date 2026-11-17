# GUI 冒烟 v2：重试点击 + 菜单入口 + 端口 + 启停
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Gw2 {
  public delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EP c, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void keybd_event(byte b, byte s, uint f, UIntPtr e);
  public static IntPtr Find(uint pid, string title){ IntPtr f=IntPtr.Zero; EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid){ var sb=new StringBuilder(256); GetWindowText(h,sb,256); if(sb.ToString()==title){ f=h; return false; } } return true; }, IntPtr.Zero); return f; }
  public static void Esc(){ keybd_event(0x1B,0,0,UIntPtr.Zero); System.Threading.Thread.Sleep(100); keybd_event(0x1B,0,2,UIntPtr.Zero); }
}
"@
$p = Get-Process Drawer | Select-Object -First 1
$root = [System.Windows.Automation.AutomationElement]::RootElement
$script:pass = 0; $script:fail = 0
function Check($c, $l) { if ($c) { $script:pass++; Write-Host ("  [PASS] " + $l) -ForegroundColor Green } else { $script:fail++; Write-Host ("  [FAIL] " + $l) -ForegroundColor Red } }
function Main2 { [System.Windows.Automation.AutomationElement]::FromHandle((Get-Process Drawer | Select-Object -First 1).MainWindowHandle) }
function Find2($el, $prop, $val) {
    try { return $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($prop, $val))) } catch { return $null }
}
function WaitMenu($name, $seconds = 6) {
    for ($i = 0; $i -lt ($seconds * 5); $i++) {
        $mi = Find2 $root ([System.Windows.Automation.AutomationElement]::NameProperty) $name
        if ($mi -ne $null) { return $mi }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Click2($el) {
    if ($el -eq $null) { return $false }
    for ($i=0; $i -lt 15; $i++) {
        try {
            if ($el.Current.IsEnabled) {
                $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                return $true
            }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    return $false
}
function Win($title) { return [Gw2]::Find([uint32]$p.Id, $title) }
function El2($h) { return [System.Windows.Automation.AutomationElement]::FromHandle($h) }
function WaitWin($title, $seconds = 8) {
    for ($i = 0; $i -lt ($seconds * 5); $i++) {
        $h = Win $title
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 200
    }
    return [IntPtr]::Zero
}

function WaitClosed($title, $seconds = 4) {
    for ($i = 0; $i -lt ($seconds * 5); $i++) {
        if ((Win $title) -eq [IntPtr]::Zero) { return $true }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function CloseTitle($t) { $h = Win $t; if ($h -ne [IntPtr]::Zero) { [void][Gw2]::PostMessage($h,0x0010,[IntPtr]::Zero,[IntPtr]::Zero) }; Start-Sleep -Milliseconds 500 }

Write-Host "== 主窗口 =="
$m = Main2
Check ($m -ne $null) '主窗口'

Write-Host "== 面板 → 标签 =="
Check (Click2 (Find2 $m ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'PanelBtn')) '面板按钮'
$tagItem = WaitMenu '标签…'
Check ($tagItem -ne $null) '面板含标签'
Check (Click2 $tagItem) '标签菜单可点'
$h = WaitWin '标签'
if ($h -eq [IntPtr]::Zero) {
    # 偶发：菜单点击后窗口没出现，重试一次
    Start-Sleep -Milliseconds 800
    Check (Click2 (Find2 (Main2) ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'PanelBtn')) '标签重试-面板'
    $mi2 = WaitMenu '标签…'
    if ($mi2 -ne $null) { Check (Click2 $mi2) '标签重试-菜单' }
    $h = WaitWin '标签' 10
}
Check ($h -ne [IntPtr]::Zero) '标签窗口'
if ($h -ne [IntPtr]::Zero) { Check (Click2 (Find2 (El2 $h) ([System.Windows.Automation.AutomationElement]::NameProperty) '取消')) '标签可取消'; [void](WaitClosed '标签') }
Check (@(Get-Process Drawer -EA SilentlyContinue).Count -gt 0) '进程存活'

Write-Host "== 工具箱 =="
Check (Click2 (Find2 (Main2) ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'ToolBtn')) '工具箱按钮'
$h = WaitWin '工具箱'
Check ($h -ne [IntPtr]::Zero) '工具箱窗口'
if ($h -ne [IntPtr]::Zero) {
  $w = El2 $h
  Check ((Find2 $w ([System.Windows.Automation.AutomationElement]::NameProperty) '安装') -ne $null) '分类页签存在'
  Check (Click2 (Find2 $w ([System.Windows.Automation.AutomationElement]::NameProperty) '取消')) '工具箱可取消'
}

Write-Host "== 快照 =="
Check (Click2 (Find2 (Main2) ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'SnapBtn')) '快照按钮'
$h = WaitWin '快照'
Check ($h -ne [IntPtr]::Zero) '快照窗口'
if ($h -ne [IntPtr]::Zero) { Check (Click2 (Find2 (El2 $h) ([System.Windows.Automation.AutomationElement]::NameProperty) '关闭')) '快照可关闭'; [void](WaitClosed '快照') }

Write-Host "== 端口（会启动抽屉，约 10s） =="
$m = Main2
Check (Click2 (Find2 $m ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'PanelBtn')) '面板按钮'
$portItem = WaitMenu '端口'
Check ($portItem -ne $null) '面板含端口'
Check (Click2 $portItem) '端口菜单可点'
$h = [IntPtr]::Zero
for ($i=0; $i -lt 30 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Seconds 1; $h = Win '端口' }
Check ($h -ne [IntPtr]::Zero) '端口窗口打开'
if ($h -ne [IntPtr]::Zero) {
  $w = El2 $h
  Start-Sleep -Seconds 2
  $texts = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)))
  $names = @($texts | ForEach-Object { $_.Current.Name } | Where-Object { $_.Trim() })
  Check (($names -join '|').Length -gt 0) ('端口窗口有内容: ' + (($names | Select-Object -First 4) -join ' / '))
  Check (Click2 (Find2 $w ([System.Windows.Automation.AutomationElement]::NameProperty) '关闭')) '端口可关闭'
}
Check (@(Get-Process Drawer -EA SilentlyContinue).Count -gt 0) '进程存活'

Write-Host "== 启动/停止切换 =="
$m = Main2
$start = Find2 $m ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'StartBtn'
$label = if ($start) { $start.Current.Name } else { '?' }
Write-Host ("  当前按钮: " + $label)
Check (Click2 $start) '启停按钮可点'
Start-Sleep -Seconds 12
Check (@(Get-Process Drawer -EA SilentlyContinue).Count -gt 0) '启停后进程存活'

Write-Host "== 自检 =="
Check (Click2 (Find2 (Main2) ([System.Windows.Automation.AutomationElement]::AutomationIdProperty) 'DoctorBtn')) '自检按钮'
Start-Sleep -Seconds 10
Check (@(Get-Process Drawer -EA SilentlyContinue).Count -gt 0) '自检后进程存活'

Write-Host ""
$crash = Join-Path $env:TEMP 'drawer-crash.log'
Check (-not (Test-Path $crash)) '无崩溃日志'
if (Test-Path $crash) { Get-Content $crash | Select-Object -First 4 | ForEach-Object { '    ' + $_ } }
Write-Host ("结果: {0} 通过, {1} 失败" -f $script:pass, $script:fail)
