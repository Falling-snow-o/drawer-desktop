#!/bin/bash
. /etc/os-release 2>/dev/null
echo "os=$PRETTY_NAME"
echo "os_id=$ID"
echo "os_ver=$VERSION_ID"
echo "kernel=$(uname -r)"
echo "arch=$(uname -m)"
echo "cpu=$(nproc)"
echo "mem_total=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
echo "pkgs=$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l)"
echo "mirror=$(grep -h "^URIs:" /etc/apt/sources.list.d/*.sources 2>/dev/null | head -1 | sed "s/URIs: //")"
if command -v Xephyr >/dev/null 2>&1 && command -v xfwm4 >/dev/null 2>&1; then echo "desktop=yes"; else echo "desktop=no"; fi
if command -v picom >/dev/null 2>&1; then echo "compositor=yes"; else echo "compositor=no"; fi
echo "work=$(findmnt -n -o SOURCE /work 2>/dev/null | head -c 80)"
