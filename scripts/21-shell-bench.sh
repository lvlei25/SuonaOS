#!/usr/bin/env bash
# ============================================================================
# 21-shell-bench.sh - 桌面流畅度测量（只读）
#
# 为什么单独一个脚本：99-verify 只能回答「配置对不对」，回答不了「顺不顺」。
# 本脚本把「顺不顺」变成可重复的数字：同一台机器、同一组场景、同一套采样项，
# 改动前后各跑一次，用 --compare 给出劣化百分比。
#
# 采样项（1 Hz）：
#   gnome-shell CPU%（时间片差值）、RSS、GPU 占用（amdgpu gpu_busy_percent）、
#   CPU 平均频率、1 分钟负载、journal 里的掉帧线索计数
#
# 有效性判据（ISSUE-01 教训）：
#   测量窗口内 CPU 平均频率低于上限 50% → 判「测量无效」，先断电复位再测，
#   否则会把 EC/SMU 锁频当成「桌面变卡」。
#
# 场景：
#   --idle            静置基线（默认 20s，无需交互，可随时跑）
#   --manual          人工场景（终端里按提示做固定动作，脚本只负责采样）
#   --compare <dir>   与既有结果对比，输出劣化百分比（>10% 视为可疑）
#
# 用法:
#   ./scripts/21-shell-bench.sh                      # 静置 20s
#   ./scripts/21-shell-bench.sh --duration 40        # 静置 40s
#   ./scripts/21-shell-bench.sh --manual             # 概览/工作区/快捷设置/滚动
#   ./scripts/21-shell-bench.sh --compare logs/shell-bench-20261115-101500
#   ./scripts/21-shell-bench.sh --json               # 机器可读摘要
#
# 只读：不写系统配置，只写 logs/ 与 backup/ 之外的项目目录。
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ACTION="idle"
DUR=20
COMPARE_DIR=""
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --idle)     ACTION="idle" ;;
    --manual)   ACTION="manual" ;;
    --duration) DUR="${2:-20}"; shift ;;
    --compare)  COMPARE_DIR="${2:-}"; ACTION="compare"; shift ;;
    --json)     JSON=1 ;;
    -h|--help)  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

case "$DUR" in ''|*[!0-9]*) die "--duration 必须是整数秒，收到: $DUR" ;; esac
[ "$DUR" -ge 5 ] || die "--duration 至少 5 秒（太短无法区分噪声）"

OUT_DIR="$LOG_DIR/shell-bench-$RUN_ID"
SHELL_PID="$(pgrep -x gnome-shell | head -1)"
HZ="$(clock_ticks)"

# ---- 对比模式 ---------------------------------------------------------------
read_metric() { # read_metric <dir> <key>
  awk -F'\t' -v k="$2" '$1==k {print $2; exit}' "$1/metrics.tsv" 2>/dev/null
}

if [ "$ACTION" = "compare" ]; then
  [ -d "$COMPARE_DIR" ] || die "--compare 目录不存在: $COMPARE_DIR"
  [ -f "$COMPARE_DIR/metrics.tsv" ] || die "该目录没有 metrics.tsv: $COMPARE_DIR"
  LATEST="$(ls -dt "$LOG_DIR"/shell-bench-* 2>/dev/null | head -1)"
  [ -n "$LATEST" ] && [ "$LATEST" != "$COMPARE_DIR" ] || LATEST="$COMPARE_DIR"
  echo
  echo "════════ 流畅度对比 ════════"
  printf '  基线: %s\n  复测: %s\n\n' "${COMPARE_DIR#$PROJECT_ROOT/}" "${LATEST#$PROJECT_ROOT/}"
  printf '  %-22s %12s %12s %10s %s\n' 指标 基线 复测 变化 判定
  BAD=0
  for k in shell_cpu_pct shell_rss_kb gpu_busy_avg cpu_freq_avg_mhz load1_avg; do
    B=$(read_metric "$COMPARE_DIR" "$k")
    A=$(read_metric "$LATEST" "$k")
    [ -n "$B" ] && [ -n "$A" ] || continue
    awk -v b="$B" -v a="$A" -v k="$k" -v bad="$BAD" 'BEGIN{
      if (b==0) { printf "  %-22s %12.2f %12.2f %9s %s\n", k, b, a, "-", "基线为 0，跳过"; exit }
      d=(a-b)/b*100;
      verdict=(d>10)?"劣化 >10%":((d<-10)?"改善 >10%":"在噪声内");
      printf "  %-22s %12.2f %12.2f %9.1f%% %s\n", k, b, a, d, verdict;
    }'
    # 用返回值判断劣化（awk 无法回传，这里用独立计算）
    REG=$(awk -v b="$B" -v a="$A" 'BEGIN{exit !(b>0 && (a-b)/b*100 > 10)}' && echo 1 || echo 0)
    [ "$REG" = "1" ] && BAD=$((BAD+1))
  done
  echo
  if [ "$BAD" -gt 0 ]; then
    warn "有 $BAD 项劣化超过 10%：先确认本次测量 freq 是否正常（见两份 metrics.tsv 的 cpu_freq_avg_mhz）"
    exit 1
  fi
  ok "各项变化均在 10% 噪声范围内"
  exit 0
