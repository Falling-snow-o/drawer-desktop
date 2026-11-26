#!/bin/bash
# 在 WSLg 的 :0 上开一个嵌套 X 服务器，整个桌面画进一个窗口
# 显示号按抽屉名算，避免多个抽屉共用 :1 互相冲突（抽象 socket 是共享的）
unset WAYLAND_DISPLAY
export DISPLAY=:0

NAME=$(cat /etc/boxrun/boxname 2>/dev/null || hostname)
NUM=$(( 10 + $(printf '%s' "$NAME" | cksum | awk '{print $1}') % 80 ))
XNUM=":$NUM"
[ -s /etc/boxrun/desktop.res ] && BOXRUN_DESKTOP_RES=$(cat /etc/boxrun/desktop.res)

# WSLg 音频：把 PulseServer 指给箱内程序
if [ -S /mnt/wslg/PulseServer ]; then
    export PULSE_SERVER=unix:/mnt/wslg/PulseServer
fi

# 加入配额 cgroup：桌面进程也受内存/CPU/进程数上限约束
if [ -d /sys/fs/cgroup/boxrun ]; then
    echo $$ > /sys/fs/cgroup/boxrun/cgroup.procs 2>/dev/null || true
fi

for p in Xephyr xfwm4 xfce4-panel xfdesktop xfce4-session xfsettingsd Thunar picom boxrun-clip; do
    pkill -f "$p" 2>/dev/null
done
sleep 1
rm -f "/tmp/.X${NUM}-lock" "/tmp/.X11-unix/X${NUM}" 2>/dev/null

setsid Xephyr "$XNUM" -screen "${BOXRUN_DESKTOP_RES:-1600x1000}" -resizeable -ac -noreset -nolisten tcp -title "boxrun desktop" >/tmp/boxrun-xephyr.log 2>&1 < /dev/null &
sleep 2
# Xephyr 有时会被上一轮残留的抽象 socket 挡住，重试一次
if ! pgrep -x Xephyr >/dev/null 2>&1; then
    sleep 2
    rm -f "/tmp/.X${NUM}-lock" "/tmp/.X11-unix/X${NUM}" 2>/dev/null
setsid Xephyr "$XNUM" -screen "${BOXRUN_DESKTOP_RES:-1600x1000}" -resizeable -ac -noreset -nolisten tcp -title "boxrun desktop" >/tmp/boxrun-xephyr.log 2>&1 < /dev/null &
    sleep 2
fi
sleep 2

# 等 X server 真正可用再起窗口管理器（冷启动时 2 秒不够）
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -S "/tmp/.X11-unix/X${NUM}" ] && break
    sleep 0.5
done
for i in 1 2 3 4 5 6 7 8 9 10; do
    DISPLAY="$XNUM" xdpyinfo >/dev/null 2>&1 && break
    sleep 0.5
done

export DISPLAY="$XNUM"
setsid dbus-run-session -- xfwm4 --compositor=off >/tmp/boxrun-xfwm4.log 2>&1 < /dev/null &
sleep 2

# 关掉屏保和 DPMS：否则桌面闲置一段时间会黑屏
# Xephyr 刚起来时 X socket 可能还没就绪，重试到成功为止
for i in 1 2 3 4 5 6 7 8 9 10; do
    xset s off >/dev/null 2>&1 && break
    sleep 1
done
xset -dpms >/dev/null 2>&1 || true
xset s noblank >/dev/null 2>&1 || true

# 设置守护和面板先起，配置好主题/壁纸后再起桌面图标
setsid dbus-run-session -- bash -c "unset WAYLAND_DISPLAY; export DISPLAY=$XNUM GDK_BACKEND=x11; xfsettingsd & xfce4-panel & sleep infinity" >/tmp/boxrun-xfce.log 2>&1 < /dev/null &
sleep 2

xfconf-query -c xsettings -p /Net/ThemeName -s Arc-Dark >/dev/null 2>&1 || true
xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus-Dark >/dev/null 2>&1 || true

if [ -f /work/boxrun-wall.png ]; then
    mkdir -p /usr/share/backgrounds
    cp /work/boxrun-wall.png /usr/share/backgrounds/boxrun-wall.png 2>/dev/null
    for p in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep last-image); do
        xfconf-query -c xfce4-desktop -p "$p" -s /usr/share/backgrounds/boxrun-wall.png >/dev/null 2>&1 || true
    done
fi

for p in $(xfconf-query -c xfce4-panel -l 2>/dev/null | grep background-alpha); do
    xfconf-query -c xfce4-panel -p "$p" -s 80 >/dev/null 2>&1 || true
done

setsid dbus-run-session -- bash -c "unset WAYLAND_DISPLAY; export DISPLAY=$XNUM GDK_BACKEND=x11; xfdesktop & sleep infinity" >/tmp/boxrun-xfdesk.log 2>&1 < /dev/null &
sleep 1
sleep 2


# 剪贴板桥：与 Windows 侧通过 /work 下的两个文件交换（daemon 常驻，避免 xclip 被会话回收）
if [ -d /work ]; then
    setsid bash -c "
        export DISPLAY=$XNUM
        F=/work/.boxrun-clip
        last=\"\"
        while true; do
            cur=\$(xclip -selection clipboard -o 2>/dev/null)
            if [ \"\$cur\" != \"\$last\" ]; then printf \"%s\" \"\$cur\" > \"\$F.linux\"; last=\"\$cur\"; fi
            if [ -f \"\$F.win\" ]; then
                w=\$(cat \"\$F.win\" 2>/dev/null)
                if [ -n \"\$w\" ] && [ \"\$w\" != \"\$last\" ]; then printf \"%s\" \"\$w\" | xclip -selection clipboard; last=\"\$w\"; fi
            fi
            sleep 0.3
        done" >/tmp/boxrun-clipd.log 2>&1 &
fi

echo "display=$XNUM xfwm4=$(pgrep -c xfwm4) panel=$(pgrep -c xfce4-panel) desktop=$(pgrep -c xfdesktop)"
DISPLAY=:0 xwininfo -root -tree 2>/dev/null | grep -c "boxrun desktop" | sed 's/^/window=/'
