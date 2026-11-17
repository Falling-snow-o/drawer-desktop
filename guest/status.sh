#!/bin/bash
# 输出机器可读状态 —— 由 boxrun 注入
R=/sys/fs/cgroup
C=$R/boxrun
echo "kernel=$(uname -r)"
echo "uptime=$(cut -d. -f1 /proc/uptime)"
echo "nproc=$(nproc)"
echo "mem_total=$(awk '/MemTotal/{print $2*1024}' /proc/meminfo)"
echo "mem_avail=$(awk '/MemAvailable/{print $2*1024}' /proc/meminfo)"
echo "cg_mem_now=$(cat $C/memory.current 2>/dev/null || echo 0)"
echo "cg_mem_max=$(cat $C/memory.max     2>/dev/null || echo 0)"
echo "cg_cpu=$(cat $C/cpu.max            2>/dev/null || echo n/a)"
echo "cg_pids_now=$(cat $C/pids.current  2>/dev/null || echo 0)"
echo "cg_pids_max=$(cat $C/pids.max      2>/dev/null || echo 0)"
if [ -c /dev/dxg ]; then echo "gpu_dev=yes"; else echo "gpu_dev=no"; fi
if ls /usr/lib/wsl/lib/libcuda.so* >/dev/null 2>&1; then echo "cuda_lib=yes"; else echo "cuda_lib=no"; fi
if [ -d /sys/fs/cgroup/boxrun ]; then echo "cg_present=yes"; else echo "cg_present=no"; fi
T="$(cat /etc/boxrun/work.dst 2>/dev/null)"
[ -n "$T" ] || T=/work
if mountpoint -q "$T" 2>/dev/null; then echo "work_mount=yes"; else echo "work_mount=no"; fi