fi

[ -n "$SHELL_PID" ] || die "找不到 gnome-shell 进程，无法测量（确认在图形会话内执行）"

mkdir -p "$OUT_DIR"
SAMPLE="$OUT_DIR/samples.tsv"
printf 't\tcpu_ticks\trss_kb\tgpu_busy\tfreq_mhz\tload1\n' >"$SAMPLE"

MAX_FREQ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 0)"

gpu_busy_now() {
  local v
  for f in /sys/class/drm/card*/device/gpu_busy_percent; do
    [ -r "$f" ] || continue
    v="$(cat "$f" 2>/dev/null)" || continue
    printf '%s' "$v"; return 0
  done
  printf 'NA'
}

freq_now() {
  local sum=0 n=0 v
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
    [ -r "$f" ] || continue
    v="$(cat "$f" 2>/dev/null)" || continue
    sum=$((sum + v)); n=$((n + 1))
  done
  [ "$n" -gt 0 ] && printf '%s' $((sum / n / 1000)) || printf '0'
}

rss_now() { awk '/^VmRSS:/ {print $2}' "/proc/$SHELL_PID/status" 2>/dev/null || echo 0; }

# 显示器缩放不在 gsettings 里，只存在于 GNOME 的 monitors.xml；
# 不同缩放比例渲染像素量不同，跨缩放对比无意义，因此必须记录。
monitor_scale() {
  local f="$HOME/.config/monitors.xml"
  [ -f "$f" ] || { printf 'unknown'; return; }
  grep -o '<scale>[0-9.]*</scale>' "$f" 2>/dev/null | head -1 | sed 's/<[^>]*>//g'
}

FRAME_HINT=0
if have journalctl; then
  FRAME_HINT=$(journalctl --user -b --since "-10 min" --no-pager -o cat 2>/dev/null \
    | grep -ciE 'dropped frame|frame.*(skip|drop)|deadline missed' || true)
fi
: "${FRAME_HINT:=0}"

if [ "$ACTION" = "manual" ]; then
  [ -t 0 ] || die "--manual 需要交互终端"
  cat <<'EOF'

──────── 人工场景（脚本只采样，动作由你完成）────────
  1. 连续开关「概览」10 次（Super 键开、Esc 关）
  2. 依次切到工作区 2 / 3 / 4，再切回 1，共 5 次往返
  3. 展开、收起快捷设置（右上角状态区）5 次
  4. 在「文件」里滚动一个长列表 10 秒
  5. 打开、关闭一个窗口 5 次
────────────────────────────────────────────────
EOF
  printf '准备好后按回车开始 %s 秒采样...' "$DUR"
  read -r _
fi

