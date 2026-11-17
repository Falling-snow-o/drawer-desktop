using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace BoxRunSetup;

internal static class Program
{
    private const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\Drawer Desktop";

    [STAThread]
    private static void Main(string[] args)
    {
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Drawer");
        bool shortcuts = true, uninstall = false, quiet = false, force = false, fromTemp = false;
        bool dirGiven = false;

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].ToLowerInvariant())
            {
                case "--dir": if (i + 1 < args.Length) { dir = Path.GetFullPath(args[++i]); dirGiven = true; } break;
                case "--no-shortcuts": shortcuts = false; break;
                case "--uninstall": uninstall = true; break;
                case "--quiet": quiet = true; break;
                case "--force": force = true; break;
                case "--from-temp": fromTemp = true; break;
            }
        }

        try
        {
            if (uninstall) { RunUninstall(dir, shortcuts, quiet, fromTemp); return; }
            if (!quiet && !dirGiven)
            {
                using var f = new OptionsForm(dir);
                if (f.ShowDialog() != DialogResult.OK) return;
                dir = f.InstallDir;
                shortcuts = f.Shortcuts;
                RunInstall(dir, shortcuts, quiet, force, f.Autostart);
                return;
            }
            RunInstall(dir, shortcuts, quiet, force, true);
        }
        catch (Exception ex)
        {
            Log("FAIL " + ex);
            if (!quiet)
                MessageBox.Show("安装失败：\n\n" + ex.Message, "Drawer Desktop", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static void RunInstall(string dir, bool shortcuts, bool quiet, bool force, bool autostart)
    {
        if (!force && !HasDotNet8(quiet)) return;
        if (!quiet) CheckWsl();

        var asm = Assembly.GetExecutingAssembly();
        var names = asm.GetManifestResourceNames();
        Log("resources=" + string.Join(",", names));
        var resName = names.FirstOrDefault(n => n.EndsWith("payload.zip", StringComparison.OrdinalIgnoreCase));
        if (resName == null) throw new InvalidOperationException("安装包缺少 payload.zip");

        var temp = Path.Combine(Path.GetTempPath(), "drawer-payload-" + Guid.NewGuid().ToString("N") + ".zip");
        using (var r = asm.GetManifestResourceStream(resName))
        using (var f = File.Create(temp))
            r.CopyTo(f);

        Directory.CreateDirectory(dir);
        using (var zip = ZipFile.OpenRead(temp))
        {
            foreach (var e in zip.Entries)
            {
                if (string.IsNullOrEmpty(e.Name)) continue;
                var target = Path.Combine(dir, e.FullName.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                e.ExtractToFile(target, true);
            }
        }
        try { File.Delete(temp); } catch { }

        File.WriteAllText(Path.Combine(dir, "boxrun.ini"), Path.Combine(dir, "box.ps1") + Environment.NewLine);

        var self = Environment.ProcessPath;
        var selfCopy = Path.Combine(dir, "drawer-setup.exe");
        if (!string.IsNullOrEmpty(self) && !string.Equals(self, selfCopy, StringComparison.OrdinalIgnoreCase))
            try { File.Copy(self, selfCopy, true); } catch { }

        if (shortcuts) CreateShortcuts(dir);
        WriteUninstallEntry(dir);
        if (autostart) WriteAutostart(dir);
        Log("installed to " + dir);

        if (quiet) return;

        var r2 = MessageBox.Show(
            "Drawer Desktop 已安装到：\n" + dir + "\n\n" +
            (shortcuts ? "桌面和开始菜单已创建快捷方式，开始菜单里也有卸载。\n\n" : "") +
            "现在启动吗？",
            "Drawer Desktop", MessageBoxButtons.YesNo, MessageBoxIcon.Information);

        if (r2 == DialogResult.Yes)
            try { Process.Start(new ProcessStartInfo(Path.Combine(dir, "Drawer.exe")) { UseShellExecute = true }); }
            catch { }
    }

    private static bool HasDotNet8(bool quiet)
    {
        var roots = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "dotnet"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "dotnet")
        };
        foreach (var root in roots)
        {
            try
            {
                var fx = Path.Combine(root, "shared", "Microsoft.WindowsDesktop.App");
                if (Directory.Exists(fx) &&
                    Directory.EnumerateDirectories(fx).Any(d => Path.GetFileName(d).StartsWith("8.")))
                    return true;
            }
            catch { }
        }

        if (quiet) return false;

        var r = MessageBox.Show(
            "这台机器没有 .NET 8 桌面运行时，管理器无法启动。\n\n" +
            "要现在打开下载页吗？（装完再运行本安装包）",
            "Drawer Desktop — 缺少运行时", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (r == DialogResult.Yes)
            try { Process.Start(new ProcessStartInfo("https://dotnet.microsoft.com/download/dotnet/8.0/runtime") { UseShellExecute = true }); }
            catch { }
        return false;
    }

    private static void CheckWsl()
    {
        try
        {
            var psi = new ProcessStartInfo("wsl.exe", "--status")
            { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            using var p = Process.Start(psi);
            p.WaitForExit(5000);
            if (p.ExitCode == 0) return;
        }
        catch { }

        Log("WSL check: not available, install will continue");
    }

    private static void WriteAutostart(string dir)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
            k.SetValue("Drawer Desktop", "\"" + Path.Combine(dir, "Drawer.exe") + "\" --tray");
        }
        catch { }
    }

    private static void RemoveAutostart()
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
            k?.DeleteValue("Drawer Desktop", false);
        }
        catch { }
    }

    private static void WriteUninstallEntry(string dir)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(UninstallKey);
            k.SetValue("DisplayName", "Drawer Desktop");
            k.SetValue("DisplayVersion", "1.0.0");
            k.SetValue("Publisher", "Drawer Desktop");
            k.SetValue("InstallLocation", dir);
            k.SetValue("DisplayIcon", Path.Combine(dir, "Drawer.exe"));
            k.SetValue("UninstallString", "\"" + Path.Combine(dir, "drawer-setup.exe") + "\" --uninstall --dir \"" + dir + "\"");
            k.SetValue("NoModify", 1, RegistryValueKind.DWord);
            k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }
        catch { }
    }

    private static void RunUninstall(string dir, bool shortcuts, bool quiet, bool fromTemp)
    {
        var self = Environment.ProcessPath;
        if (!fromTemp && self != null && self.StartsWith(dir, StringComparison.OrdinalIgnoreCase))
        {
            // 自己在安装目录里，删不掉自己：拷到临时目录再执行
            var tmp = Path.Combine(Path.GetTempPath(), "drawer-uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
            File.Copy(self, tmp, true);
            var q = quiet ? " --quiet" : "";
            Process.Start(tmp, $"--uninstall --dir \"{dir}\"{q} --from-temp");
            return;
        }

        try { Directory.SetCurrentDirectory(Path.GetTempPath()); } catch { }

        // 关掉正在运行的管理器，否则 exe 被占用
        foreach (var p in Process.GetProcessesByName("Drawer"))
        {
            try
            {
                var path = p.MainModule?.FileName;
                if (path != null && path.StartsWith(dir, StringComparison.OrdinalIgnoreCase))
                {
                    Log("stopping running BoxRun pid=" + p.Id);
                    p.CloseMainWindow();
                    if (!p.WaitForExit(3000)) p.Kill(true);
                }
            }
            catch { }
        }
        try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); } catch { }
        RemoveAutostart();
        if (shortcuts) RemoveShortcuts();

        if (!Directory.Exists(dir))
        {
            if (!quiet) MessageBox.Show("程序目录不存在，已清理快捷方式和注册项。", "Drawer Desktop");
            return;
        }

        var ok = false;
        for (var i = 0; i < 15 && !ok; i++)
        {
            try
            {
                Directory.Delete(dir, true);
                ok = true;
            }
            catch (Exception ex)
            {
                Log("delete retry " + i + ": " + ex.Message);
                try
                {
                    var exe2 = Path.Combine(dir, "Drawer.exe");
                    using (var fs = File.Open(exe2, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
                    Log("  probe: open ok (not locked)");
                    try { File.Delete(exe2); Log("  probe: file delete ok"); }
                    catch (Exception e3) { Log("  probe: file delete fail " + e3.Message); }
                }
                catch (Exception e2) { Log("  probe: open fail " + e2.Message); }
                try
                {
                    foreach (var f in Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories))
                        try { File.SetAttributes(f, FileAttributes.Normal); } catch { }
                }
                catch { }
                Thread.Sleep(600);
            }
        }

        if (!ok)
        {
            // 兜底：交回 cmd，等本进程退出后再删（通常是被杀软短暂占用）
            try
            {
                var psi = new ProcessStartInfo("cmd.exe",
                    $"/c ping 127.0.0.1 -n 5 >nul & rmdir /s /q \"{dir}\"")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = Path.GetTempPath(),
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                Process.Start(psi);
                Log("fallback scheduled");
            }
            catch (Exception ex) { Log("fallback fail: " + ex.Message); }
        }

        if (!quiet)
        {
            var cfg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun");
            MessageBox.Show(
                "已卸载程序、快捷方式和卸载项。\n\n" +
                "箱子数据没有动：\n" + cfg + "\n\n" +
                "如需彻底清理，请手动删除该目录（或先打开管理器删除箱子）。",
                "Drawer Desktop", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }

    private static void CreateShortcuts(string dir)
    {
        var exe = Path.Combine(dir, "Drawer.exe");
        var wsType = Type.GetTypeFromProgID("WScript.Shell");
        if (wsType == null) return;
        dynamic ws = Activator.CreateInstance(wsType);

        void Mk(string path, string target, string args)
        {
            dynamic sc = ws.CreateShortcut(path);
            sc.TargetPath = target;
            sc.Arguments = args;
            sc.WorkingDirectory = dir;
            sc.IconLocation = exe + ",0";
            sc.Save();
        }

        Mk(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Drawer Desktop.lnk"), exe, "");

        var menuDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            @"Microsoft\Windows\Start Menu\Programs\Drawer Desktop");
        Directory.CreateDirectory(menuDir);
        Mk(Path.Combine(menuDir, "Drawer Desktop.lnk"), exe, "");
        Mk(Path.Combine(menuDir, "卸载 Drawer Desktop.lnk"), Path.Combine(dir, "drawer-setup.exe"), "--uninstall --dir \"" + dir + "\"");
    }

    private static void RemoveShortcuts()
    {
        try
        {
            var desktop = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Drawer Desktop.lnk");
            if (File.Exists(desktop)) File.Delete(desktop);
            var menuDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                @"Microsoft\Windows\Start Menu\Programs\Drawer Desktop");
            if (Directory.Exists(menuDir)) Directory.Delete(menuDir, true);
        }
        catch { }
    }

    private static void Log(string m)
    {
        try
        {
            File.AppendAllText(Path.Combine(Path.GetTempPath(), "drawer-setup.log"),
                DateTime.Now.ToString("HH:mm:ss") + " " + m + Environment.NewLine);
        }
        catch { }
    }
}

