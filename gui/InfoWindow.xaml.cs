using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BoxRun;

public partial class InfoWindow : Window
{
    private readonly string _box;
    private readonly Func<System.Threading.Tasks.Task<string>> _load;
    private string _dataPath;

    public InfoWindow(string box, Func<System.Threading.Tasks.Task<string>> load)
    {
        InitializeComponent();
        _box = box;
        _load = load;
        HeadText.Text = "抽屉信息";
        SubText.Text = box;
        Loaded += async (_, _) => await Reload();
    }

    private async System.Threading.Tasks.Task Reload()
    {
        HintText.Text = "读取中…";
        var raw = await _load();
        HintText.Text = "";
        SectionsPanel.Children.Clear();
        try
        {
            using var doc = JsonDocument.Parse(Extract(raw));
            var r = doc.RootElement;
            string S(string k) => r.TryGetProperty(k, out var v) && v.ValueKind != JsonValueKind.Null ? v.ToString() : "—";

            AddSection("系统", new (string, string)[]
            {
                ("发行版", S("os")),
                ("版本号", S("os_ver")),
                ("内核", S("kernel")),
                ("架构", S("arch")),
                ("CPU", S("cpu") + " 核"),
                ("内存", S("mem_total") + " MB"),
                ("已装软件包", S("pkgs") + " 个"),
            });
            AddSection("运行状态", new (string, string)[]
            {
                ("状态", S("running") == "True" ? "运行中" : "已停止"),
                ("已运行", Time(S("uptimeSec"))),
                ("内存占用", S("memNowGB") + " GB / " + S("memMaxGB") + " GB"),
                ("CPU 配额", S("cpuCores") + " 核"),
                ("GPU", S("gpu") == "True" ? "直通" : "无"),
                ("CUDA", S("cuda") == "True" ? "可用" : "不可用"),
            });
            AddSection("环境", new (string, string)[]
            {
                ("桌面组件", S("desktop") == "yes" ? "已安装" : "未安装"),
                ("合成器", S("compositor") == "yes" ? "已安装" : "未安装"),
                ("apt 镜像", S("mirror")),
                ("data 挂载", S("workMounted") == "True" ? "已挂载" : "未挂载"),
                ("预装", S("packages")),
            });
            _dataPath = S("data");
            AddSection("存储", new (string, string)[]
            {
                ("磁盘", S("diskGB") + " GB"),
                ("显存上限", S("vramMB") + " MB"),
                ("数据目录", S("data")),
                ("下载目录", S("downloads")),
                ("系统目录", S("state")),
            });
            AddSection("快照", new (string, string)[]
            {
                ("数量", S("snapshotCount")),
                ("占用", S("snapshotMB") + " MB"),
            });
        }
        catch (Exception ex)
        {
            HintText.Text = "解析失败：" + ex.Message;
        }
    }

    private static string Extract(string raw) => JsonUtil.Object(raw, raw);

    private static string Time(string sec)
    {
        if (!int.TryParse(sec, out var s) || s <= 0) return "—";
        var t = TimeSpan.FromSeconds(s);
        return t.TotalHours >= 1 ? $"{(int)t.TotalHours} 小时 {t.Minutes} 分" : $"{t.Minutes} 分 {t.Seconds} 秒";
    }

    private void AddSection(string title, (string Key, string Value)[] rows)
    {
        var card = new Border
        {
            Background = Brushes.White,
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(16, 14, 16, 14),
            Margin = new Thickness(0, 0, 0, 12)
        };
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock
        {
            Text = title,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Color.FromRgb(0x86, 0x86, 0x8B)),
            FontSize = 12,
            Margin = new Thickness(0, 0, 0, 8)
        });
        foreach (var (k, v) in rows)
        {
            var row = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var key = new TextBlock { Text = k, Foreground = new SolidColorBrush(Color.FromRgb(0x86, 0x86, 0x8B)) };
            var val = new TextBlock { Text = v, TextWrapping = TextWrapping.Wrap };
            Grid.SetColumn(val, 1);
            row.Children.Add(key);
            row.Children.Add(val);
            panel.Children.Add(row);
        }
        card.Child = panel;
        SectionsPanel.Children.Add(card);
    }

    private void OpenDataBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_dataPath) || !System.IO.Directory.Exists(_dataPath))
        {
            MessageBox.Show(this, "数据目录不存在（抽屉可能已删除）", "数据目录");
            return;
        }
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(_dataPath) { UseShellExecute = true }); } catch { }
    }

    private async void RefreshBtn_Click(object sender, RoutedEventArgs e) => await Reload();
    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
