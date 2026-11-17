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

    private string Remote => RemoteBox.Text.Trim();
    private string Branch => BranchBox.Text.Trim();
    private string Message => string.IsNullOrWhiteSpace(MsgBox.Text)
        ? "drawer: " + DateTime.Now.ToString("yyyy-MM-dd HH:mm")
        : MsgBox.Text.Trim();

    private async void InitBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Remote)) { MessageBox.Show(this, "先填远端地址", "协同"); return; }
        await Do("init", Remote);
    }

    private async void CloneBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Remote)) { MessageBox.Show(this, "先填远端地址", "协同"); return; }
        await Do("clone", Remote);
    }

    private async void RemoteBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Remote)) { await Do("remote"); return; }
        await Do("remote", Remote);
    }

    private async void NewBranchBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Branch)) { MessageBox.Show(this, "先填分支名", "协同"); return; }
        await Do("branch", "-c", Branch);
    }

    private async void SwitchBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Branch)) { MessageBox.Show(this, "先填分支名", "协同"); return; }
        await Do("branch", Branch);
    }

    private async void BranchListBtn_Click(object sender, RoutedEventArgs e) => await Do("branch");

    private async void CommitBtn_Click(object sender, RoutedEventArgs e) => await Do("commit", "-m", Message);

    private async void SyncBtn_Click(object sender, RoutedEventArgs e) => await Do("sync", "-m", Message);

    private async void StatusBtn_Click(object sender, RoutedEventArgs e) => await Do("status");

    private async void DiffBtn_Click(object sender, RoutedEventArgs e) => await Do("diff");

    private async void LogBtn_Click(object sender, RoutedEventArgs e) => await Do("log", "20");

    private async void FetchBtn_Click(object sender, RoutedEventArgs e) => await Do("fetch");

    private async void PullBtn_Click(object sender, RoutedEventArgs e) => await Do("pull");

    private async void PushBtn_Click(object sender, RoutedEventArgs e) => await Do("push");

    private async void StashBtn_Click(object sender, RoutedEventArgs e) => await Do("stash");

    private async void StashPopBtn_Click(object sender, RoutedEventArgs e) => await Do("stash", "pop");

    private async void TagBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Branch)) { MessageBox.Show(this, "在分支/标签输入框填标签名", "协同"); return; }
        await Do("tag", Branch);
    }

    private async void MergeBtn_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(Branch)) { MessageBox.Show(this, "在分支输入框填要合并的分支", "协同"); return; }
        await Do("merge", Branch);
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e) => Close();
}
