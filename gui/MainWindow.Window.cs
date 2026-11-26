using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using System.Runtime.InteropServices;
using System.Globalization;

namespace BoxRun;
public partial class MainWindow
{

    private void InitTray()
    {
        try
        {
            _tray = new System.Windows.Forms.NotifyIcon
            {
                Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath),
                Text = "Drawer Desktop",
                Visible = true
            };
            var menu = new System.Windows.Forms.ContextMenuStrip();
            menu.Items.Add("显示窗口", null, (_, _) => RestoreFromTray());
            menu.Items.Add("退出（停止所有抽屉）", null, (_, _) => { _reallyExit = true; Close(); });
            _tray.ContextMenuStrip = menu;
            _tray.DoubleClick += (_, _) => RestoreFromTray();
        }
        catch { }
    }


    public void ShowFromTray() => RestoreFromTray();


    private void RestoreFromTray()
    {
        Show();
        ShowInTaskbar = true;
        WindowState = WindowState.Normal;
        Activate();
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);


    private void TryAcrylic()
    {
        try
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            int v = 3;
            if (DwmSetWindowAttribute(hwnd, 38, ref v, 4) == 0)
            {
                Background = Brushes.Transparent;
                if (Content is Panel root) root.Opacity = 0.92;
            }
        }
        catch { }
    }


    private async void IdleTick(object sender, EventArgs e)
    {
        if (_busy || SelectedBox == null || IdleChk.IsChecked != true) return;
        bool running = _hasInfo && _info.TryGetProperty("running", out var r) && r.ValueKind == JsonValueKind.True;
        if (!running) return;
        if ((DateTime.Now - _lastActive).TotalMinutes < 5) return;

        // 桌面 / 图形窗口开着时不要自动停，否则会变成灰黑屏
        try
        {
            var box = SelectedBox;
            var raw = await CaptureAsync("api", "gui-active", box);
            using var doc = JsonDocument.Parse(ExtractJson(raw));
            if (doc.RootElement.TryGetProperty("active", out var a) && a.ValueKind == JsonValueKind.True)
            {
                _lastActive = DateTime.Now;   // 重新计时，5 分钟后再看
                return;
            }
        }
        catch { }

        Log("空闲 5 分钟，自动停止");
        await RunActionAsync("down", SelectedBox);
    }


    private void FullBtn_Click(object sender, RoutedEventArgs e) => ToggleFull();


    private void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        // 隐藏到托盘时不能释放引擎客户端，否则再打开会重建 daemon
        if (!_reallyExit)
        {
            e.Cancel = true;
            Hide();
            ShowInTaskbar = false;
            return;
        }

        if (_tray != null) { _tray.Visible = false; _tray.Dispose(); _tray = null; }
        StopClipboardSync();

        if (_busy) { e.Cancel = true; MessageBox.Show(this, "还有操作在执行，等它结束再关。", "Drawer Desktop"); return; }

        try { _client?.Dispose(); } catch { }

        // 真正退出时：停掉所有正在运行的抽屉，并在没有其它发行版时关掉 WSL 虚拟机
        StopAllDrawersOnExit();
    }

    private static void StopAllDrawersOnExit()
    {
        try
        {
            var names = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var reg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".boxrun", "boxes.json");
            if (File.Exists(reg))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(reg));
                if (doc.RootElement.TryGetProperty("boxes", out var boxes))
                    foreach (var b in boxes.EnumerateArray())
                        if (b.TryGetProperty("name", out var n) && n.GetString() is { } s)
                            names.Add(s);
            }

            foreach (var name in WslRunning())
                if (names.Contains(name))
                    RunWsl(6000, "--terminate", name);

            // 只剩我们自己的抽屉时，直接关掉 WSL 虚拟机，释放 vmmemWSL
            var left = WslRunning();
            var onlyDrawers = left.All(n => names.Contains(n));
            if (onlyDrawers) RunWsl(8000, "--shutdown");
        }
        catch { }
    }

    private static void RunWsl(int timeoutMs, params string[] args)
    {
        try
        {
            var psi = new ProcessStartInfo("wsl.exe")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = System.Text.Encoding.Unicode,
                StandardErrorEncoding = System.Text.Encoding.Unicode
            };
            foreach (var a in args) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi);
            if (p == null) return;
            p.StandardOutput.ReadToEnd();
            p.StandardError.ReadToEnd();
            p.WaitForExit(timeoutMs);
        }
        catch { }
    }

    private static System.Collections.Generic.List<string> WslRunning()
    {
        var list = new System.Collections.Generic.List<string>();
        try
        {
            var psi = new ProcessStartInfo("wsl.exe")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                StandardOutputEncoding = System.Text.Encoding.Unicode
            };
            psi.ArgumentList.Add("-l");
            psi.ArgumentList.Add("--running");
            psi.ArgumentList.Add("-q");
            using var p = Process.Start(psi);
            if (p == null) return list;
            var text = p.StandardOutput.ReadToEnd();
            p.WaitForExit(5000);
            foreach (var part in text.Split('\n'))
            {
                var s = part.Replace("\0", "").Trim();
                if (s.Length > 0) list.Add(s);
            }
        }
        catch { }
        return list;
    }
}