step "采样 ${DUR}s（1 Hz，gnome-shell pid=$SHELL_PID）"
T0=$(date +%s)
LAST_TICKS="$(proc_cpu_ticks "$SHELL_PID")"
i=0
while [ "$i" -lt "$DUR" ]; do
  sleep 1
  i=$((i + 1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$i" "$(proc_cpu_ticks "$SHELL_PID")" "$(rss_now)" "$(gpu_busy_now)" "$(freq_now)" \
    "$(awk '{print $1}' /proc/loadavg)" >>"$SAMPLE"
done
T1=$(date +%s)
ELAPSED=$((T1 - T0))
[ "$ELAPSED" -ge 1 ] || ELAPSED=1

# ---- 汇总 -------------------------------------------------------------------
FIRST_TICKS="$(awk 'NR==2{print $2}' "$SAMPLE")"
LAST_TICKS="$(tail -1 "$SAMPLE" | cut -f2)"
CPU_PCT=$(awk -v a="$FIRST_TICKS" -v b="$LAST_TICKS" -v hz="$HZ" -v e="$ELAPSED" \
  'BEGIN{printf "%.2f", (b-a)/hz/e*100}')

GPU_AVG=$(awk -F'\t' 'NR>1 && $4!="NA"{s+=$4;n++} END{if(n)printf "%.1f", s/n; else print "NA"}' "$SAMPLE")
GPU_MAX=$(awk -F'\t' 'NR>1 && $4!="NA"{if($4>m)m=$4} END{if(m!="")print m; else print "NA"}' "$SAMPLE")
RSS_AVG=$(awk -F'\t' 'NR>1{s+=$3;n++} END{if(n)printf "%.0f", s/n; else print 0}' "$SAMPLE")
FREQ_AVG=$(awk -F'\t' 'NR>1{s+=$5;n++} END{if(n)printf "%.0f", s/n; else print 0}' "$SAMPLE")
FREQ_MIN=$(awk -F'\t' 'NR>1{if(m==""||$5<m)m=$5} END{print (m==""?0:m)}' "$SAMPLE")
LOAD_AVG=$(awk -F'\t' 'NR>1{s+=$6;n++} END{if(n)printf "%.2f", s/n; else print 0}' "$SAMPLE")

# 有效性：频率不足上限一半 → 数据不可用
VALID="yes"
MAX_MHZ=$((MAX_FREQ / 1000))
if [ "$MAX_MHZ" -gt 0 ]; then
  awk -v f="$FREQ_AVG" -v m="$MAX_MHZ" 'BEGIN{exit !(f < m*0.5)}' && VALID="no"
fi

{
  printf 'scenario\t%s\n' "$ACTION"
  printf 'duration_s\t%s\n' "$ELAPSED"
  printf 'shell_cpu_pct\t%s\n' "$CPU_PCT"
  printf 'shell_rss_kb\t%s\n' "$RSS_AVG"
  printf 'gpu_busy_avg\t%s\n' "$GPU_AVG"
  printf 'gpu_busy_max\t%s\n' "$GPU_MAX"
  printf 'cpu_freq_avg_mhz\t%s\n' "$FREQ_AVG"
  printf 'cpu_freq_min_mhz\t%s\n' "$FREQ_MIN"
  printf 'cpu_freq_max_mhz\t%s\n' "$MAX_MHZ"
  printf 'load1_avg\t%s\n' "$LOAD_AVG"
  printf 'frame_drop_hint_10min\t%s\n' "$FRAME_HINT"
  printf 'valid\t%s\n' "$VALID"
  printf 'text_scaling\t%s\n' "$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null | tr -d "'")"
  printf 'monitor_scale\t%s\n' "$(monitor_scale)"
  printf 'shell_theme\t%s\n' "$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | tr -d "'")"
  printf 'blur_enabled\t%s\n' "$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -c blur-my-shell)"
  printf 'kernel\t%s\n' "$(uname -r)"
} >"$OUT_DIR/metrics.tsv"

if [ "$JSON" -eq 1 ]; then
  printf '{'
  awk -F'\t' 'BEGIN{first=1} {if(!first)printf ","; printf "\"%s\":\"%s\"", $1, $2; first=0}' "$OUT_DIR/metrics.tsv"
  printf '}\n'
else
  echo
  echo "════════ 流畅度采样结果 ════════"
  printf '  场景        : %s（%ss）\n' "$ACTION" "$ELAPSED"
  printf '  shell CPU   : %s%%\n' "$CPU_PCT"
  printf '  shell RSS   : %s KB\n' "$RSS_AVG"
  printf '  GPU 占用    : 均值 %s%% / 峰值 %s%%（本机静置虚高，仅看趋势）\n' "$GPU_AVG" "$GPU_MAX"
  printf '  CPU 频率    : 均值 %s MHz（最低 %s / 上限 %s）\n' "$FREQ_AVG" "$FREQ_MIN" "$MAX_MHZ"
  printf '  1 分钟负载  : %s\n' "$LOAD_AVG"
  printf '  掉帧线索    : 近 10 分钟 journal 命中 %s 次\n' "$FRAME_HINT"
  printf '  显示缩放    : %s（文字缩放 %s）\n' "$(monitor_scale)" \
    "$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null | tr -d "'")"
  echo
  if [ "$VALID" = "no" ]; then
    warn "测量无效：平均频率 ${FREQ_AVG}MHz 低于上限的 50%（${MAX_MHZ}MHz）"
    warn "先完整断电复位（EC/SMU），再重测；不要把锁频当成桌面变卡（ISSUE-01）"
  else
    ok "测量有效，可作为基线：${OUT_DIR#$PROJECT_ROOT/}"
  fi
  log "细粒度采样: ${SAMPLE#$PROJECT_ROOT/}"
  log "改完一项后: $0 --compare ${OUT_DIR#$PROJECT_ROOT/}"
fi

[ "$VALID" = "no" ] && exit 2
exit 0
