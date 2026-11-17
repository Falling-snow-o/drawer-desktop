using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace BoxRun;

public sealed class BoxItem
{
    public string Name { get; set; }
    public string Alias { get; set; }
    public string DisplayName => string.IsNullOrEmpty(Alias) ? Name : Alias;
    public string Tag { get; set; }
    public string TagText => string.IsNullOrEmpty(Tag) ? "" : Tag;
    public Visibility TagVis => string.IsNullOrEmpty(Tag) ? Visibility.Collapsed : Visibility.Visible;
    public string TagGroup => string.IsNullOrEmpty(Tag) ? "未分组" : Tag;
}

public static class BoxMeta
{
    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".boxrun");

    private static Dictionary<string, string> _tags = new();
    private static Dictionary<string, string> _aliases = new();
    private static DateTime _stamp = DateTime.MinValue;

    public static void Reload(bool force = false)
    {
        try
        {
            var tf = Path.Combine(Dir, "tags.json");
            var af = Path.Combine(Dir, "aliases.json");
            var stamp = Max(File.GetLastWriteTimeUtc(tf), File.GetLastWriteTimeUtc(af));
            if (!force && stamp == _stamp) return;
            _tags = Read(tf);
            _aliases = Read(af);
            _stamp = stamp;
        }
        catch { }
    }

    private static DateTime Max(DateTime a, DateTime b) => a > b ? a : b;

    private static Dictionary<string, string> Read(string file)
    {
        try
        {
            if (!File.Exists(file)) return new Dictionary<string, string>();
            return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(file))
                   ?? new Dictionary<string, string>();
        }
        catch { return new Dictionary<string, string>(); }
    }

    private static bool Write(string file, Dictionary<string, string> map)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(file, JsonSerializer.Serialize(map));
            _stamp = DateTime.MinValue;   // 下次 Reload 重新读
            return true;
        }
        catch { return false; }
    }

    public static string TagOf(string name)
    {
        Reload();
        return _tags.TryGetValue(name, out var v) ? v : "";
    }

    public static string AliasOf(string name)
    {
        Reload();
        return _aliases.TryGetValue(name, out var v) ? v : "";
    }

    public static string DisplayOf(string name)
    {
        var a = AliasOf(name);
        return string.IsNullOrEmpty(a) ? name : a;
    }

    public static bool SetTag(string name, string value)
    {
        Reload();
        if (string.IsNullOrEmpty(value)) _tags.Remove(name);
        else _tags[name] = value;
        return Write(Path.Combine(Dir, "tags.json"), _tags);
    }

    public static bool SetAlias(string name, string value)
    {
        Reload();
        if (string.IsNullOrEmpty(value) || value == name) _aliases.Remove(name);
        else _aliases[name] = value;
        return Write(Path.Combine(Dir, "aliases.json"), _aliases);
    }
}
