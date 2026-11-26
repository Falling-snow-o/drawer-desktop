using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace DrawerMcp;

internal static class Program
{
    private static string _engine;
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);

    private static int Main()
    {
        Console.InputEncoding = Utf8;
        Console.OutputEncoding = Utf8;
        try { _engine = FindEngine(); }
        catch (Exception ex) { Console.Error.WriteLine(ex.Message); return 1; }

        string line;
        while ((line = Console.In.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            JsonNode req;
            try { req = JsonNode.Parse(line); }
            catch { continue; }

            var id = req?["id"];
            var method = req?["method"]?.GetValue<string>();
            if (string.IsNullOrEmpty(method)) continue;

            // 通知（没有 id）不需要回复
            if (id == null) continue;

            try
            {
                switch (method)
                {
                    case "initialize":
                        Respond(id, new
                        {
                            protocolVersion = "2024-11-05",
                            capabilities = new { tools = new { } },
                            serverInfo = new { name = "drawer-mcp", version = "0.1.0" }
                        });
                        break;
                    case "tools/list":
                        Respond(id, new { tools = Tools() });
                        break;
                    case "tools/call":
                        HandleCall(id, req["params"]);
                        break;
                    case "ping":
                        Respond(id, new { });
                        break;
                    default:
                        Error(id, -32601, "method not found: " + method);
                        break;
                }
            }
            catch (Exception ex)
            {
                Error(id, -32000, ex.Message);
            }
        }
        return 0;
    }

    private static object[] Tools() => new object[]
    {
        Tool("drawer_begin_task",
            "Start a disposable agent task for a host directory. Creates a staged copy, snapshots it with git, and mounts it at /work in the drawer.",
            new { box = Str("drawer name"), host_dir = Str("host directory to work on"), name = Str("optional task name") },
            new[] { "box", "host_dir" }),
        Tool("drawer_exec",
            "Run a shell command inside the task's /work directory. Records the step, exit code, output and changed files.",
            new { task_id = Str("task id"), command = Str("shell command") },
            new[] { "task_id", "command" }),
        Tool("drawer_end_task",
            "Finish a task: commit applies the staged changes to the host directory; rollback discards them.",
            new { task_id = Str("task id"), action = new { type = "string", @enum = new[] { "commit", "rollback" } } },
            new[] { "task_id", "action" }),
        Tool("drawer_task_status",
            "Show one task and all recorded steps.",
            new { task_id = Str("task id") },
            new[] { "task_id" }),
        Tool("drawer_list_tasks",
            "List recorded agent tasks (newest first).",
            new { },
            Array.Empty<string>()),
    };

    private static object Tool(string name, string description, object properties, string[] required) => new
    {
        name,
        description,
        inputSchema = new
        {
            type = "object",
            properties,
            required
        }
    };

    private static object Str(string description) => new { type = "string", description };

    private static void HandleCall(JsonNode id, JsonNode p)
    {
        var name = p?["name"]?.GetValue<string>();
        var args = p?["arguments"] as JsonObject ?? new JsonObject();

        string output;
        try
        {
            switch (name)
            {
                case "drawer_begin_task":
                    output = RunEngine("agent", Get(args, "box", true), "begin",
                        Get(args, "host_dir", true), Get(args, "name", false));
                    break;
                case "drawer_exec":
                    output = RunEngine("agent", _boxForTask(Get(args, "task_id", true)), "exec",
                        Get(args, "task_id", true), Get(args, "command", true));
                    break;
                case "drawer_end_task":
                    output = RunEngine("agent", _boxForTask(Get(args, "task_id", true)), "end",
                        Get(args, "task_id", true), Get(args, "action", true));
                    break;
                case "drawer_task_status":
                    output = RunEngine("agent", _boxForTask(Get(args, "task_id", true)), "show",
                        Get(args, "task_id", true));
                    break;
                case "drawer_list_tasks":
                    output = RunEngine("agent", "list");
                    break;
                default:
                    ToolError(id, "unknown tool: " + name);
                    return;
            }
        }
        catch (Exception ex)
        {
            ToolError(id, ex.Message);
            return;
        }

        Respond(id, new
        {
            content = new[] { new { type = "text", text = output } },
            isError = false
        });
    }

    private static string _boxForTask(string taskId)
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Drawer", "tasks", taskId);
        var file = Path.Combine(root, "task.json");
        if (!File.Exists(file)) throw new Exception("task not found: " + taskId);
        using var doc = JsonDocument.Parse(File.ReadAllText(file));
        return doc.RootElement.GetProperty("box").GetString();
    }

    private static string Get(JsonObject args, string key, bool required)
    {
        if (args.TryGetPropertyValue(key, out var node) && node != null)
        {
            var s = node.GetValue<string>();
            if (!string.IsNullOrWhiteSpace(s)) return s;
        }
        if (required) throw new Exception("missing argument: " + key);
        return null;
    }

    private static string RunEngine(params string[] args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Utf8,
            StandardErrorEncoding = Utf8,
            WorkingDirectory = Path.GetDirectoryName(_engine)
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(_engine);
        foreach (var a in args) if (a != null) psi.ArgumentList.Add(a);

        using var p = Process.Start(psi);
        var stdout = p.StandardOutput.ReadToEnd();
        var stderr = p.StandardError.ReadToEnd();
        p.WaitForExit();

        var text = (stdout + (string.IsNullOrWhiteSpace(stderr) ? "" : "\n" + stderr)).Trim();
        // 取最后一行 JSON（引擎会先打印人类可读的进度）
        var lines = text.Split('\n');
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var l = lines[i].Trim();
            if ((l.StartsWith("{") && l.EndsWith("}")) || (l.StartsWith("[") && l.EndsWith("]")))
            {
                try { JsonDocument.Parse(l); return l; } catch { }
            }
        }
        return text;
    }

    private static string FindEngine()
    {
        var env = Environment.GetEnvironmentVariable("DRAWER_ENGINE");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env)) return env;

        var dir = AppContext.BaseDirectory;
        var ini = Path.Combine(dir, "boxrun.ini");
        if (File.Exists(ini))
        {
            var first = File.ReadAllLines(ini).FirstOrDefault(l => l.Trim().Length > 0 && !l.TrimStart().StartsWith("#"));
            if (first != null && File.Exists(first.Trim())) return first.Trim();
        }

        var d = new DirectoryInfo(dir);
        for (var i = 0; i < 8 && d != null; i++)
        {
            var c = Path.Combine(d.FullName, "box.ps1");
            if (File.Exists(c)) return c;
            d = d.Parent;
        }

        const string fallback = @"D:\Acta\boxrun\box.ps1";
        if (File.Exists(fallback)) return fallback;
        throw new Exception("box.ps1 not found; set DRAWER_ENGINE");
    }

    private static void Respond(JsonNode id, object result)
    {
        var msg = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id.DeepClone(),
            ["result"] = JsonSerializer.SerializeToNode(result)
        };
        Console.Out.WriteLine(msg.ToJsonString());
        Console.Out.Flush();
    }

    private static void Error(JsonNode id, int code, string message)
    {
        var msg = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = id.DeepClone(),
            ["error"] = new JsonObject { ["code"] = code, ["message"] = message }
        };
        Console.Out.WriteLine(msg.ToJsonString());
        Console.Out.Flush();
    }

    private static void ToolError(JsonNode id, string message)
    {
        Respond(id, new
        {
            content = new[] { new { type = "text", text = "ERROR: " + message } },
            isError = true
        });
    }
}
