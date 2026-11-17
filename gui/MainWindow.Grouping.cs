using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows.Controls;

namespace BoxRun;

public partial class MainWindow
{
    private readonly List<BoxItem> _items = new();
    private ICollectionView _view;

    private void PopulateList(List<string> names, string keep)
    {
        BoxMeta.Reload();
        _items.Clear();
        foreach (var n in names)
            _items.Add(new BoxItem { Name = n, Alias = BoxMeta.AliasOf(n), Tag = BoxMeta.TagOf(n) });

        if (_view == null)
        {
            _view = System.Windows.Data.CollectionViewSource.GetDefaultView(_items);
            _view.GroupDescriptions.Add(new System.Windows.Data.PropertyGroupDescription(nameof(BoxItem.TagGroup)));
            BoxList.ItemsSource = _view;
            BuildTagFilter();
        }

        _view.Filter = o =>
        {
            if (o is not BoxItem it) return false;
            var f = TagFilter?.SelectedItem as string;
            if (string.IsNullOrEmpty(f) || f == "全部分组") return true;
            return it.TagGroup == f;
        };
        _view.Refresh();

        if (keep != null && names.Contains(keep))
            BoxList.SelectedItem = _items.FirstOrDefault(x => x.Name == keep);
        else if (names.Count > 0)
            BoxList.SelectedIndex = 0;
        else
            ClearStatus();

    }

    private void BuildTagFilter()
    {
        if (TagFilter == null) return;
        var cur = TagFilter.SelectedItem as string;
        TagFilter.Items.Clear();
        TagFilter.Items.Add("全部分组");
        foreach (var g in _items.Select(x => x.TagGroup).Distinct().OrderBy(x => x))
            TagFilter.Items.Add(g);
        TagFilter.SelectedItem = cur != null && TagFilter.Items.Contains(cur) ? cur : "全部分组";
    }

    private void TagFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _view?.Refresh();
    }
}
