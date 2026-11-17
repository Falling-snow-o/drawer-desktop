using System;

namespace BoxRun;

/// <summary>引擎输出里可能混着日志行，这里统一取中间的 JSON 片段。</summary>
public static class JsonUtil
{
    public static string Object(string raw, string fallback = "{}")
    {
        if (string.IsNullOrEmpty(raw)) return fallback;
        int a = raw.IndexOf('{'), b = raw.LastIndexOf('}');
        return a >= 0 && b > a ? raw.Substring(a, b - a + 1) : fallback;
    }

    public static string Array(string raw, string fallback = "[]")
    {
        if (string.IsNullOrEmpty(raw)) return fallback;
        int a = raw.IndexOf('['), b = raw.LastIndexOf(']');
        return a >= 0 && b > a ? raw.Substring(a, b - a + 1) : fallback;
    }
}
