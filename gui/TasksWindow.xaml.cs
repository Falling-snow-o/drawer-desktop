using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

namespace BoxRun;

public partial class TasksWindow : Window
{
    private readonly Func<string[], Task<string>> _run;
    private readonly string _root;
    private readonly List<TaskView> _tasks = new();
    private readonly List<StepView> _steps = new();

    private sealed class TaskView
    {
        public string Id, Box, Name, Host, Status, Started;
        public override string ToString() => $"{Name}  ·  {Friendly(Status)}";
    }

    private sealed class StepView
    {
        public int Seq;
        public string Cmd, Output, Diff;
        public int Exit;
        public List<string> Changed = new();
        public override string ToString() => $"第 {Seq} 步 · {(Exit == 0 ? "成功" : "失败")}";
    }

    private static string Friendly(string status) => status switch
    {
        "running" => "进行中",
        "committed" => "已保留",
        "rolledback" => "已撤销",
        _ => status
    };

    public TasksWindow(Func<string[], Task<string>> run)
    {
        InitializeComponent();
        _run = run;
        _root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Drawer", "tasks");
        Loaded += (_, _) => Reload();
    }

    private void Reload()
    {
        var selected = (TaskList.SelectedItem as TaskView)?.Id;
        _tasks.Clear();
        if (Directory.Exists(_root))
        {
            foreach (var d in Directory.GetDirectories(_root).OrderByDescending(x => x))
            {
                var f = Path.Combine(d, "task.json");
                if (!File.Exists(f)) continue;
                try
                {
                    using var doc = JsonDocument.Parse(File.ReadAllText(f));
                    var r = doc.RootElement;
                    _tasks.Add(new TaskView
                    {
                        Id = Str(r, "id"),
                        Box = Str(r, "box"),
                        Name = Str(r, "name"),
                        Host = Str(r, "host"),
                        Status = Str(r, "status"),
                        Started = Str(r, "started"),
                    });
                }
                catch { }
            }
        }

        TaskList.ItemsSource = null;
        TaskList.ItemsSource = _tasks;
        if (selected != null) TaskList.SelectedItem = _tasks.FirstOrDefault(t => t.Id == selected);
        if (TaskList.SelectedItem == null && _tasks.Count > 0) TaskList.SelectedIndex = 0;

        if (_tasks.Count == 0)
        {
            TitleText.Text = "还没有任务";
            SubText.Text = "让 AI 帮你改代码时，每一步都会记在这里";
            HelpCard.Visibility = Visibility.Visible;
            StepList.Visibility = Visibility.Collapsed;
            DetailTitle.Text = "AI 会做什么";
            DetailBox.Text = "\n准备就绪后，这里会显示 AI 改了什么。";
            CommitBtn.IsEnabled = RollbackBtn.IsEnabled = false;
        }
    }

    private static string Str(JsonElement r, string key)
        => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : "";

    private TaskView Current => TaskList.SelectedItem as TaskView;

    private void TaskList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var t = Current;
        if (t == null) return;

        HelpCard.Visibility = Visibility.Collapsed;
        StepList.Visibility = Visibility.Visible;
        TitleText.Text = t.Name;
        SubText.Text = $"抽屉 {t.Box}  ·  {t.Started.Replace("T", " ")}  ·  {Friendly(t.Status)}";
        CommitBtn.IsEnabled = RollbackBtn.IsEnabled = t.Status == "running";

        _steps.Clear();
        var sf = Path.Combine(_root, t.Id, "steps.jsonl");
        if (File.Exists(sf))
        {
            foreach (var line in File.ReadLines(sf))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    using var doc = JsonDocument.Parse(line);
                    var r = doc.RootElement;
                    var s = new StepView
                    {
                        Seq = r.TryGetProperty("seq", out var seq) ? seq.GetInt32() : 0,
                        Cmd = Str(r, "cmd"),
                        Exit = r.TryGetProperty("exit", out var ex) ? ex.GetInt32() : 0,
                        Output = Str(r, "output"),
                        Diff = Str(r, "diff"),
                    };
                    if (r.TryGetProperty("changed", out var ch) && ch.ValueKind == JsonValueKind.Array)
                        foreach (var c in ch.EnumerateArray()) s.Changed.Add(c.GetString());
                    _steps.Add(s);
                }
                catch { }
            }
        }

        StepList.ItemsSource = null;
        StepList.ItemsSource = _steps;
        if (_steps.Count > 0) StepList.SelectedIndex = _steps.Count - 1;
        else
        {
            DetailTitle.Text = "还没有步骤";
            DetailBox.Text = "\nAI 还没有开始操作。";
        }
    }

    private void StepList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var s = StepList.SelectedItem as StepView;
        if (s == null) return;
        DetailTitle.Text = $"第 {s.Seq} 步做了什么";
        var text = $"做了什么：{s.Cmd}\r\n结果：{(s.Exit == 0 ? "成功" : "失败")}\r\n";
        if (s.Changed.Count > 0)
            text += $"改了 {s.Changed.Count} 个文件：{string.Join("、", s.Changed)}\r\n";
        if (!string.IsNullOrWhiteSpace(s.Diff)) text += "\r\n" + s.Diff + "\r\n";
        if (!string.IsNullOrWhiteSpace(s.Output)) text += "\r\nAI 的输出：\r\n" + s.Output + "\r\n";
        DetailBox.Text = text;
    }

    private async void CommitBtn_Click(object sender, RoutedEventArgs e) => await EndTask("commit");
    private async void RollbackBtn_Click(object sender, RoutedEventArgs e) => await EndTask("rollback");

    private async Task EndTask(string action)
    {
        var t = Current;
        if (t == null) return;
        if (t.Status != "running")
        {
            MessageBox.Show(this, "这个任务已经结束了。", "AI 任务");
            return;
        }

        var confirm = MessageBox.Show(this,
            action == "commit"
                ? "把 AI 改过的内容保存到你的文件夹？"
                : "撤销 AI 的所有改动？你的文件夹会保持原样。",
            "AI 任务", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (confirm != MessageBoxResult.Yes) return;

        try
        {
            await _run(new[] { "agent", t.Box, "end", t.Id, action });
            Reload();
            MessageBox.Show(this, action == "commit" ? "已保存到你的文件夹。" : "已撤销，文件夹没有变化。", "AI 任务");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "操作失败：" + ex.Message, "AI 任务");
        }
    }

    private void CopyConfigBtn_Click(object sender, RoutedEventArgs e)
    {
        var exe = Path.Combine(AppContext.BaseDirectory, "drawer-mcp.exe");
        var esc = exe.Replace("\\", "\\\\");
        var json = "{\n  \"mcpServers\": {\n    \"drawer\": {\n      \"command\": \"" + esc + "\"\n    }\n  }\n}";
        try
        {
            Clipboard.SetText(json);
            MessageBox.Show(this,
                "已复制。把它粘到 Claude Code / Cursor 的 MCP 设置里，\n然后对 AI 说：用 drawer 工具修改 D:\\你的项目",
                "AI 任务");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "复制失败：" + ex.Message, "AI 任务");
        }
    }

    private void DocsBtn_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var local = Path.Combine(AppContext.BaseDirectory, "AGENT.md");
            if (File.Exists(local)) Process.Start(new ProcessStartInfo(local) { UseShellExecute = true });
            else Process.Start(new ProcessStartInfo("https://github.com/Falling-snow-o/drawer-desktop/blob/master/AGENT.md") { UseShellExecute = true });
        }
        catch { }
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
