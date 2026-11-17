#!/bin/bash
# 应用 cgroup v2 配额 —— 由 boxrun 注入
R=/sys/fs/cgroup
C=$R/boxrun
on=""
for c in memory cpu pids; do
    if grep -qw "$c" "$R/cgroup.controllers" 2>/dev/null; then
        echo "+$c" > "$R/cgroup.subtree_control" 2>/dev/null && on="$on $c"
    fi
done
mkdir -p "$C"
[ -n "$BOXRUN_CPU"  ] && { echo "$BOXRUN_CPU"  > "$C/cpu.max"    2>/dev/null; }
[ -n "$BOXRUN_MEM"  ] && { echo "$BOXRUN_MEM"  > "$C/memory.max" 2>/dev/null; }
[ -n "$BOXRUN_PIDS" ] && { echo "$BOXRUN_PIDS" > "$C/pids.max"   2>/dev/null; }
# --all：把箱内所有进程都纳入配额（含 systemd 拉起的服务）
if [ "$1" = "--all" ]; then
    moved=0
    for p in /proc/[0-9]*; do
        pid=${p#/proc/}
        echo "$pid" > "$C/cgroup.procs" 2>/dev/null && moved=$((moved + 1))
    done
    echo "moved=$moved"
fi
echo "controllers:$on"
echo "cpu.max    = $(cat $C/cpu.max    2>/dev/null || echo n/a)"
echo "memory.max = $(cat $C/memory.max 2>/dev/null || echo n/a)"
echo "pids.max   = $(cat $C/pids.max   2>/dev/null || echo n/a)"
