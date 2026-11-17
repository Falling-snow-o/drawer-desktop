using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BoxRun;

public sealed class OnboardingWindow : Window
{
    public OnboardingWindow()
    {
        Title = "开始使用";
        Width = 560;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Background = new SolidColorBrush(Color.FromRgb(0xF2, 0xF2, 0xF7));

        var panel = new StackPanel { Margin = new Thickness(28) };
        panel.Children.Add(new TextBlock
        {
            Text = "欢迎使用 Drawer",
            FontSize = 24,
            FontWeight = FontWeights.Bold,
            Margin = new Thickness(0, 0, 0, 6)
        });
        panel.Children.Add(new TextBlock
        {
            Text = "一个抽屉 = 一台便携 Linux。三步就能跑起来：",
            FontSize = 13,
            Foreground = new SolidColorBrush(Color.FromRgb(0x86, 0x86, 0x8B)),
            Margin = new Thickness(0, 0, 0, 16)
        });

        void Step(string n, string title, string desc)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 14) };
            row.Children.Add(new Border
            {
                Width = 26,
                Height = 26,
                CornerRadius = new CornerRadius(13),
                Background = new SolidColorBrush(Color.FromRgb(0x00, 0x71, 0xE3)),
                Child = new TextBlock
                {
                    Text = n,
                    Foreground = Brushes.White,
                    FontSize = 12,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                }
            });
            var tx = new StackPanel { Margin = new Thickness(12, 0, 0, 0) };
            tx.Children.Add(new TextBlock { Text = title, FontSize = 14, FontWeight = FontWeights.SemiBold });
            tx.Children.Add(new TextBlock
            {
                Text = desc,
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(0x86, 0x86, 0x8B)),
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = 440
            });
            row.Children.Add(tx);
            panel.Children.Add(row);
        }

        Step("1", "新建抽屉", "点「添加」选一个空目录，或在「查找」里导入已有抽屉目录。");
        Step("2", "构建", "首次点「启动」会自动构建（下载 rootfs + 预装包）。用基础镜像时约 10–20 秒。");
        Step("3", "使用", "启动后可用终端、桌面、端口面板；关窗口不会删除，删目录才是卸载。");

        panel.Children.Add(new TextBlock
        {
            Text = "数据位置：抽屉目录下的 data/ 和 downloads/，还原快照不会动它们。",
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(0xA1, 0xA1, 0xA6)),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 4, 0, 0)
        });

        var ok = new Button
        {
            Content = "开始使用",
            HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Thickness(20, 8, 20, 8),
            Margin = new Thickness(0, 18, 0, 0),
            Background = new SolidColorBrush(Color.FromRgb(0x00, 0x71, 0xE3)),
            Foreground = Brushes.White,
            BorderThickness = new Thickness(0)
        };
        ok.Click += (_, _) => Close();
        panel.Children.Add(ok);

        Content = panel;
    }
}
