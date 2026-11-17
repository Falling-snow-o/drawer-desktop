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

    private static (string engine, string root) FindEngine()
    {
        // 1) 优先读同目录的 boxrun.ini（第一行非空、非 # 开头 = box.ps1 的完整路径）
        var ini = Path.Combine(AppContext.BaseDirectory, "boxrun.ini");
        if (File.Exists(ini))
        {
            var line = File.ReadAllLines(ini).FirstOrDefault(l => l.Trim().Length > 0 && !l.TrimStart().StartsWith("#"));
            if (line != null)
            {
                var path = line.Trim();
                if (File.Exists(path)) return (path, Path.GetDirectoryName(path));
            }
        }

        // 2) 从 exe 所在目录往上找
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        for (int i = 0; i < 10 && dir != null; i++)
        {
            var candidate = Path.Combine(dir.FullName, "box.ps1");
            if (File.Exists(candidate)) return (candidate, dir.FullName);
            dir = dir.Parent;
        }
        const string fallback = @"D:\Acta\boxrun\box.ps1";
        return (fallback, Path.GetDirectoryName(fallback));
    }


    private ProcessStartInfo EnginePsi(params string[] args) => _client.CreateStartInfo(args);

    private Task<string> CaptureAsync(params string[] args) => _client.CaptureAsync(args);

    private static string ExtractJson(string raw) => JsonUtil.Object(raw, "{}");

    private static string BusyMarker => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "state", "busy.json");

    /// <summary>安装器/更新器据此判断“现在不能杀进程”。</summary>
    private void MarkBusy(string verb)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(BusyMarker)!);
            File.WriteAllText(BusyMarker, JsonSerializer.Serialize(new
            {
                pid = Environment.ProcessId,
                verb,
                started = DateTime.Now.ToString("s")
            }));
        }
        catch { }
    }

    private void ClearBusyMark()
    {
        try { File.Delete(BusyMarker); } catch { }
    }

    public void RequestQuit()
    {
        if (_busy) { Log("[退出] 有操作在执行，等结束再退"); return; }
        // 先关掉所有附属窗口，避免主窗口关闭后残留模态循环
        foreach (var w in Application.Current.Windows.OfType<Window>().Where(w => w != this).ToList())
        {
            try { w.Close(); } catch { }
        }
        _reallyExit = true;
        Close();
    }


    private async Task RunActionAsync(params string[] args)
    {
        if (_busy) { Log("[忙] 上一个操作还没结束"); return; }

        _busy = true;
        _busyStart = DateTime.Now;
        MarkBusy(args.Length > 0 ? args[0] : "action");
        InteractionHub.SetBusy(true);
        _lastActive = DateTime.Now;
        ProgressText.Text = "执行中 0s";
        SetButtons();
        Bar.Visibility = Visibility.Visible;
        Bar.IsIndeterminate = true;
        Log("");
        Log("▸ box.ps1 " + string.Join(' ', args));

        try
        {
            using var p = new Process { StartInfo = EnginePsi(args), EnableRaisingEvents = true };
            var psi = p.StartInfo;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;

            p.OutputDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                Dispatcher.Invoke(() =>
                {
                    var m = System.Text.RegularExpressions.Regex.Match(e.Data, @"\[进度\]\s*(\d+)%");
                    if (m.Success)
                    {
                        Bar.IsIndeterminate = false;
                        Bar.Value = int.Parse(m.Groups[1].Value);
                        ProgressText.Text = "执行中 " + m.Groups[1].Value + "%";
                    }
                    var st = System.Text.RegularExpressions.Regex.Match(e.Data, @"\[阶段\]\s*(.+)");
                    if (st.Success) ProgressText.Text = st.Groups[1].Value.Trim();
                    Log(e.Data);
                });
            };
            p.ErrorDataReceived += (_, e) => { if (e.Data != null) Dispatcher.Invoke(() => Log(e.Data)); };

            p.Start();
            _runProc = p;
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            await p.WaitForExitAsync();
            if (p.ExitCode != 0) ShowError($"操作失败（退出码 {p.ExitCode}），详情见日志");
        }
        catch (Exception ex)
        {
            Log("[异常] " + ex.Message);
            ShowError(ex.Message);
        }
        finally
        {
            Log($"[结束] {string.Join(' ', args)} · {(DateTime.Now - _busyStart).TotalSeconds:0.0}s");
            _runProc = null;
            _busy = false;
            ClearBusyMark();
            InteractionHub.SetBusy(false);
            InteractionHub.NotifyAction(args.Length > 0 ? args[0] : "action");
            Bar.IsIndeterminate = false;
            Bar.Value = 0;
            Bar.Visibility = Visibility.Collapsed;
            ProgressText.Text = "完成";
            SetButtons();
            await _client.InvalidateAsync();
            await RefreshAsync();
        }
    }
}
