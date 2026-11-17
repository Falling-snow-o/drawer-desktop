using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace BoxRun;

/// <summary>统一的表单弹窗：标题 + 若干输入框 + 保存/取消。减少每个对话框重复布局。</summary>
public sealed class FormDialog : Window
{
    public TextBox[] Inputs { get; }
    public bool Accepted { get; private set; }

    public string this[int index] => Inputs.Length > index ? Inputs[index].Text.Trim() : "";

    internal FormDialog(string title, string heading, string okText, (string Label, string Value)[] fields)
    {
        Title = title;
        Width = 440;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Background = new SolidColorBrush(Color.FromRgb(0xF2, 0xF2, 0xF7));

        var panel = new StackPanel { Margin = new Thickness(20) };
        if (!string.IsNullOrEmpty(heading))
            panel.Children.Add(new TextBlock
            {
                Text = heading,
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 12)
            });

        Inputs = new TextBox[fields.Length];
        for (int i = 0; i < fields.Length; i++)
        {
            if (!string.IsNullOrEmpty(fields[i].Label))
                panel.Children.Add(new TextBlock
                {
                    Text = fields[i].Label,
                    Foreground = new SolidColorBrush(Color.FromRgb(0x86, 0x86, 0x8B)),
                    FontSize = 11,
                    Margin = new Thickness(0, i == 0 ? 0 : 10, 0, 4)
                });
            var box = new TextBox
            {
                Text = fields[i].Value ?? "",
                Height = 30,
                Margin = new Thickness(0, 0, 0, 4)
            };
            Inputs[i] = box;
            panel.Children.Add(box);
        }

        var btns = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        var ok = new Button { Content = okText, Padding = new Thickness(16, 6, 16, 6) };
        ok.Click += (_, _) => { Accepted = true; DialogResult = true; };
        var cancel = new Button
        {
            Content = "取消", Padding = new Thickness(16, 6, 16, 6),
            Margin = new Thickness(8, 0, 0, 0), IsCancel = true
        };
        btns.Children.Add(ok);
        btns.Children.Add(cancel);
        panel.Children.Add(btns);

        Content = panel;
        Loaded += (_, _) => { if (Inputs.Length > 0) { Inputs[0].Focus(); Inputs[0].SelectAll(); } };
    }
}

public static class DialogShell
{
    public static FormDialog Form(string title, string heading, string okText, params (string Label, string Value)[] fields)
        => new FormDialog(title, heading, okText, fields);

    public static FormDialog Prompt(string title, string heading, string value, string okText = "保存")
        => new FormDialog(title, heading, okText, new[] { ("", value ?? "") });
}
