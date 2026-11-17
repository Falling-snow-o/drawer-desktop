using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;

namespace BoxRun;

/// <summary>极简折线图：把 0..1 的采样画成一条曲线，用于内存/进程趋势。</summary>
public sealed class Sparkline : FrameworkElement
{
    private static readonly Brush LineBrush = Freeze(new SolidColorBrush(Color.FromRgb(0x00, 0x71, 0xE3)));
    private static readonly Brush FillBrush = Freeze(new SolidColorBrush(Color.FromArgb(0x22, 0x00, 0x71, 0xE3)));

    private readonly List<double> _values = new();

    public void Push(double v)
    {
        _values.Add(Math.Max(0, Math.Min(1, v)));
        if (_values.Count > 60) _values.RemoveAt(0);
        InvalidateVisual();
    }

    public void Clear()
    {
        _values.Clear();
        InvalidateVisual();
    }

    private static T Freeze<T>(T f) where T : Freezable { f.Freeze(); return f; }

    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight;
        if (w < 8 || h < 8 || _values.Count < 2) return;
        if (_values.Max() <= 0.001) return;

        var geo = new StreamGeometry();
        using (var g = geo.Open())
        {
            double step = w / Math.Max(1, _values.Count - 1);
            var first = new Point(0, h - _values[0] * (h - 4) - 2);
            g.BeginFigure(first, true, false);
            for (int i = 1; i < _values.Count; i++)
                g.LineTo(new Point(i * step, h - _values[i] * (h - 4) - 2), true, false);
            g.LineTo(new Point(w, h), false, false);
            g.LineTo(new Point(0, h), false, false);
        }
        geo.Freeze();
        dc.DrawGeometry(FillBrush, null, geo);

        var line = new StreamGeometry();
        using (var g = line.Open())
        {
            double step = w / Math.Max(1, _values.Count - 1);
            g.BeginFigure(new Point(0, h - _values[0] * (h - 4) - 2), false, false);
            for (int i = 1; i < _values.Count; i++)
                g.LineTo(new Point(i * step, h - _values[i] * (h - 4) - 2), true, false);
        }
        line.Freeze();
        var pen = new Pen(LineBrush, 1.6) { LineJoin = PenLineJoin.Round };
        pen.Freeze();
        dc.DrawGeometry(null, pen, line);
    }
}
