using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
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

public partial class MainWindow : Window
    {
    [DllImport("kernel32.dll")] private static extern uint GetOEMCP();

    private static readonly Encoding ConsoleEnc = ResolveConsoleEncoding();

    private static Encoding ResolveConsoleEncoding()
    {
        try
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            return Encoding.GetEncoding((int)GetOEMCP());
        }
        catch { return Encoding.UTF8; }
    }

    private Process _runProc;
    private bool _running;
    private DispatcherTimer _errTimer;
    private readonly string _ps = "powershell.exe";
    private readonly string _engine;
    private readonly string _root;
    private readonly EngineClient _client;

    private bool _busy;
    private DateTime _busyStart;
    private readonly DispatcherTimer _autoRefresh;
    private readonly DispatcherTimer _elapsed;
    private JsonElement _info = default;
    private bool _hasInfo;
    private readonly Dictionary<string, JsonElement> _infoCache = new();
    private int _refreshGen;
    private DispatcherTimer _selDebounce;
    private DateTime _lastActive = DateTime.Now;
    private readonly DispatcherTimer _idleTimer;
    private System.Windows.Forms.NotifyIcon _tray;
    private bool _reallyExit;
    private bool _isFull;
    private WindowStyle _styleBeforeFull;
    private Rect _boundsBeforeFull;

    public MainWindow()
    {
        InitializeComponent();
        CleanupLogs();
        EnsureSettingsVersion();

        (_engine, _root) = FindEngine();
        _client = new EngineClient(_engine, _root, LogTrace);
        VerText.Text = "v1.0";
        StatusLine.Text = $"引擎: {_engine}";

        Loaded += OnLoaded;
        Closing += OnClosing;

        _autoRefresh = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        _autoRefresh.Tick += async (_, _) =>
        {
            if (_busy) return;
            if (!IsVisible) return;                       // 托盘隐藏时完全不刷
            if (WindowState == WindowState.Minimized) return;
            await RefreshAsync();
        };
        Activated += async (_, _) => { if (!_busy) await RefreshAsync(); };
        _autoRefresh.Start();

        _elapsed = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _elapsed.Tick += (_, _) =>
        {
            if (_busy) ProgressText.Text = $"执行中 {(int)(DateTime.Now - _busyStart).TotalSeconds}s";
        };
        _elapsed.Start();

        _idleTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        _idleTimer.Tick += IdleTick;
        _idleTimer.Start();

        PreviewMouseMove += (_, _) => _lastActive = DateTime.Now;
        PreviewKeyDown += (_, _) => _lastActive = DateTime.Now;

        InitTray();
        InitClipboard();
        PreviewKeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.F11) { ToggleFull(); e.Handled = true; } };
    }

    private string SelectedBox => (BoxList.SelectedItem as BoxItem)?.Name ?? BoxList.SelectedItem as string;

    private async Task OnLoadedAsync()
    {
        if (Content is FrameworkElement root)
        {
            root.Opacity = 0;
            var tt = new TranslateTransform(0, 12);
            root.RenderTransform = tt;

            var fade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220));
            root.BeginAnimation(OpacityProperty, fade);

            var move = new DoubleAnimation(12, 0, TimeSpan.FromMilliseconds(280))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
            };
            tt.BeginAnimation(TranslateTransform.YProperty, move);
        }

        // 界面动画期间先把 daemon / wsl 缓存热起来
        _ = _client.PrewarmAsync();

        await LoadBoxesAsync();
        HookCardHover();

        // 预热当前抽屉的 info，首次点击不再等冷启动
        var warmBox = SelectedBox;
        if (warmBox != null) _ = CaptureAsync("info", warmBox, "-fast");

        if (Environment.GetCommandLineArgs().Any(a => string.Equals(a, "--tray", StringComparison.OrdinalIgnoreCase)))
        {
            var hideTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) };
            hideTimer.Tick += (_, _) =>
            {
                hideTimer.Stop();
                ShowInTaskbar = false;
                WindowState = WindowState.Minimized;
                Hide();
            };
            hideTimer.Start();
        }
    }

    private static void HookMenuAnimation()
    {
        EventManager.RegisterClassHandler(typeof(ContextMenu), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((s, _) =>
            {
                if (s is ContextMenu cm) AnimateDrawerMenu(cm);
            }));
    }

    private static void AnimateDrawerMenu(ContextMenu cm)
    {
        cm.ApplyTemplate();
        if (VisualTreeHelper.GetChildrenCount(cm) == 0) return;
        if (VisualTreeHelper.GetChild(cm, 0) is not FrameworkElement root) return;

        var tt = new TranslateTransform(0, -14);
        root.RenderTransform = tt;
        root.RenderTransformOrigin = new Point(0.5, 0);

        double h = root.ActualHeight, w = root.ActualWidth;
        if (h > 4 && w > 4)
        {
            var clip = new RectangleGeometry(new Rect(0, 0, w, h * 0.3));
            root.Clip = clip;
            var ca = new RectAnimation(new Rect(0, 0, w, h * 0.3), new Rect(0, 0, w, h),
                TimeSpan.FromMilliseconds(200))
            { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            ca.Completed += (_, _) => root.Clip = null;
            clip.BeginAnimation(RectangleGeometry.RectProperty, ca);
        }

        tt.BeginAnimation(TranslateTransform.YProperty,
            new DoubleAnimation(-14, 0, TimeSpan.FromMilliseconds(200))
            { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        root.BeginAnimation(UIElement.OpacityProperty,
            new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(140)));
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _ = OnLoadedAsync();

        var flag = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "onboarded");
        if (!File.Exists(flag))
        {
            try
            {
                new OnboardingWindow { Owner = this }.ShowDialog();
                File.WriteAllText(flag, DateTime.Now.ToString("s"));
            }
            catch { }
        }
    }

    // ---------------- 进程执行 ----------------

    private static bool ShouldKeep(string line)
    {
        if (line.Length == 0) return false;
        if (line.StartsWith("▸ box.ps1")) return true;          // 开始
        if (line.StartsWith("[结束]")) return true;             // 结束
        if (line.StartsWith("[标签]") || line.StartsWith("[快照]")) return true;

        // 问题
        foreach (var k in new[] { "✗", "⚠", "错误", "失败", "警告", "异常", "退出码", "找不到", "无法", "未找到", "error", "warn" })
            if (line.Contains(k, StringComparison.OrdinalIgnoreCase)) return true;

        // 结果行（成功收尾）
        foreach (var k in new[] { "完成", "已启动", "已停止", "已保存", "已删除", "已重命名",
                                  "已还原", "已创建", "已导出", "已注册", "已备份", "通过" })
            if (line.Contains(k)) return true;

        return false;
    }

    private void Log(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        var line = text.TrimEnd();
        if (!ShouldKeep(line)) return;
        Brush color;
        if (line.Contains("✗") || line.Contains("错误") || line.Contains("失败") ||
            line.Contains("error", StringComparison.OrdinalIgnoreCase)) color = Brushes.Red;
        else if (line.Contains("⚠") || line.Contains("警告") ||
                 line.Contains("warn", StringComparison.OrdinalIgnoreCase)) color = Brushes.DarkOrange;
        else if (line.Contains("✓") || line.Contains("成功") || line.Contains("完成")) color = Brushes.Green;
        else if (line.StartsWith("[阶段]")) color = Brushes.SteelBlue;
        else color = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0x3A, 0x3A, 0x3C));

        LogBox.Document.Blocks.Add(new Paragraph(new Run(line) { Foreground = color }) { Margin = new Thickness(0) });
        AppendLog(line);
        if (LogBox.Document.Blocks.Count > 2000)
        {
            for (int i = 0; i < 800 && LogBox.Document.Blocks.Count > 0; i++)
                LogBox.Document.Blocks.Remove(LogBox.Document.Blocks.FirstBlock);
        }
        LogBox.ScrollToEnd();
    }

    /// <summary>只写文件、不进界面：用于 daemon 耗时这类高频诊断。</summary>
    private void LogTrace(string text) => AppendLog(text);

    private static string LogDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "logs");

    private static string TodayLog => Path.Combine(LogDir, "gui-" + DateTime.Now.ToString("yyyyMMdd") + ".log");

    /// <summary>单文件超过 5 MB 轮转一次；写文件失败不影响界面。</summary>
    private static void AppendLog(string text)
    {
        try
        {
            Directory.CreateDirectory(LogDir);
            var file = TodayLog;
            if (File.Exists(file) && new FileInfo(file).Length > 5 * 1024 * 1024)
                File.Move(file, file + ".1", true);
            File.AppendAllText(file, DateTime.Now.ToString("HH:mm:ss") + " " + text + Environment.NewLine);
        }
        catch { }
    }

    /// <summary>启动清理：保留 14 天，其余 gui-*.log* 删除。</summary>
    private static void CleanupLogs()
    {
        try
        {
            if (!Directory.Exists(LogDir)) return;
            var cutoff = DateTime.Now.AddDays(-14);
            foreach (var f in new DirectoryInfo(LogDir).GetFiles("gui-*.log*"))
                if (f.LastWriteTime < cutoff) f.Delete();
        }
        catch { }
    }

    /// <summary>旧版 settings.json 没有 version，启动时补一个（保留其余字段）。</summary>
    private static void EnsureSettingsVersion()
    {
        try
        {
            var file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun", "settings.json");
            if (!File.Exists(file)) return;
            var root = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(file)) as System.Text.Json.Nodes.JsonObject;
            if (root == null || root.ContainsKey("version")) return;
            root["version"] = 1;
            File.WriteAllText(file, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    private void NoticeDismiss_Click(object sender, RoutedEventArgs e) => NoticeBar.Visibility = Visibility.Collapsed;

    private void ShowError(string msg)
    {
        ErrorText.Text = msg;
        ErrorBar.Visibility = Visibility.Visible;
        _errTimer?.Stop();
        _errTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(9) };
        _errTimer.Tick += (_, _) => { _errTimer.Stop(); ErrorBar.Visibility = Visibility.Collapsed; };
        _errTimer.Start();
    }

    private void ErrorDismiss_Click(object sender, RoutedEventArgs e) => ErrorBar.Visibility = Visibility.Collapsed;

    private List<string> SelectedNames() =>
        BoxList.SelectedItems.OfType<BoxItem>().Select(x => x.Name).ToList();

    // ---------------- 列表与状态 ----------------

    // ---------------- 事件 ----------------

    private void ToggleFull()
    {
        if (!_isFull)
        {
            _styleBeforeFull = WindowStyle;
            _boundsBeforeFull = new Rect(Left, Top, Width, Height);
            WindowState = WindowState.Normal;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            var wa = SystemParameters.WorkArea;
            Left = wa.Left;
            Top = wa.Top;
            Width = wa.Width;
            Height = wa.Height;
            _isFull = true;
        }
        else
        {
            WindowStyle = _styleBeforeFull;
            ResizeMode = ResizeMode.CanResize;
            Left = _boundsBeforeFull.Left;
            Top = _boundsBeforeFull.Top;
            Width = _boundsBeforeFull.Width;
            Height = _boundsBeforeFull.Height;
            _isFull = false;
        }
    }

}
