#!/bin/bash
# 把 Windows 侧的 data/ 和 downloads/ 挂进抽屉 —— 由 boxrun 注入
S="$(cat /etc/boxrun/work.src 2>/dev/null)"
T="$(cat /etc/boxrun/work.dst 2>/dev/null)"; [ -n "$T" ] || T=/work
D="$(cat /etc/boxrun/dl.src 2>/dev/null)"
mount_dir() {
    src="$1"; dst="$2"
    [ -n "$src" ] || return 0
    mkdir -p "$dst" || return 1
    mountpoint -q "$dst" 2>/dev/null && { echo "已挂载: $dst"; return 0; }
    if mount -t drvfs "$src" "$dst" -o metadata,uid=0,gid=0,umask=022 2>/dev/null; then
        echo "挂载成功: $src -> $dst"; return 0
    fi
    echo "挂载失败: $src -> $dst"; return 1
}
[ -n "$S" ] || { echo "缺少 /etc/boxrun/work.src"; exit 2; }
mount_dir "$S" "$T" || exit 4
[ -n "$D" ] && mount_dir "$D" /downloads
exit 0
