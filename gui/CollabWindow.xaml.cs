using System;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;

namespace BoxRun;

public partial class CollabWindow : Window
{
    private readonly string _box;
    private readonly Func<string[], Task<string>> _run;

    public CollabWindow(string box, Func<string[], Task<string>> run)
    {
        InitializeComponent();
        _box = box;
        _run = run;
        HeadText.Text = "协同 · " + box;
        Loaded += async (_, _) => await Do("status");
    }

    private async Task Do(params string[] tail)
    {
        var args = new[] { "collab", _box }.Concat(tail).ToArray();
        OutBox.Text += "\u25b8 " + string.Join(' ', args) + Environment.NewLine;
        try
        {
            var raw = await _run(args);
            OutBox.Text += raw.TrimEnd() + Environment.NewLine + Environment.NewLine;
        }
        catch (Exception ex)
        {
            OutBox.Text += "[失败] " + ex.Message + Environment.NewLine + Environment.NewLine;
        }
        OutBox.ScrollToEnd();
    }

    private async void InitBtn_Click(object sender, RoutedEventArgs e)
    {
        var remote = RemoteBox.Text.Trim();
        if (string.IsNullOrEmpty(remote))
        {
            MessageBox.Show(this, "先填远端地址（可以是本地裸仓库路径）", "协同");
            return;
        }
        await Do("init", remote);
    }

    private async void StatusBtn_Click(object sender, RoutedEventArgs e) => await Do("status");

    private async void SyncBtn_Click(object sender, RoutedEventArgs e)
        => await Do("sync", "-m", "drawer: 协同同步 " + DateTime.Now.ToString("yyyy-MM-dd HH:mm"));

    private async void MergeBtn_Click(object sender, RoutedEventArgs e)
    {
        var branch = RemoteBox.Text.Trim();
        if (string.IsNullOrEmpty(branch))
        {
            MessageBox.Show(this, "先填要合并的分支名（例如 master）", "协同");
            return;
        }
        await Do("merge", branch);
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