internal sealed class OptionsForm : Form
{
    private readonly TextBox _path;
    private readonly CheckBox _sc;
    private readonly CheckBox _auto;

    public string InstallDir => _path.Text.Trim();
    public bool Shortcuts => _sc.Checked;
    public bool Autostart => _auto.Checked;

    public OptionsForm(string defaultDir)
    {
        Text = "安装 Drawer Desktop";
        Width = 560;
        Height = 240;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        Font = new System.Drawing.Font("Segoe UI", 9.5f);

        var lbl = new Label { Text = "安装位置：", Left = 20, Top = 22, AutoSize = true };
        _path = new TextBox { Left = 20, Top = 46, Width = 400, Text = defaultDir };
        var browse = new Button { Text = "浏览…", Left = 430, Top = 44, Width = 90 };
        browse.Click += (_, _) =>
        {
            using var d = new FolderBrowserDialog { SelectedPath = _path.Text };
            if (d.ShowDialog() == DialogResult.OK) _path.Text = d.SelectedPath;
        };

        _sc = new CheckBox { Text = "创建桌面和开始菜单快捷方式", Left = 20, Top = 88, Width = 480, Checked = true };
        _auto = new CheckBox { Text = "开机自动启动（托盘常驻，剪贴板同步需要）", Left = 20, Top = 116, Width = 480, Checked = true };

        var ok = new Button { Text = "安装", Left = 340, Top = 160, Width = 90, DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "取消", Left = 436, Top = 160, Width = 90, DialogResult = DialogResult.Cancel };
        AcceptButton = ok;
        CancelButton = cancel;

        Controls.AddRange(new Control[] { lbl, _path, browse, _sc, _auto, ok, cancel });
    }
}