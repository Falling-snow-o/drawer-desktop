using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace BoxRun;

/// <summary>
/// 常驻引擎进程：加载一次引擎模块，之后 list/info 走 JSON 行协议。
/// 定位类似 Docker daemon：GUI 不承担引擎启动成本。
/// </summary>
public sealed class EngineDaemon : IDisposable
{
    private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);
    private readonly string _engine;
    private readonly string _root;
    private readonly ConcurrentDictionary<int, TaskCompletionSource<string>> _pending = new();
    private Process _proc;
    private int _nextId;
    private readonly object _gate = new();

    public EngineDaemon(string enginePath, string root)
    {
        _engine = enginePath;
        _root = root;
    }

    public bool IsAlive
    {
        get { try { return _proc != null && !_proc.HasExited; } catch { return false; } }
    }

    private string BuildScript()
    {
        var esc = _engine.Replace("'", "''");
        return $@"
$env:DRAWER_DAEMON='1'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$ErrorActionPreference='Stop'
$infoCache = @{{}}
. '{esc}'
while ($true) {{
    $task = [Console]::In.ReadLineAsync()
    if (-not $task.Wait(900000)) {{ break }}
    $l = $task.Result
    if ($null -eq $l) {{ break }}
    if (-not $l.Trim()) {{ continue }}
    $r = $null
    try {{
        $r = $l | ConvertFrom-Json
        $a = @($r.args | ForEach-Object {{ [string]$_ }})
        switch ($r.method) {{
            'list' {{ $out = ConvertTo-Json -Compress -Depth 5 -InputObject ([pscustomobject]@{{ boxes = @(Get-BoxList) }}) }}
            'info' {{
                $key = $a[0]
                $now = [DateTime]::UtcNow
                $hit = $infoCache[$key]
                if ($hit -and ($now - $hit.T).TotalMilliseconds -lt 4500) {{
                    $out = $hit.V
                }} else {{
                    $fast = ($a -contains '-fast')
                    $out = (Get-BoxInfo -Dir (Get-BoxDir $a[0]) -Fast:$fast | ConvertTo-Json -Compress -Depth 6)
                    $infoCache[$key] = @{{ T = $now; V = $out }}
                }}
            }}
            'catalog' {{
                $out = (Get-Catalog | ConvertTo-Json -Compress -Depth 6)
            }}
            'warm' {{
                $null = Get-WslListCached -TtlMs 0
                $out = 'ok'
            }}
            'invalidate' {{
                $infoCache.Clear()
                $out = 'ok'
            }}
            default {{ throw ('unsupported: ' + $r.method) }}
        }}
        $resp = [pscustomobject]@{{ id = $r.id; ok = $true; out = $out }}
    }} catch {{
        $id = if ($r) {{ $r.id }} else {{ 0 }}
        $resp = [pscustomobject]@{{ id = $id; ok = $false; out = $_.Exception.Message }}
    }}
    [Console]::Out.WriteLine(($resp | ConvertTo-Json -Compress -Depth 4))
    [Console]::Out.Flush()
}}
";
    }

    public void EnsureStarted()
    {
        lock (_gate)
        {
            if (IsAlive) return;
            _proc?.Dispose();
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Utf8NoBom,
                StandardErrorEncoding = Utf8NoBom,
                StandardInputEncoding = Utf8NoBom,
                WorkingDirectory = _root
            };
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-Command");
            psi.ArgumentList.Add(BuildScript());

            var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            p.OutputDataReceived += (_, e) =>
            {
                if (string.IsNullOrEmpty(e.Data)) return;
                try
                {
                    using var doc = JsonDocument.Parse(e.Data);
                    var root = doc.RootElement;
                    if (!root.TryGetProperty("id", out var idEl) || !idEl.TryGetInt32(out var id)) return;
                    var text = root.TryGetProperty("out", out var o) ? (o.GetString() ?? "") : "";
                    var ok = root.TryGetProperty("ok", out var okEl) && okEl.ValueKind == JsonValueKind.True;
                    if (_pending.TryRemove(id, out var tcs))
                    {
                        if (ok) tcs.TrySetResult(text);
                        else tcs.TrySetException(new Exception(text));
                    }
                }
                catch { }
            };
            p.ErrorDataReceived += (_, _) => { };
            p.Exited += (_, _) => FailAll("引擎进程退出");
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            _proc = p;
        }
    }

    public async Task<string> QueryAsync(string method, params string[] args)
    {
        EnsureStarted();
        var id = System.Threading.Interlocked.Increment(ref _nextId);
        var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[id] = tcs;

        var payload = JsonSerializer.Serialize(new { id, method, args });
        try
        {
            await _proc.StandardInput.WriteLineAsync(payload);
            await _proc.StandardInput.FlushAsync();
            using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(12));
            try { return await tcs.Task.WaitAsync(cts.Token); }
            catch (OperationCanceledException) { throw new TimeoutException("引擎查询超时"); }
        }
        finally
        {
            _pending.TryRemove(id, out _);
        }
    }

    private void FailAll(string reason)
    {
        foreach (var kv in _pending)
            if (_pending.TryRemove(kv.Key, out var tcs)) tcs.TrySetException(new Exception(reason));
    }

    public void Dispose()
    {
        try
        {
            if (_proc != null && !_proc.HasExited)
            {
                try { _proc.StandardInput.WriteLine(); } catch { }
                _proc.Kill(true);
            }
            _proc?.Dispose();
        }
        catch { }
        _proc = null;
        FailAll("引擎进程已关闭");
    }
}
