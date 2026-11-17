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

    private async Task LoadBoxesAsync()
    {
        var json = await CaptureAsync("api", "list");
        var names = new List<string>();
        try
        {
            using var doc = JsonDocument.Parse(ExtractJson(json));
            if (doc.RootElement.TryGetProperty("boxes", out var boxes))
                foreach (var b in boxes.EnumerateArray())
                    if (b.TryGetProperty("name", out var n)) names.Add(n.GetString());
        }
        catch { }

        var keep = SelectedBox;
        CountText.Text = $"{names.Count} 个";
        PopulateList(names, keep);
    }


    private async Task RefreshAsync()
    {
        var box = SelectedBox;
        if (box == null) { ClearStatus(); return; }
        int gen = ++_refreshGen;
        try
        {
            var raw = await CaptureAsync("info", box, "-fast");

            // 期间切换了抽屉：丢弃这次结果，避免旧数据盖新界面
            if (gen != _refreshGen || SelectedBox != box) return;

            try
            {
                var doc = JsonDocument.Parse(ExtractJson(raw));
                _info = doc.RootElement.Clone();
                _hasInfo = true;
                _infoCache[box] = _info;
                ApplyInfo(_info);
            }
            catch
            {
                Log("[状态] 解析失败，原始输出：");
                Log(raw);
            }
        }
        catch { }
    }


    private void ApplyInfo(JsonElement o)
    {
        string S(string key) => o.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : "";
        bool B(string key) => o.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.True;
        double D(string key) => o.TryGetProperty(key, out var v) && v.TryGetDouble(out var d) ? d : 0;
        int I(string key) => o.TryGetProperty(key, out var v) && v.TryGetInt32(out var n) ? n : 0;

        bool built = B("built");
        bool running = B("running");

        StateVal.Text = !built ? "△  未构建" : running ? "●  运行中" : "○  已停止";
        StateVal.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
            !built ? "#B25000" : running ? "#1B8A3A" : "#86868B"));

        PathVal.Text = S("dir");
        KernelVal.Text = string.IsNullOrEmpty(S("kernel")) ? "启动后显示" : S("kernel");
        UptimeVal.Text = running && I("uptimeSec") > 0
            ? $"{I("uptimeSec") / 86400} 天 {(I("uptimeSec") % 86400) / 3600} 小时" : "—";
        DiskVal.Text = $"{D("diskGB"):0.##} GB";
        VramVal.Text = I("vramMB") > 0 ? $"{I("vramMB")} MiB" : "不限制";
        GpuVal.Text = running ? (B("gpu") && B("cuda") ? "✓ /dev/dxg · libcuda" : B("gpu") ? "✓ /dev/dxg" : "✗ 无") : "—";
        MountVal.Text = running ? (B("workMounted") ? "✓ /work" : "✗ 未挂载") : "—";
        LocVal.Text = S("storeAt");
        BuiltVal.Text = built ? "已注册" : "未注册";
        _running = running;


        double memMax = D("memMaxGB");
        double memNow = D("memNowGB");
        int pidsMax = I("pidsMax");
        int pidsNow = I("pidsNow");
        int cores = I("cpuCores");
        int host = Environment.ProcessorCount;

        CpuVal.Text = cores > 0 ? $"{cores} / {host} 核" : (string.IsNullOrEmpty(S("cpuMax")) ? "—" : $"上限 {Math.Round(ParseCores(S("cpuMax")), 2)} 核");
        MemVal.Text = memMax > 0 ? $"{memNow:0.0} / {memMax:0.#} GB" : "—";
        PidsVal.Text = pidsMax > 0 ? $"{pidsNow} / {pidsMax}" : "—";

        SetBar(CpuBar, CpuTrack, host > 0 ? 100.0 * cores / host : 0);
        SetBar(MemBar, MemTrack, memMax > 0 ? 100.0 * memNow / memMax : 0);
        SetBar(PidBar, PidTrack, pidsMax > 0 ? 100.0 * pidsNow / pidsMax : 0);

        MemSpark?.Push(memMax > 0 ? memNow / memMax : 0);
        if (SparkRow != null) SparkRow.Visibility = (running && memMax > 0) ? Visibility.Visible : Visibility.Collapsed;
        if (MemSpark != null) MemSpark.Visibility = (running && memMax > 0) ? Visibility.Visible : Visibility.Collapsed;
        if (SparkHint != null) SparkHint.Text = memMax > 0 ? $"{memNow:0.0} GB" : "";

        SetButtons();
    }


    private static double ParseCores(string cpuMax)
    {
        var parts = cpuMax.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length >= 2 && double.TryParse(parts[0], out var q) && double.TryParse(parts[1], out var p) && p > 0)
            return q / p;
        return 0;
    }


    private static void SetBar(Border bar, Border track, double pct)
    {
        double w = track.ActualWidth > 4 ? track.ActualWidth : 240;
        double target = Math.Max(0, Math.Min(w, w * pct / 100.0));
        if (Math.Abs(bar.ActualWidth - target) < 1.0) return;
        var anim = new DoubleAnimation(bar.ActualWidth, target, TimeSpan.FromMilliseconds(350))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        bar.BeginAnimation(FrameworkElement.WidthProperty, anim);
    }


    private void ClearStatus()
    {
        _running = false;
        MemSpark?.Clear();
        if (SparkHint != null) SparkHint.Text = "";

        foreach (var tb in new[] { StateVal, KernelVal, UptimeVal, DiskVal, VramVal, GpuVal, MountVal, LocVal, BuiltVal, CpuVal, MemVal, PidsVal })
            tb.Text = "—";
        PathVal.Text = "—";
        SetButtons();
    }


    private void SetButtons()
    {
        bool built = _hasInfo && _info.TryGetProperty("built", out var b) && b.ValueKind == JsonValueKind.True;
        bool running = _hasInfo && _info.TryGetProperty("running", out var r) && r.ValueKind == JsonValueKind.True;
        bool on = !_busy && SelectedBox != null;

        StartBtn.IsEnabled = on;
        StartBtn.Content = running ? "■  停止" : (built ? "▶  启动" : "构建并启动");
        StartBtn.Style = running ? (Style)FindResource(typeof(Button)) : (Style)FindResource("Accent");
        TermBtn.IsEnabled = on && built;
        DesktopMenuBtn.IsEnabled = on && built;
        RestoreBtn.IsEnabled = on && built;

        SnapBtn.IsEnabled = on && built;
        DoctorBtn.IsEnabled = !_busy;
        RefreshBtn.IsEnabled = !_busy;
        DeleteBtn.IsEnabled = !_busy && SelectedBox != null;
        ScanBtn.IsEnabled = !_busy;
        AddBtn.IsEnabled = !_busy;
        ToolBtn.IsEnabled = !_busy && SelectedBox != null;
        CloneBtn.IsEnabled = !_busy && SelectedBox != null;
        ExportMenuBtn.IsEnabled = !_busy && SelectedBox != null;
        NewFromTplBtn.IsEnabled = !_busy;
    }


    private void HookCardHover()
    {
        if (StateVal.Parent is not FrameworkElement card) return;
        var scale = new ScaleTransform(1, 1);
        card.RenderTransform = scale;
        card.RenderTransformOrigin = new Point(0.5, 0.5);

        card.MouseEnter += (_, _) =>
        {
            var a = new DoubleAnimation(1, 1.008, TimeSpan.FromMilliseconds(140))
            { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, a);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        };
        card.MouseLeave += (_, _) =>
        {
            var a = new DoubleAnimation(1.008, 1, TimeSpan.FromMilliseconds(160))
            { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, a);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        };
    }
}
