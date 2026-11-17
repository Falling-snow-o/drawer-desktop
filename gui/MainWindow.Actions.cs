using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
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

    private async void RefreshBtn_Click(object sender, RoutedEventArgs e)
    {
        await LoadBoxesAsync();
        await RefreshAsync();
    }


    private async void StartBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        if (_running) { await RunActionAsync("down", b); return; }

        bool built = _hasInfo && _info.TryGetProperty("built", out var bt) && bt.ValueKind == JsonValueKind.True;
        if (!built) await RunActionAsync("build", b);
        await RunActionAsync("up", b);
    }


    private void TermBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;

        // 优先 Windows Terminal：每个抽屉一个带标题的标签
        try
        {
            var q2 = ((char)34).ToString();
            var q = "";
            var psi = new ProcessStartInfo("wt.exe")
            {
                UseShellExecute = true,
                Arguments = "new-tab --title " + q2 + "Drawer: " + b + q2 + " " + _ps + " -NoExit -NoProfile -ExecutionPolicy Bypass -Command " + q2 + "& '" + _engine + "' exec " + b + " bash" + q2
            };
            Process.Start(psi);
            return;
        }
        catch { }

        try
        {
            var psi = new ProcessStartInfo(_ps,
                $"-NoExit -NoProfile -ExecutionPolicy Bypass -Command \"& '{_engine}' exec {b} bash\"")
            { UseShellExecute = true };
            Process.Start(psi);
        }
        catch (Exception ex) { Log("[终端] " + ex.Message); }
    }


    private async void FilesBtn_Click(object sender, RoutedEventArgs e) => await RunActionAsync("gui", SelectedBox, "-y");


    private async void DeskBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        var dir = _hasInfo && _info.TryGetProperty("dir", out var d) && d.ValueKind == JsonValueKind.String ? d.GetString() : null;
        await RunActionAsync("desktop", b, "-y");
        if (dir != null) _fixedDir = dir;   // 桌面开着时，剪贴板跟着这个抽屉
    }


    private async void DoctorBtn_Click(object sender, RoutedEventArgs e) => await RunActionAsync("doctor");


    private async void SnapBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;

        var raw = await CaptureAsync("snap-list", b);
        Log("[快照] " + raw.Trim());
        var json = JsonUtil.Array(raw);
        var items = new List<SnapItem>();
        try
        {
            var arr = System.Text.Json.JsonSerializer.Deserialize<List<SnapItem>>(json,
                new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (arr != null) items = arr;
        }
        catch { }

        Log("[快照] parsed=" + items.Count);
        var dlg = new SnapDialog(b, items, async tag =>
        {
            var del = await CaptureAsync("snap-delete", b, tag);
            Log("[快照] " + del.Trim());
            return del.Contains("已删除");
        }) { Owner = this };
        if (dlg.ShowDialog() != true) return;

        if (dlg.Action == "create")
            await RunActionAsync("snap", b, dlg.Tag);
        else if (dlg.Action == "restore")
        {
            await RunActionAsync("snap-restore", b, dlg.Tag);
            await RefreshAsync();
        }
    }


    private async void RestoreBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;

        var dlg = new RestoreDialog(b) { Owner = this };
        var ok = dlg.ShowDialog() == true;
        if (!ok || dlg.Result == RestoreDialog.Choice.Cancel)
        {
            Log("已取消恢复");
            return;
        }

        if (dlg.Result == RestoreDialog.Choice.Full)
            await RunActionAsync("restore", b, "-y");
        else
            await RunActionAsync("restore", b, "-y", "-KeepGui");
    }


    private async void DeleteBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        var r = MessageBox.Show(this,
            $"删除抽屉 {b}\n\n会注销 WSL 发行版、删除整个目录（包括 data/downloads），不可恢复。",
            "删除抽屉", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No);
        if (r != MessageBoxResult.Yes) return;
        await RunActionAsync("remove", b, "-y");
        await LoadBoxesAsync();
    }


    private async void AddBtn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "选择抽屉目录（可以是任意位置，不存在会自动创建）"
        };
        if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

        var dir = dlg.SelectedPath;
        var name = Path.GetFileName(dir.TrimEnd('\\', '/'));
        if (string.IsNullOrWhiteSpace(name)) name = "box";

        await RunActionAsync("add", dir, "-Name", name);
        await LoadBoxesAsync();
        BoxList.SelectedItem = name;
    }


    private async void CloneBtn_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedBox == null) return;
        var name = Microsoft.VisualBasic.Interaction.InputBox(
            "新抽屉名字（会复制当前抽屉的磁盘，秒级完成）", "克隆 " + SelectedBox, SelectedBox + "-copy");
        if (string.IsNullOrWhiteSpace(name)) return;
        await RunActionAsync("clone", SelectedBox, name.Trim());
        await LoadBoxesAsync();
    }


    private async void NewFromTplBtn_Click(object sender, RoutedEventArgs e)
    {
        var ofd = new System.Windows.Forms.OpenFileDialog
        {
            Filter = "Drawer 模板|*.tar.gz;*.tgz|所有文件|*.*",
            Title = "选择模板文件"
        };
        if (ofd.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

        var name = Microsoft.VisualBasic.Interaction.InputBox(
            "新抽屉名字", "从模板新建", Path.GetFileNameWithoutExtension(ofd.FileName).Replace(".tar", ""));
        if (string.IsNullOrWhiteSpace(name)) return;

        var newName = name.Trim();
        await RunActionAsync("template", "apply", ofd.FileName, newName);
        await LoadBoxesAsync();

        // 紧接着构建，省得还要手动点一步
        if (BoxList.Items.Contains(newName))
        {
            await RunActionAsync("build", newName);
        }
        await LoadBoxesAsync();
        BoxList.SelectedItem = newName;
    }


    private async void TplBtn_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedBox == null) return;
        await RunActionAsync("template", "export", SelectedBox);
    }


    private async void ToolBtn_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedBox == null) { Log("先选一个抽屉"); return; }
        var cat = await CaptureAsync("api", "catalog");
        var src = await CaptureAsync("catalog-sources");
        var dlg = new ToolboxWindow(ExtractJson(cat), src) { Owner = this };
        dlg.ShowDialog();
        if (dlg.Plan.Count == 0) return;

        foreach (var (kind, ids) in dlg.Plan)
        {
            if (kind == "clean") await RunActionAsync("clean", SelectedBox, "-Only", ids);
            else if (kind == "catalog-update") await RunActionAsync("catalog-update", ids);
            else if (kind == "catalog-reset") await RunActionAsync("catalog-reset");
            else await RunActionAsync(kind, SelectedBox, ids);
        }
    }


    private async void ScanBtn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = "选择要扫描的目录（查找 box.yaml）" };
        if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
        await RunActionAsync("scan", dlg.SelectedPath);
        await LoadBoxesAsync();
    }


    private void InfoBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        new InfoWindow(b, () => CaptureAsync("about", b)) { Owner = this }.ShowDialog();
    }


    private void CancelBtn_Click(object sender, RoutedEventArgs e)
    {
        var p = _runProc;
        if (p == null) return;
        try { p.Kill(true); Log("[取消] 已终止当前任务"); } catch { }
    }


    private async void ExportBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        var dlg = DialogShell.Form("导出应用", "把「" + b + "」里的应用导出到开始菜单", "导出",
            ("名称", b), ("启动命令（在抽屉里执行）", "xfce4-terminal"));
        dlg.Owner = this;
        if (dlg.ShowDialog() != true) return;
        var appName = dlg[0];
        var raw = await CaptureAsync("export-app", b, appName, dlg[1]);
        Log(raw.Trim());
        MessageBox.Show(this, "已导出到开始菜单：\nDrawer\\" + appName, "导出应用");
    }


    private async void TagBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) { ShowError("有操作在执行，等它结束再试"); return; }

        var b = SelectedBox;
        if (b == null) { Log("[标签] 没有选中的抽屉"); return; }
        var dlg = DialogShell.Prompt("标签", "给「" + b + "」设置分组标签（留空清除）：", BoxMeta.TagOf(b));
        dlg.Owner = this;
        if (dlg.ShowDialog() != true) return;
        if (!BoxMeta.SetTag(b, dlg[0])) Log("[标签] 保存失败，检查 ~/.boxrun 是否可写");
        var keep = b;
        await LoadBoxesAsync();
        if (keep != null) BoxList.SelectedItem = BoxList.Items.OfType<BoxItem>().FirstOrDefault(x => x.Name == keep);
    }


    private void OpenMenu_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.ContextMenu != null)
        {
            b.ContextMenu.PlacementTarget = b;
            b.ContextMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom;
            b.ContextMenu.IsOpen = true;
        }
    }


    private void CollabMenu_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) { ShowError("有操作在执行，等它结束再试"); return; }

        var b = SelectedBox;
        if (b == null) { ShowError("先选一个抽屉"); return; }
        new CollabWindow(b, args => CaptureAsync(args)) { Owner = this }.ShowDialog();
    }

    private async void DiagMenu_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) { ShowError("有操作在执行，等它结束再试"); return; }

        try
        {
            var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            var tmp = Path.Combine(Path.GetTempPath(), "drawer-diag-" + stamp);
            Directory.CreateDirectory(tmp);

            if (Directory.Exists(LogDir))
                foreach (var f in Directory.GetFiles(LogDir))
                    File.Copy(f, Path.Combine(tmp, "log-" + Path.GetFileName(f)), true);

            var meta = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun");
            foreach (var name in new[] { "settings.json", "boxes.json", "aliases.json", "tags.json" })
            {
                var src = Path.Combine(meta, name);
                if (File.Exists(src)) File.Copy(src, Path.Combine(tmp, name), true);
            }

            var regFile = Path.Combine(meta, "boxes.json");
            if (File.Exists(regFile))
            {
                try
                {
                    using var doc = JsonDocument.Parse(File.ReadAllText(regFile));
                    if (doc.RootElement.TryGetProperty("boxes", out var boxes))
                        foreach (var b in boxes.EnumerateArray())
                        {
                            if (!b.TryGetProperty("dir", out var d) || !b.TryGetProperty("name", out var n)) continue;
                            var y = Path.Combine(d.GetString() ?? "", "box.yaml");
                            if (File.Exists(y))
                                File.Copy(y, Path.Combine(tmp, (n.GetString() ?? "box") + ".box.yaml"), true);
                        }
                }
                catch { }
            }

            var sb = new StringBuilder();
            sb.AppendLine("Drawer Desktop diagnostics");
            sb.AppendLine("time: " + DateTime.Now.ToString("s"));
            sb.AppendLine("app: " + (System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "?"));
            sb.AppendLine("os: " + Environment.OSVersion);
            sb.AppendLine("dotnet: " + Environment.Version);
            try
            {
                var psi = new ProcessStartInfo("wsl.exe", "--version")
                {
                    RedirectStandardOutput = true, RedirectStandardError = true,
                    UseShellExecute = false, CreateNoWindow = true
                };
                using var wp = Process.Start(psi);
                sb.AppendLine("wsl: " + ((wp?.StandardOutput.ReadToEnd() ?? "") + (wp?.StandardError.ReadToEnd() ?? "")).Trim());
            }
            catch { }
            File.WriteAllText(Path.Combine(tmp, "system.txt"), sb.ToString());

            var doctor = await CaptureAsync("doctor");
            File.WriteAllText(Path.Combine(tmp, "doctor.txt"), doctor);

            var zip = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                "drawer-diagnostics-" + stamp + ".zip");
            ZipFile.CreateFromDirectory(tmp, zip);
            Directory.Delete(tmp, true);

            MessageBox.Show(this, "诊断包已导出：\n" + zip, "导出诊断包");
            try { Process.Start("explorer.exe", "/select," + zip); } catch { }
        }
        catch (Exception ex)
        {
            ShowError("导出诊断包失败：" + ex.Message);
        }
    }

    private async void UpdateMenu_Click(object sender, RoutedEventArgs e)
    {
        string url = "";
        try
        {
            var f = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "settings.json");
            if (File.Exists(f))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(f));
                if (doc.RootElement.TryGetProperty("updateUrl", out var u)) url = u.GetString() ?? "";
            }
        }
        catch { }
        await UpdateChecker.CheckAsync(this, url);
    }


    private void PanelBtn_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.ContextMenu != null)
        {
            b.ContextMenu.PlacementTarget = b;
            b.ContextMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom;
            b.ContextMenu.IsOpen = true;
        }
    }


    private void WallBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) { ShowError("有操作在执行，等它结束再试"); return; }

        new StatusWallWindow(
            () => CaptureAsync("api", "list"),
            n => CaptureAsync("info", n, "-fast"),
            n =>
            {
                try
                {
                    BoxList.SelectedItem = n;
                    BoxList.ScrollIntoView(n);
                }
                catch { }
            }) { Owner = this }.ShowDialog();
    }


    private async void PortBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) { ShowError("有操作在执行，等它结束再试"); return; }

        var b = SelectedBox;
        if (b == null) return;
        var win = new PortsWindow(b, () => CaptureAsync("ports", b)) { Owner = this };
        win.Closed += async (_, _) => { await _client.InvalidateAsync(); await RefreshAsync(); };
        win.Show();
    }


    private void SetBtn_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SettingsWindow(_engine) { Owner = this };
        if (dlg.ShowDialog() == true) Log("设置已保存（下次构建/装包生效）");
    }


    private async void BuildBtn_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        await RunActionAsync("build", b);
        await RefreshAsync();
    }


    private void ClearLogBtn_Click(object sender, RoutedEventArgs e)
    {
        LogBox.Document.Blocks.Clear();
        ProgressText.Text = "";
        try { File.WriteAllText(TodayLog, ""); } catch { }
    }


    private async void BatchStart_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        foreach (var n in SelectedNames()) await RunActionAsync("up", n);
    }


    private async void BatchStop_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        foreach (var n in SelectedNames()) await RunActionAsync("down", n);
    }


    private async void BatchDelete_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        var names = SelectedNames();
        if (names.Count == 0) { ShowError("没有选中抽屉"); return; }
        if (MessageBox.Show(this, "删除选中的 " + names.Count + " 个抽屉？\n\n" + string.Join("\n", names) +
                "\n\n系统会被卸载，data/ 和 downloads/ 保留。", "批量删除",
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        foreach (var n in names) await RunActionAsync("remove", n, "-y");
        await LoadBoxesAsync();
    }


    private async void AliasMenu_Click(object sender, RoutedEventArgs e)
    {
        var b = SelectedBox;
        if (b == null) return;
        var cur = BoxMeta.AliasOf(b);
        var dlg = DialogShell.Prompt("显示别名", "面板里显示的名称（留空则用原名「" + b + "」）：", cur);
        dlg.Owner = this;
        if (dlg.ShowDialog() != true) return;

        var v = dlg[0];
        if (!BoxMeta.SetAlias(b, v)) Log("[别名] 保存失败，检查 ~/.boxrun 是否可写");

        await LoadBoxesAsync();
        if (b != null) BoxList.SelectedItem = BoxList.Items.OfType<BoxItem>().FirstOrDefault(x => x.Name == b);
    }


    private void BoxList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var box = SelectedBox;
        if (box == null) { ClearStatus(); return; }

        // 1) 有缓存就先渲染，切换立刻有内容
        if (_infoCache.TryGetValue(box, out var cached))
        {
            _info = cached;
            _hasInfo = true;
            ApplyInfo(_info);
        }

        // 2) 120ms 防抖，连点只发一次 info
        _selDebounce?.Stop();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(120) };
        timer.Tick += async (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_selDebounce, timer)) return;   // 已被更新的选择取代
            await RefreshAsync();
        };
        _selDebounce = timer;
        timer.Start();
    }
}
