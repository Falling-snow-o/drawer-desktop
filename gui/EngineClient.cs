using System;
using System.Diagnostics;
using System.Text;
using System.Threading.Tasks;

namespace BoxRun;

/// <summary>只负责“怎么调用引擎”：参数拼接、编码、抓输出。与界面状态解耦。</summary>
public sealed class EngineClient
{
    private readonly string _ps;
    private readonly string _engine;
    private readonly EngineDaemon _daemon;
    private readonly Action<string> _log;
    private readonly System.Collections.Generic.Dictionary<string, int> _calls = new();
    private volatile bool _daemonReady;

    public string EnginePath => _engine;
    public string WorkingRoot { get; }

    public EngineClient(string enginePath, string workingRoot, Action<string> log = null, string powershell = "powershell.exe")
    {
        _engine = enginePath;
        WorkingRoot = workingRoot;
        _ps = powershell;
        _log = log;
        _daemon = new EngineDaemon(enginePath, workingRoot);
    }

    public void Dispose() => _daemon.Dispose();

    /// <summary>启动预热：把 daemon 和 wsl 列表缓存先热起来（失败无所谓）。</summary>
    public async Task PrewarmAsync()
    {
        try
        {
            await _daemon.QueryAsync("warm");
            await _daemon.QueryAsync("list");
            _daemonReady = true;
            _log?.Invoke("[daemon] 已就绪");
        }
        catch (Exception ex) { _daemonReady = false; _log?.Invoke("[daemon] 预热失败: " + ex.Message); }
    }

    /// <summary>动作完成后让 daemon 丢掉 info 缓存，避免看到旧状态。</summary>
    public async Task InvalidateAsync()
    {
        try { await _daemon.QueryAsync("invalidate"); } catch { }
    }

    public ProcessStartInfo CreateStartInfo(params string[] args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = _ps,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = WorkingRoot
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-Command");

        // 用 -Command 包一层，强制子进程按 UTF-8 输出，避免 ▸ ✓ 这类符号变成问号
        var sb = new StringBuilder();
        sb.Append("chcp 65001 > $null; [Console]::OutputEncoding=[Text.Encoding]::UTF8; & '");
        sb.Append(_engine.Replace("'", "''")).Append('\'');
        foreach (var a in args)
        {
            sb.Append(' ');
            if (a.IndexOfAny(new[] { ' ', '"', '\'', '\t' }) >= 0)
                sb.Append('\'').Append(a.Replace("'", "''")).Append('\'');
            else
                sb.Append(a);
        }
        psi.ArgumentList.Add(sb.ToString());
        return psi;
    }

    private static (string Method, string[] Args)? MapToDaemon(string[] args)
    {
        if (args.Length == 0) return null;

        if (args[0] == "api" && args.Length >= 2)
        {
            if (args[1] == "list") return ("list", Array.Empty<string>());
            if (args[1] == "catalog") return ("catalog", Array.Empty<string>());
            return null;
        }
        if (args[0] == "info" && args.Length >= 2)
        {
            var extra = Array.IndexOf(args, "-fast") >= 0 ? new[] { args[1], "-fast" } : new[] { args[1] };
            return ("info", extra);
        }
        return null;
    }

    public async Task<string> CaptureAsync(params string[] args)
    {
        // 热路径：只读查询走常驻引擎，不再每次启动 PowerShell
        var mapped = _daemonReady ? MapToDaemon(args) : null;
        if (mapped != null)
        {
            try
            {
                var sw = Stopwatch.StartNew();
                var r = await _daemon.QueryAsync(mapped.Value.Method, mapped.Value.Args);
                _calls.TryGetValue(mapped.Value.Method, out var n);
                _calls[mapped.Value.Method] = ++n;
                var ms = sw.ElapsedMilliseconds;
                if (n == 1 || n % 50 == 0 || ms > 500)
                    _log?.Invoke($"[daemon] {mapped.Value.Method}#{n} {ms}ms");
                return r;
            }
            catch { _daemon.Dispose(); }
        }

        using var p = new Process { StartInfo = CreateStartInfo(args) };
        p.Start();
        var stdout = await p.StandardOutput.ReadToEndAsync();
        var stderr = await p.StandardError.ReadToEndAsync();
        await p.WaitForExitAsync();
        return stdout + (string.IsNullOrWhiteSpace(stderr) ? "" : "\n" + stderr);
    }
}
