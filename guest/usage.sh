#!/bin/bash
# 轻量实时用量：内存（KB）+ 进程数
awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%d %d\n", t, a}' /proc/meminfo
ls /proc | grep -c '^[0-9]'
