using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace BoxRun;

public partial class MainWindow
{
    private string _lastWin = "";
    private string _lastLinux = "";
    private DispatcherTimer _clipTimer;
    private DateTime _clipMtime = DateTime.MinValue;
    private string _fixedDir;

    private void InitClipboard()
    {
        _clipTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _clipTimer.Tick += (_, _) => ClipboardTick();
        _clipTimer.Start();
    }

    private void StopClipboardSync()
    {
        try { _clipTimer?.Stop(); } catch { }
    }

    private static void DebugLog(string msg)
    {
        try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "boxrun-clip.log"), DateTime.Now.ToString("HH:mm:ss") + " " + msg + Environment.NewLine); } catch { }
    }

    private string BoxDir()
    {
        if (!string.IsNullOrEmpty(_fixedDir) && Directory.Exists(_fixedDir))
            return _fixedDir;
        if (_hasInfo && _info.TryGetProperty("dir", out var d) && d.ValueKind == JsonValueKind.String)
            return d.GetString();
        return null;
    }

    private void ClipboardTick()
    {
        var dir = BoxDir();
        if (string.IsNullOrEmpty(dir)) return;

        var dataDir = Path.Combine(dir, "data");
        var linFile = Path.Combine(dataDir, ".boxrun-clip.linux");
        var winFile = Path.Combine(dataDir, ".boxrun-clip.win");

        // Linux -> Windows
        try
        {
            if (File.Exists(linFile))
            {
                var mt = File.GetLastWriteTimeUtc(linFile);
                if (mt != _clipMtime)
                {
                    _clipMtime = mt;
                    var text = File.ReadAllText(linFile);
                    if (!string.IsNullOrEmpty(text) && text != _lastLinux)
                    {
                        _lastLinux = text;
                        _lastWin = text;
                        bool ok = false;
                        for (int i = 0; i < 5 && !ok; i++)
                        {
                            try { Clipboard.SetText(text); ok = true; }
                            catch { System.Threading.Thread.Sleep(60); }
                        }
                        DebugLog("L->W len=" + text.Length + " ok=" + ok);
                    }
                }
            }
        }
        catch { }

        // Windows -> Linux
        try
        {
            var win = Clipboard.ContainsText() ? Clipboard.GetText() : "";
            if (win != _lastWin && !string.IsNullOrEmpty(win))
            {
                _lastWin = win;
                _lastLinux = win;
                try { File.WriteAllText(winFile, win, new UTF8Encoding(false)); DebugLog("W->L len=" + win.Length); }
                catch (Exception ex) { DebugLog("W->L fail: " + ex.Message); }
            }
        }
        catch { }
    }
}
