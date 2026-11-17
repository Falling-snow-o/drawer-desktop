using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;

namespace BoxRun;

public sealed class SnapItem
{
    public string Tag { get; set; } = "";
    public string File { get; set; } = "";
    public long SizeMB { get; set; }
    public string Created { get; set; } = "";
    public string Path { get; set; } = "";

    public string SizeText => SizeMB >= 1024 ? (SizeMB / 1024.0).ToString("F1") + " GB" : SizeMB + " MB";
    public string ShaText => (Path.Length > 0 && System.IO.File.Exists(Path + ".sha256")) ? "校验 ✓"
        : (File == "restic" ? "restic" : "无校验");
    public bool IsRestic => File == "restic";
}

public partial class SnapDialog : Window
{
    private readonly List<SnapItem> _items;
    private readonly string _box;
    private readonly Func<string, System.Threading.Tasks.Task<bool>> _deleteRestic;

    public string Action { get; private set; } = "";
    public string Tag { get; private set; } = "";

    public SnapDialog(string box, List<SnapItem> items,
        Func<string, System.Threading.Tasks.Task<bool>> deleteRestic = null)
    {
        InitializeComponent();
        _deleteRestic = deleteRestic;
        _box = box;
        _items = items;
        HeadText.Text = box;
        TagBox.Text = DateTime.Now.ToString("yyyyMMdd-HHmm");
        RefreshList();
    }

    private void RefreshList()
    {
        SnapList.ItemsSource = null;
        SnapList.ItemsSource = _items;
        var empty = _items.Count == 0;
        EmptyText.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        SnapList.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        HeadText.Text = _box + "  ·  " + _items.Count + " 个快照";
    }

    private SnapItem Selected => SnapList.SelectedItem as SnapItem;

    private void CreateBtn_Click(object sender, RoutedEventArgs e)
    {
        var tag = TagBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(tag)) return;
        Action = "create";
        Tag = tag;
        DialogResult = true;
    }

    private void RestoreBtn_Click(object sender, RoutedEventArgs e)
    {
        var it = Selected;
        if (it == null) { MessageBox.Show(this, "先选一个快照", "快照", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var r = MessageBox.Show(this,
            "还原到快照「" + it.Tag + "」？\n\n" +
            "大小：" + it.SizeText + "\n创建：" + it.Created + "\n完整性：" + it.ShaText + "\n\n" +
            "当前系统会被替换，data/ 和 downloads/ 不动。",
            "还原快照", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
        if (r != MessageBoxResult.Yes) return;
        Action = "restore";
        Tag = it.Tag;
        DialogResult = true;
    }

    private async void DeleteBtn_Click(object sender, RoutedEventArgs e)
    {
        var it = Selected;
        if (it == null) return;
        var r = MessageBox.Show(this, "删除快照「" + it.Tag + "」？\n\n" + it.SizeText + " · " + it.Created,
            "删除快照", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
        if (r != MessageBoxResult.Yes) return;

        try
        {
            if (it.IsRestic)
            {
                if (_deleteRestic == null)
                {
                    MessageBox.Show(this, "restic 快照需要从主窗口删除（缺少引擎回调）", "删除快照");
                    return;
                }
                if (!await _deleteRestic(it.Tag))
                {
                    MessageBox.Show(this, "restic 删除失败，详情见主窗口日志", "删除快照");
                    return;
                }
            }
            else
            {
                System.IO.File.Delete(it.Path);
                System.IO.File.Delete(it.Path + ".sha256");
            }
            _items.Remove(it);
            RefreshList();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "删除失败：" + ex.Message, "快照", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e) { DialogResult = false; }
}
