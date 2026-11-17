using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.Json;
using System.Windows;

namespace BoxRun;

public sealed class PortItem
{
    public int Port { get; set; }
    public string Status { get; set; } = "检测中";
    public string PortText => ":" + Port;
    public string Url => "http://localhost:" + Port;
}

public partial class PortsWindow : Window
{
    private readonly string _box;
    private readonly Func<System.Threading.Tasks.Task<string>> _load;

    public PortsWindow(string box, Func<System.Threading.Tasks.Task<string>> load)
    {
        InitializeComponent();
        _box = box;
        _load = load;
        SubText.Text = box;
        Loaded += async (_, _) => await Reload();
        InteractionHub.ActionCompleted += OnExternalChange;
        InteractionHub.BoxesChanged += OnExternalChange;
        Closed += (_, _) =>
        {
            InteractionHub.ActionCompleted -= OnExternalChange;
            InteractionHub.BoxesChanged -= OnExternalChange;
        };
    }

    private void OnExternalChange(string _)
    {
        if (InteractionHub.IsBusy) return;
        Dispatcher.BeginInvoke(async () => await Reload());
    }

    private void OnExternalChange()
    {
        if (InteractionHub.IsBusy) return;
        Dispatcher.BeginInvoke(async () => await Reload());
    }


    private async System.Threading.Tasks.Task Reload()
    {
        HintText.Text = "正在启动抽屉并读取端口…";
        string raw;
        try { raw = await _load(); }
        catch (Exception ex)
        {
            HintText.Text = "读取失败：" + ex.Message;
            PortList.ItemsSource = null;
            return;
        }
        var items = new List<PortItem>();
        try
        {
            var json = JsonUtil.Array(raw);
            var arr = JsonSerializer.Deserialize<List<PortItem>>(json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (arr != null) items = arr;
        }
        catch { }

        PortList.ItemsSource = items;
        HintText.Text = items.Count == 0 ? "没有监听端口（先启动一个服务）" : items.Count + " 个端口";

        foreach (var it in items)
        {
            var probe = it;
            _ = System.Threading.Tasks.Task.Run(() =>
            {
                bool ok = false;
                try
                {
                    using var c = new System.Net.Sockets.TcpClient();
                    var ar = c.BeginConnect("127.0.0.1", probe.Port, null, null);
                    ok = ar.AsyncWaitHandle.WaitOne(400) && c.Connected;
                    if (ok) c.EndConnect(ar);
                }
                catch { ok = false; }
                Dispatcher.Invoke(() =>
                {
                    probe.Status = ok ? "本机可达" : "未转发";
                    PortList.ItemsSource = null;
                    PortList.ItemsSource = items;
                });
            });
        }
    }

    private static void OpenUrl(int port)
    {
        try { Process.Start(new ProcessStartInfo("http://localhost:" + port) { UseShellExecute = true }); }
        catch { }
    }

    private void OpenBtn_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is int p) OpenUrl(p);
    }

    private void PortList_MouseDoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (PortList.SelectedItem is PortItem it) OpenUrl(it.Port);
    }

    private async void RefreshBtn_Click(object sender, RoutedEventArgs e) => await Reload();
    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
