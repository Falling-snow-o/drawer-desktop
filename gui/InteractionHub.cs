using System;

namespace BoxRun;

/// <summary>
/// 全局交互总线：主窗口发布“忙碌 / 动作完成 / 抽屉列表变化”，
/// 各功能窗口订阅后统一刷新，避免各自为政。
/// </summary>
public static class InteractionHub
{
    public static event Action<bool> BusyChanged;
    public static event Action<string> ActionCompleted;
    public static event Action BoxesChanged;

    public static bool IsBusy { get; private set; }

    public static void SetBusy(bool busy)
    {
        IsBusy = busy;
        try { BusyChanged?.Invoke(busy); } catch { }
    }

    public static void NotifyAction(string verb)
    {
        try { ActionCompleted?.Invoke(verb); } catch { }
    }

    public static void NotifyBoxes()
    {
        try { BoxesChanged?.Invoke(); } catch { }
    }
}
