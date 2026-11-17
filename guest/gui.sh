#!/bin/bash
# 在 Windows 桌面开一个图形窗口 —— 由 boxrun 注入
# 用法: boxrun-gui <命令> [参数...]
# 进程在抽屉里跑，窗口由 WSLg（Weston + RDP）画到宿主桌面，不需要装桌面环境
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
LOG=/tmp/boxrun-gui.log
: > "$LOG"
if ! command -v "$1" >/dev/null 2>&1 && [ ! -x "$1" ]; then
    echo "找不到程序: $1"
    exit 127
fi
# setsid：脱离当前会话，wsl.exe 退出后进程还能活（只 nohup 对 pcmanfm 这类不够）
setsid "$@" </dev/null >>"$LOG" 2>&1 &
sleep 1
if grep -qiE 'cannot open display|failed to execute|No such file or directory' "$LOG" 2>/dev/null; then
    echo "启动失败，日志："
    tail -n 20 "$LOG"
    exit 1
fi
echo "已启动（独立会话）—— 窗口应出现在 Windows 桌面"
exit 0
