using System;
using System.Collections.Generic;
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
        public string Id;
        public string Box;
        public string Name;
        public string Host;
        public string Status;
        public string Started;
        public override string ToString() => $"{Name}  ·  {Box}  ·  {Status}";
    }

    private sealed class StepView
    {
        public int Seq;
        public string Cmd;
        public int Exit;
        public string Output;
        public string Diff;
        public List<string> Changed = new();
        public override string ToString()
        {
            var mark = Exit == 0 ? "✓" : "✗";
            return $"#{Seq}  {mark}  {Cmd}";
        }
    }

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
        if (selected != null)
            TaskList.SelectedItem = _tasks.FirstOrDefault(t => t.Id == selected);
        if (TaskList.SelectedItem == null && _tasks.Count > 0)
            TaskList.SelectedIndex = 0;
        if (_tasks.Count == 0)
        {
            TitleText.Text = "还没有任务";
            SubText.Text = "让 Agent 调 drawer_begin_task，或用 box.ps1 agent 开始一个任务";
            StepList.ItemsSource = null;
            DetailBox.Text = "";
        }
    }

    private static string Str(JsonElement r, string key)
        => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : "";

    private void TaskList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var t = TaskList.SelectedItem as TaskView;
        if (t == null) return;
        TitleText.Text = t.Name;
        SubText.Text = $"{t.Box}  ·  {t.Host}  ·  {t.Status}  ·  {t.Started}";

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
        else DetailBox.Text = "还没有步骤";
    }

    private void StepList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var s = StepList.SelectedItem as StepView;
        if (s == null) return;
        var text = $"$ {s.Cmd}\r\n\r\nexit: {s.Exit}\r\n";
        if (s.Changed.Count > 0) text += "changed: " + string.Join(", ", s.Changed) + "\r\n";
        if (!string.IsNullOrWhiteSpace(s.Diff)) text += "\r\n" + s.Diff + "\r\n";
        if (!string.IsNullOrWhiteSpace(s.Output)) text += "\r\n" + s.Output + "\r\n";
        DetailBox.Text = text;
    }

    private TaskView Current => TaskList.SelectedItem as TaskView;

    private async void CommitBtn_Click(object sender, RoutedEventArgs e) => await EndTask("commit");
    private async void RollbackBtn_Click(object sender, RoutedEventArgs e) => await EndTask("rollback");

    private async Task EndTask(string action)
    {
        var t = Current;
        if (t == null) return;
        if (t.Status != "running")
        {
            MessageBox.Show(this, "任务已经结束（" + t.Status + "）", "Agent 任务");
            return;
        }
        var confirm = MessageBox.Show(this,
            action == "commit" ? "把暂存的改动写回宿主目录？" : "丢弃这个任务的所有改动？",
            "Agent 任务", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (confirm != MessageBoxResult.Yes) return;

        try
        {
            var raw = await _run(new[] { "agent", t.Box, "end", t.Id, action });
            DetailBox.Text = raw.Trim();
            Reload();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "操作失败：" + ex.Message, "Agent 任务");
        }
    }

    private void RefreshBtn_Click(object sender, RoutedEventArgs e) => Reload();
    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
