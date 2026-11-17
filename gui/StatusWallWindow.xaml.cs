using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace BoxRun;

public partial class StatusWallWindow : Window
{
    private readonly Func<Task<string>> _list;
    private readonly Func<string, Task<string>> _info;
    private readonly Action<string> _pick;

    private static readonly Brush Green = new SolidColorBrush(Color.FromRgb(0x34, 0xC7, 0x59));
    private static readonly Brush Yellow = new SolidColorBrush(Color.FromRgb(0xFF, 0x9F, 0x0A));
    private static readonly Brush Red = new SolidColorBrush(Color.FromRgb(0xFF, 0x3B, 0x30));
    private static readonly Brush Gray = new SolidColorBrush(Color.FromRgb(0xE5, 0xE5, 0xEA));

    public StatusWallWindow(Func<Task<string>> list, Func<string, Task<string>> info, Action<string> pick)
    {
        InitializeComponent();
        _list = list;
        _info = info;
        _pick = pick;
        Loaded += async (_, _) => await RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        HintText.Text = "读取中…";
        WallPanel.Children.Clear();

        var names = new List<string>();
        try
        {
            var raw = await _list();
            var json = JsonUtil.Array(raw);
            using var doc = JsonDocument.Parse(json);
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                string n = null;
                if (el.ValueKind == JsonValueKind.String) n = el.GetString();
                else if (el.TryGetProperty("name", out var p)) n = p.GetString();
                if (!string.IsNullOrEmpty(n)) names.Add(n);
            }
        }
        catch { }

        int ok = 0, run = 0, bad = 0;
        foreach (var n in names)
        {
            var (state, detail) = await ProbeAsync(n);
            Brush brush = state == 0 ? Green : state == 1 ? Yellow : Red;
            if (state == 0) ok++; else if (state == 1) run++; else bad++;
            var shown = BoxMeta.DisplayOf(n);
            WallPanel.Children.Add(MakeCell(shown, n, brush, detail));
        }

        HintText.Text = $"{names.Count} 个抽屉 · 正常 {ok} · 运行 {run} · 异常 {bad}";
    }

    /// <summary>0=正常(已停) 1=运行中 2=异常</summary>
    private async Task<(int, string)> ProbeAsync(string name)
    {
        try
        {
            var raw = await _info(name);
            var json = JsonUtil.Object(raw, "");
            if (json.Length == 0) return (2, "信息读取失败");
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            bool running = root.TryGetProperty("running", out var r) && r.ValueKind == JsonValueKind.True;
            bool built = !root.TryGetProperty("built", out var bt) || bt.ValueKind != JsonValueKind.False;
            if (!built) return (2, "未构建");
            return running ? (1, "运行中") : (0, "已停止");
        }
        catch (Exception ex)
        {
            return (2, ex.Message);
        }
    }

    private FrameworkElement MakeCell(string shown, string real, Brush brush, string detail)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 0, 14, 14), Width = 64, Cursor = Cursors.Hand };
        var cell = new Border
        {
            Width = 64,
            Height = 64,
            CornerRadius = new CornerRadius(8),
            Background = brush
        };
        var text = new TextBlock
        {
            Text = shown.Length > 6 ? shown.Substring(0, 6) : shown,
            FontSize = 11,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        cell.Child = text;
        stack.Children.Add(cell);
        var label = new TextBlock
        {
            Text = shown,
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.FromRgb(0x86, 0x86, 0x8B)),
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(0, 4, 0, 0),
            TextAlignment = TextAlignment.Center
        };
        stack.Children.Add(label);
        stack.ToolTip = $"{shown}\n{real}\n{detail}";

        cell.MouseLeftButtonUp += (_, _) => { _pick(real); Close(); };
        return stack;
    }

    private async void RefreshBtn_Click(object sender, RoutedEventArgs e) => await RefreshAsync();
    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
