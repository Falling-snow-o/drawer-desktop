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
            menu.Items.Add("退出", null, (_, _) => { _reallyExit = true; Close(); });
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

        Log("空闲 5 分钟，自动停止");
        await RunActionAsync("down", SelectedBox);
    }


    private void FullBtn_Click(object sender, RoutedEventArgs e) => ToggleFull();


    private void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        try { _client?.Dispose(); } catch { }
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

        var b = SelectedBox;
        bool running = _hasInfo && _info.TryGetProperty("running", out var r) && r.ValueKind == JsonValueKind.True;
        if (b == null || !running) return;

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = _ps,
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{_engine}\" down {b}",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = _root
            });
        }
        catch { }
    }
}
