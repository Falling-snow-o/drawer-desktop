using System;
using System.IO;
using System.Text.Json;
using System.Windows;

namespace BoxRun;

public partial class SettingsWindow : Window
{
    private static string SettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "settings.json");

    private readonly string _cacheDir;

    public SettingsWindow(string enginePath)
    {
        InitializeComponent();
        PathText.Text = SettingsPath;
        _cacheDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "apt-cache");
        RefreshCacheText();

        string mirror = "tuna";
        bool useBase = true, aptCache = true, restic = false;
        string updateUrl = "";
        string crashUrl = "";

        try
        {
            if (File.Exists(SettingsPath))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(SettingsPath));
                var r = doc.RootElement;
                if (r.TryGetProperty("mirror", out var m)) mirror = m.GetString() ?? "tuna";
                if (r.TryGetProperty("useBase", out var b)) useBase = b.GetBoolean();
                if (r.TryGetProperty("aptCache", out var c)) aptCache = c.GetBoolean();
                if (r.TryGetProperty("restic", out var rs)) restic = rs.GetBoolean();
                if (r.TryGetProperty("updateUrl", out var uu)) updateUrl = uu.GetString() ?? "";
                if (r.TryGetProperty("crashUrl", out var cu)) crashUrl = cu.GetString() ?? "";
            }
        }
        catch { }

        foreach (var item in MirrorBox.Items)
            if (item is System.Windows.Controls.ComboBoxItem ci && (string)ci.Tag == mirror)
                MirrorBox.SelectedItem = item;
        if (MirrorBox.SelectedIndex < 0) MirrorBox.SelectedIndex = 0;

        BaseChk.IsChecked = useBase;
        CacheChk.IsChecked = aptCache;
        ResticChk.IsChecked = restic;
        UpdateUrlBox.Text = updateUrl;
        CrashUrlBox.Text = crashUrl;
    }

    private void RefreshCacheText()
    {
        try
        {
            long sum = 0; var n = 0;
            if (Directory.Exists(_cacheDir))
                foreach (var f in new DirectoryInfo(_cacheDir).GetFiles("*", SearchOption.AllDirectories))
                { sum += f.Length; n++; }
            CacheText.Text = n == 0 ? "空（0 个包）" : $"{n} 个包 · {sum / 1024.0 / 1024.0:F0} MB";
        }
        catch { CacheText.Text = "读取失败"; }
    }

    private void ClearCacheBtn_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "清空后，下次装包会重新下载。继续？", "清空 apt 缓存",
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        try
        {
            if (Directory.Exists(_cacheDir))
                foreach (var d in Directory.GetDirectories(_cacheDir)) Directory.Delete(d, true);
            if (Directory.Exists(_cacheDir))
                foreach (var f in Directory.GetFiles(_cacheDir)) File.Delete(f);
            RefreshCacheText();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "清空失败：" + ex.Message, "清空 apt 缓存");
        }
    }

    private void SaveBtn_Click(object sender, RoutedEventArgs e)
    {
        var mirror = (string)((System.Windows.Controls.ComboBoxItem)MirrorBox.SelectedItem).Tag;

        // 保留未知字段（向前兼容），只覆盖已知项
        System.Text.Json.Nodes.JsonObject root;
        try
        {
            root = File.Exists(SettingsPath)
                ? (System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(SettingsPath)) as System.Text.Json.Nodes.JsonObject
                   ?? new System.Text.Json.Nodes.JsonObject())
                : new System.Text.Json.Nodes.JsonObject();
        }
        catch { root = new System.Text.Json.Nodes.JsonObject(); }

        root["version"] = 1;
        root["mirror"] = mirror;
        root["useBase"] = BaseChk.IsChecked == true;
        root["aptCache"] = CacheChk.IsChecked == true;
        root["restic"] = ResticChk.IsChecked == true;
        root["updateUrl"] = UpdateUrlBox.Text.Trim();
        root["crashUrl"] = CrashUrlBox.Text.Trim();
        var json = root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
            File.WriteAllText(SettingsPath, json);
            DialogResult = true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "保存失败：" + ex.Message, "设置");
        }
    }

    private void CancelBtn_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
