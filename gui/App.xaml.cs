using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace BoxRun;

public partial class App : System.Windows.Application
{
    private Mutex _mutex;
    private EventWaitHandle _activate;
    private const string ActivateName = @"Local\drawer-activate";
    private const string QuitName = @"Local\drawer-quit";
    private EventWaitHandle _quit;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string cls, string title);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr h, int cmd);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr h);

    public App()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Dump(e.ExceptionObject as Exception);
        DispatcherUnhandledException += (_, e) => Dump(e.Exception);
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        // 安装器/脚本用它请求优雅退出（不弹托盘、不杀进程）
        var argv = Environment.GetCommandLineArgs();

        // 测试钩子：--crash-test 触发一次未处理异常，用于验证崩溃报告
        if (Array.Exists(argv, a => string.Equals(a, "--crash-test", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("drawer crash test");
        if (Array.Exists(argv, a => string.Equals(a, "--quit", StringComparison.OrdinalIgnoreCase)))
        {
            try { using var q = EventWaitHandle.OpenExisting(QuitName); q.Set(); } catch { }
            Shutdown();
            return;
        }

        bool created;
        _mutex = new Mutex(true, @"Local\drawer-gui", out created);
        if (!created)
        {
            try
            {
                using var ev = EventWaitHandle.OpenExisting(ActivateName);
                ev.Set();
            }
            catch
            {
                var h = FindWindow(null, "Drawer Desktop");
                if (h != IntPtr.Zero) { ShowWindow(h, 9); SetForegroundWindow(h); }
            }
            Shutdown();
            return;
        }
        base.OnStartup(e);

        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        _activate = new EventWaitHandle(false, EventResetMode.AutoReset, ActivateName);
        Task.Run(() =>
        {
            while (true)
            {
                _activate.WaitOne();
                Dispatcher.BeginInvoke(new Action(() => (MainWindow as MainWindow)?.ShowFromTray()));
            }
        });

        _quit = new EventWaitHandle(false, EventResetMode.AutoReset, QuitName);
        Task.Run(() =>
        {
            while (true)
            {
                _quit.WaitOne();
                try { Dispatcher.BeginInvoke(new Action(() => (MainWindow as MainWindow)?.RequestQuit())); } catch { }
            }
        });

        var args = Environment.GetCommandLineArgs();
        bool tray = Array.Exists(args, a => string.Equals(a, "--tray", StringComparison.OrdinalIgnoreCase));

        if (tray)
        {
            var mw = new MainWindow();
            MainWindow = mw;
            ShutdownMode = ShutdownMode.OnMainWindowClose;
            mw.Show();
            return;
        }

        var mainWin = new MainWindow();
        MainWindow = mainWin;
        ShutdownMode = ShutdownMode.OnMainWindowClose;
        mainWin.Show();
        mainWin.Activate();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try { _mutex?.ReleaseMutex(); } catch { }
        try { _quit?.Dispose(); } catch { }
        base.OnExit(e);
    }

    private static void Dump(Exception ex)
    {
        string path = null;
        string text = "";
        try
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".boxrun", "crashes");
            Directory.CreateDirectory(dir);
            path = Path.Combine(dir, "crash-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" +
                                     Environment.ProcessId + ".txt");

            var sb = new System.Text.StringBuilder();
            sb.AppendLine("Drawer Desktop crash report");
            sb.AppendLine("time: " + DateTime.Now.ToString("s"));
            sb.AppendLine("app: " + (System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "?"));
            sb.AppendLine("os: " + Environment.OSVersion);
            sb.AppendLine("dotnet: " + Environment.Version);
            sb.AppendLine("args: " + string.Join(' ', Environment.GetCommandLineArgs()));
            sb.AppendLine(new string('-', 60));
            sb.AppendLine(ex?.ToString() ?? "unknown");
            text = sb.ToString();
            File.WriteAllText(path, text);

            // 兼容旧位置，方便既有诊断脚本
            File.WriteAllText(Path.Combine(Path.GetTempPath(), "drawer-crash.log"), text);
        }
        catch { }

        try
        {
            var settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".boxrun", "settings.json");
            if (!File.Exists(settings)) return;
            var url = "";
            using (var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(settings)))
                if (doc.RootElement.TryGetProperty("crashUrl", out var u)) url = u.GetString() ?? "";
            if (string.IsNullOrWhiteSpace(url)) return;

            using var http = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var content = new System.Net.Http.StringContent(text, System.Text.Encoding.UTF8, "text/plain");
            http.PostAsync(url, content).GetAwaiter().GetResult();
        }
        catch { }
    }
}