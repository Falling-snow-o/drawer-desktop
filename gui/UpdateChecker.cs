using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;

namespace BoxRun;

/// <summary>无签名的轻量更新：读 latest.json → 下载 → sha256 校验 → 静默安装 → 重启。</summary>
public static class UpdateChecker
{
    private static bool TryLocal(string url, out string path)
    {
        path = null;
        if (string.IsNullOrWhiteSpace(url)) return false;
        try
        {
            if (url.StartsWith("file://", StringComparison.OrdinalIgnoreCase))
            {
                path = new Uri(url).LocalPath;
                return File.Exists(path);
            }
            if (url.IndexOf("://", StringComparison.Ordinal) < 0 && File.Exists(url))
            {
                path = url;
                return true;
            }
        }
        catch { }
        return false;
    }

    public static async Task CheckAsync(Window owner, string manifestUrl)
    {
        if (string.IsNullOrWhiteSpace(manifestUrl))
        {
            MessageBox.Show(owner, "还没有配置更新源。\n\n在「设置」里填 latest.json 的 URL 后再试。", "检查更新");
            return;
        }

        string body;
        try
        {
            if (TryLocal(manifestUrl, out var localManifest))
                body = await File.ReadAllTextAsync(localManifest);
            else
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                body = await http.GetStringAsync(manifestUrl);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(owner, "获取更新信息失败：\n" + ex.Message, "检查更新");
            return;
        }

        string version = "", url = "", sha = "", notes = "";
        try
        {
            using var doc = JsonDocument.Parse(body);
            var r = doc.RootElement;
            if (r.TryGetProperty("version", out var v)) version = v.GetString() ?? "";
            if (r.TryGetProperty("url", out var u)) url = u.GetString() ?? "";
            if (r.TryGetProperty("sha256", out var s)) sha = s.GetString() ?? "";
            if (r.TryGetProperty("notes", out var n)) notes = n.GetString() ?? "";
        }
        catch
        {
            MessageBox.Show(owner, "更新清单格式不对，应为 {\"version\":\"1.2.0\",\"url\":\"…\",\"sha256\":\"…\"}", "检查更新");
            return;
        }

        var current = typeof(UpdateChecker).Assembly.GetName().Version ?? new Version(1, 0, 0);
        if (!Version.TryParse(version, out var latest) || latest <= current)
        {
            MessageBox.Show(owner, "已是最新版本（当前 " + current.ToString(3) + "）", "检查更新");
            return;
        }

        if (string.IsNullOrWhiteSpace(url))
        {
            MessageBox.Show(owner, "清单里没有 url", "检查更新");
            return;
        }

        var msg = "发现新版本 " + latest.ToString(3) + "（当前 " + current.ToString(3) + "）";
        if (!string.IsNullOrWhiteSpace(notes)) msg += "\n\n" + notes;
        msg += "\n\n下载并安装？安装完会自动重启。";
        if (MessageBox.Show(owner, msg, "检查更新", MessageBoxButton.YesNo, MessageBoxImage.Question,
                MessageBoxResult.No) != MessageBoxResult.Yes) return;

        var tmp = Path.Combine(Path.GetTempPath(), "drawer-update-" + Guid.NewGuid().ToString("N") + ".exe");
        var win = new UpdateProgressWindow { Owner = owner };
        win.Show();

        try
        {
            if (TryLocal(url, out var localFile))
            {
                await using var src = File.OpenRead(localFile);
                await using var dst = File.Create(tmp);
                var total = src.Length;
                var buf = new byte[81920];
                long done = 0;
                int n;
                while ((n = await src.ReadAsync(buf)) > 0)
                {
                    await dst.WriteAsync(buf.AsMemory(0, n));
                    done += n;
                    win.SetProgress(total > 0 ? done * 100.0 / total : -1, done);
                }
            }
            else
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
                using var resp = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
                resp.EnsureSuccessStatusCode();
                var total = resp.Content.Headers.ContentLength ?? -1;
                await using var src = await resp.Content.ReadAsStreamAsync();
                await using var dst = File.Create(tmp);
                var buf = new byte[81920];
                long done = 0;
                int n;
                while ((n = await src.ReadAsync(buf)) > 0)
                {
                    await dst.WriteAsync(buf.AsMemory(0, n));
                    done += n;
                    win.SetProgress(total > 0 ? done * 100.0 / total : -1, done);
                }
            }

            if (!string.IsNullOrWhiteSpace(sha))
            {
                string got;
                using (var fs = File.OpenRead(tmp))
                    got = Convert.ToHexString(SHA256.HashData(fs)).ToLowerInvariant();
                if (!string.Equals(got, sha.Trim().ToLowerInvariant(), StringComparison.Ordinal))
                    throw new Exception("下载文件校验失败（sha256 不匹配）");
            }

            win.SetProgress(100, 0);
            win.Close();

            // 安装器负责停掉本进程、覆盖安装、再重启；这里直接退出即可
            Process.Start(new ProcessStartInfo(tmp, "--quiet --restart") { UseShellExecute = true });
            await Task.Delay(600);
            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            try { win.Close(); } catch { }
            try { File.Delete(tmp); } catch { }
            MessageBox.Show(owner, "更新失败：" + ex.Message, "检查更新");
        }
    }
}

public sealed class UpdateProgressWindow : Window
{
    private readonly System.Windows.Controls.TextBlock _text;

    public UpdateProgressWindow()
    {
        Title = "正在下载更新";
        Width = 360;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xF2, 0xF2, 0xF7));

        var panel = new System.Windows.Controls.StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new System.Windows.Controls.TextBlock
        {
            Text = "正在下载安装包…",
            FontSize = 14,
            FontWeight = FontWeights.SemiBold
        });
        _text = new System.Windows.Controls.TextBlock { Text = "0%", FontSize = 12, Margin = new Thickness(0, 8, 0, 0) };
        panel.Children.Add(_text);
        Content = panel;
    }

    public void SetProgress(double pct, long bytes)
    {
        _text.Text = pct < 0
            ? $"{bytes / 1024.0 / 1024.0:F1} MB"
            : $"{pct:F0}%  ·  {bytes / 1024.0 / 1024.0:F1} MB";
    }
}
