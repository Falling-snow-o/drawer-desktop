using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Windows;

namespace BoxRun;

public sealed class CatalogSource
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Url { get; set; } = "";
    public override string ToString() => Name;
}

public partial class CatalogSourcesDialog : Window
{
    public string Action { get; private set; } = "";
    public string Url { get; private set; } = "";

    public CatalogSourcesDialog(string sourcesJson)
    {
        InitializeComponent();
        var list = new List<CatalogSource>();
        try
        {
            using var doc = JsonDocument.Parse(sourcesJson);
            if (doc.RootElement.TryGetProperty("sources", out var arr))
            {
                foreach (var it in arr.EnumerateArray())
                {
                    list.Add(new CatalogSource
                    {
                        Id = it.TryGetProperty("id", out var i) ? i.GetString() : "",
                        Name = it.TryGetProperty("name", out var n) ? n.GetString() : "",
                        Url = it.TryGetProperty("url", out var u) ? u.GetString() : ""
                    });
                }
            }
        }
        catch { }

        SourceList.ItemsSource = list;
        if (list.Count > 0) SourceList.SelectedIndex = 0;
    }

    private void SourceList_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (SourceList.SelectedItem is CatalogSource s && !string.IsNullOrEmpty(s.Url))
            UrlBox.Text = s.Url;
    }

    private void UpdateBtn_Click(object sender, RoutedEventArgs e)
    {
        var url = UrlBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(url))
        {
            MessageBox.Show(this, "先选一个镜像或填一个地址", "更新目录");
            return;
        }
        Action = "update";
        Url = url;
        DialogResult = true;
    }

    private void ResetBtn_Click(object sender, RoutedEventArgs e)
    {
        Action = "reset";
        DialogResult = true;
    }

    private void CancelBtn_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
