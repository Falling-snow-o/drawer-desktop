#!/bin/bash
# 进入 cgroup 后 exec —— 由 boxrun 注入
CG=/sys/fs/cgroup/boxrun
# 发行版重启后 cgroup 会消失，这里按配置自愈一次
if [ ! -d "$CG" ] && [ -f /etc/boxrun/quota.env ]; then
    . /etc/boxrun/quota.env
    /usr/local/bin/boxrun-quota >/dev/null 2>&1 || true
fi
if [ -w "$CG/cgroup.procs" ]; then
    echo $$ > "$CG/cgroup.procs" 2>/dev/null || true
fi
# 抽屉可能刚被自动回收，mount 会丢；这里幂等补挂一次
/usr/local/bin/boxrun-work >/dev/null 2>&1 || true
/usr/local/bin/boxrun-quota --all >/dev/null 2>&1 || true
# 显存闸（gpu.vram > 0 时才有这个文件）
if [ -f /etc/boxrun/vram.env ]; then . /etc/boxrun/vram.env; fi
exec "$@"
