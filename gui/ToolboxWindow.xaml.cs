using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace BoxRun;

public partial class ToolboxWindow : Window
{
    private sealed record Item(string Id, string Name, string Size, string Desc);

    private readonly Dictionary<string, List<Item>> _catalog = new();
    private readonly Dictionary<string, HashSet<string>> _sel = new()
    {
        ["clean"] = new(), ["install"] = new(), ["plugin"] = new()
    };
    private readonly string _sourcesJson;
    private string _tab = "clean";

    /// <summary>按顺序执行的命令：(动词, id 列表)</summary>
    public List<(string Kind, string Ids)> Plan { get; } = new();

    public ToolboxWindow(string catalogJson, string sourcesJson)
    {
        InitializeComponent();
        _sourcesJson = sourcesJson;
        LoadCatalog(catalogJson);
        Render();
    }

    private void LoadCatalog(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            foreach (var kind in new[] { "clean", "install", "plugin" })
            {
                var list = new List<Item>();
                if (doc.RootElement.TryGetProperty(kind, out var arr))
                {
                    foreach (var it in arr.EnumerateArray())
                    {
                        string S(string k) => it.TryGetProperty(k, out var v) ? v.GetString() : "";
                        list.Add(new Item(S("id"), S("name"), S("size"), S("desc")));
                    }
                }
                _catalog[kind] = list;
            }
        }
        catch { }
    }

    private void Render()
    {
        ListPanel.Children.Clear();
        if (!_catalog.TryGetValue(_tab, out var items)) return;

        var q = (SearchBox?.Text ?? "").Trim();
        int shown = 0;
        foreach (var it in items)
        {
            if (q.Length > 0 &&
                !(it.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                  it.Id.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                  it.Desc.Contains(q, StringComparison.OrdinalIgnoreCase)))
                continue;

            var cb = new CheckBox
            {
                Content = $"{it.Name}  ·  {it.Size}  —  {it.Desc}",
                Tag = it.Id,
                Margin = new Thickness(0, 5, 0, 5),
                FontSize = 12.5,
                IsChecked = _sel[_tab].Contains(it.Id)
            };
            var kind = _tab;
            cb.Checked += (s, _) => { if (s is CheckBox c && c.Tag is string id) _sel[kind].Add(id); };
            cb.Unchecked += (s, _) => { if (s is CheckBox c && c.Tag is string id) _sel[kind].Remove(id); };
            ListPanel.Children.Add(cb);
            shown++;
        }

        HintText.Text = q.Length > 0 ? $"匹配 {shown} / {items.Count} 项" : $"共 {items.Count} 项";
        SubText.Text = _tab switch
        {
            "clean" => "清理缓存，不影响已装软件和数据",
            "install" => "预置安装包，按需勾选",
            _ => "插件 = 安装包 + 额外配置"
        };
    }

    private void Tab_Checked(object sender, RoutedEventArgs e)
    {
        if (TabInstall == null) return;
        _tab = TabClean.IsChecked == true ? "clean" : TabInstall.IsChecked == true ? "install" : "plugin";
        Render();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => Render();

    private void CustomBtn_Click(object sender, RoutedEventArgs e)
    {
        var p = PkgBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(p))
        {
            MessageBox.Show(this, "先填要装的包名，例如 htop ripgrep", "自定义安装");
            return;
        }
        Plan.Add(("apt", p));
        DialogResult = true;
    }

    private void UpdateBtn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new CatalogSourcesDialog(_sourcesJson) { Owner = this };
        if (dlg.ShowDialog() != true) return;
        if (dlg.Action == "reset") Plan.Add(("catalog-reset", ""));
        else Plan.Add(("catalog-update", dlg.Url));
        DialogResult = true;
    }

    private void RunBtn_Click(object sender, RoutedEventArgs e)
    {
        int n = 0;
        foreach (var kv in _sel) n += kv.Value.Count;
        if (n == 0)
        {
            MessageBox.Show(this, "还没有勾选任何项目", "工具箱");
            return;
        }

        var lines = new List<string>();
        foreach (var kv in _sel)
            if (kv.Value.Count > 0) lines.Add($"{kv.Key}：{kv.Value.Count} 项");

        if (MessageBox.Show(this, "即将执行：\n" + string.Join("\n", lines) + "\n\n继续？", "确认",
                MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes)
            return;

        DialogResult = true;
    }

    private void CancelBtn_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
