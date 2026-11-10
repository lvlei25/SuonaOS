#!/usr/bin/env bash
# ============================================================================
# bench.sh - 系统性能快照（用于优化前后对比）
# 纯用户态基准，不受主题/字体/输入法/配置影响
# 用法: ./scripts/bench.sh
# ============================================================================
set -o pipefail

printf '%-22s %s\n' "时间" "$(date '+%F %T')"
printf '%-22s %s\n' "内核" "$(uname -r)"

# ---- CPU 频率 --------------------------------------------------------------
FREQS=$(for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do cat "$f"; done 2>/dev/null)
if [ -n "$FREQS" ]; then
  AVG=$(echo "$FREQS" | awk '{s+=$1; n++} END {printf "%.0f", s/n/1000}')
  MAXF=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
  printf '%-22s %s MHz (上限 %s MHz)\n' "当前频率均值" "$AVG" "$((${MAXF:-0}/1000))"
fi
printf '%-22s %s\n' "governor" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
printf '%-22s %s\n' "platform_profile" "$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"

# ---- 基准 1：纯 CPU 整数运算 ----------------------------------------------
T1=$( { /usr/bin/time -f '%e' python3 -c "sum(range(10**7))" ; } 2>&1 | tail -1 )
printf '%-22s %s 秒   (正常约 0.4s, 越大越慢)\n' "python 求和 1e7" "$T1"

# ---- 基准 2：sha256 吞吐 ---------------------------------------------------
S=$(date +%s%N)
dd if=/dev/zero bs=1M count=256 2>/dev/null | sha256sum >/dev/null
E=$(date +%s%N)
MS=$(( (E-S)/1000000 ))
[ "$MS" -gt 0 ] && printf '%-22s %s MB/s  (正常 1000+ MB/s)\n' "sha256" "$((256*1000/MS))"

# ---- 基准 3：磁盘读 --------------------------------------------------------
if [ -w /tmp ] && command -v dd >/dev/null; then
  S=$(date +%s%N)
  dd if=/dev/zero of=/tmp/.bench bs=1M count=512 conv=fsync 2>/dev/null
  E=$(date +%s%N)
  rm -f /tmp/.bench
  MS=$(( (E-S)/1000000 ))
  [ "$MS" -gt 0 ] && printf '%-22s %s MB/s\n' "磁盘写" "$((512*1000/MS))"
fi

printf '%-22s %s\n' "内存" "$(free -h | awk '/^内存|^Mem/{print $3"/"$2}')"
printf '%-22s %s\n' "负载" "$(cut -d' ' -f1-3 /proc/loadavg)"
