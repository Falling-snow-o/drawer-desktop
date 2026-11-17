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
        base.OnExit(e);
    }

    private static void Dump(Exception ex)
    {
        try
        {
            File.WriteAllText(
                Path.Combine(Path.GetTempPath(), "drawer-crash.log"),
                DateTime.Now + "\r\n" + (ex?.ToString() ?? "unknown"));
        }
        catch { }
    }
}