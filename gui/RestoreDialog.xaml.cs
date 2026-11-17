using System;
using System.Windows;
using System.Windows.Threading;

namespace BoxRun;

public partial class RestoreDialog : Window
{
    public enum Choice { Cancel, Full, KeepGui }

    public Choice Result { get; private set; } = Choice.Cancel;

    public RestoreDialog(string box)
    {
        InitializeComponent();
        HeadText.Text = "恢复初始 " + box + "？";

        // 防误触：窗口刚出现时按钮全部禁用 450ms，并让取消获得焦点
        SetButtons(false);
        Loaded += (_, _) =>
        {
            CancelBtn.Focus();
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(450) };
            t.Tick += (_, _) => { t.Stop(); SetButtons(true); };
            t.Start();
        };
    }

    private void SetButtons(bool on)
    {
        FullBtn.IsEnabled = on;
        KeepBtn.IsEnabled = on;
    }

    private void FullBtn_Click(object sender, RoutedEventArgs e) { Result = Choice.Full; DialogResult = true; }
    private void KeepBtn_Click(object sender, RoutedEventArgs e) { Result = Choice.KeepGui; DialogResult = true; }
    private void CancelBtn_Click(object sender, RoutedEventArgs e) { Result = Choice.Cancel; DialogResult = false; }
}
