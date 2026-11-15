#!/usr/bin/env bash
# ============================================================================
# 28-peripherals-power.sh - 外设矩阵 + 电池枚举抖动诊断 + 交付前电源门禁
#
# 三件事：
#   1) --status   一次性列出显示输出/扩展坞/打印扫描/蓝牙/电池，判断"外设齐不齐"
#   2) --battery  连续采样 BAT* 是否存在，量化抖动率（ISSUE-33）
#   3) --gate     交付门禁：要求电池在 N 分钟内连续存在，任何一次消失即失败
#
# 为什么单做电池抖动：ISSUE-33 里 BAT0 每 40 秒消失一次，顶栏电量随之消失。
#   _STA 由 EC 提供，软件层改不了；能做的只有"测出来 + 按流程处置 + 交付前拦住"。
#
# 用法:
#   ./scripts/28-peripherals-power.sh --status
#   ./scripts/28-peripherals-power.sh --battery 60        # 采样 60 秒
#   ./scripts/28-peripherals-power.sh --gate --minutes 5  # 交付门禁
#   ./scripts/28-peripherals-power.sh --audit             # 结果落盘
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ACTION="status"
SECS=60
MINUTES=5
AUDIT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --status)  ACTION=status ;;
    --battery) ACTION=battery; SECS="${2:-60}"; shift ;;
    --gate)    ACTION=gate ;;
    --minutes) MINUTES="${2:-5}"; shift ;;
    --audit)   AUDIT=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

case "$SECS" in ''|*[!0-9]*) die "--battery 需要整数秒" ;; esac
case "$MINUTES" in ''|*[!0-9]*) die "--minutes 需要整数分钟" ;; esac

have_sudo() { sudo -n true 2>/dev/null; }

# ---- 电池采样 ---------------------------------------------------------------
# 只观测 /sys/class/power_supply/BAT* 的存在性；这是 _STA 翻转在用户态唯一
# 可靠的可观测结果（_STA 本身不可直接读，不臆造读数）。
battery_sample() {
  local secs="$1" interval=2 elapsed=0 miss=0 prev="?" cur transitions=0
  while [ "$elapsed" -lt "$secs" ]; do
    if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then cur="present"; else cur="absent"; fi
    [ "$prev" != "?" ] && [ "$cur" != "$prev" ] && transitions=$((transitions + 1))
    [ "$cur" = "absent" ] && miss=$((miss + 1))
    prev="$cur"
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  local n=$((secs / interval))
  [ "$n" -gt 0 ] || n=1
  printf '%s\t%s\t%s\t%s\n' "$secs" "$miss" "$n" "$transitions"
}

report_battery() {
  local secs="$1" out secs_o miss n tr rate verdict
  out="$(battery_sample "$secs")"
  IFS=$'\t' read -r secs_o miss n tr <<<"$out"
  rate=$(awk -v m="$miss" -v n="$n" 'BEGIN{printf "%.0f", m/n*100}')
  if [ "$miss" -eq 0 ]; then verdict="稳定"
  elif [ "$rate" -lt 20 ]; then verdict="偶发抖动"
  else verdict="频繁抖动"
  fi
  printf '  采样时长    : %ss（每 2s 一次，共 %s 次）\n' "$secs_o" "$n"
  printf '  电池缺失次数: %s（%s%%）\n' "$miss" "$rate"
  printf '  状态翻转    : %s 次\n' "$tr"
  printf '  判定        : %s\n' "$verdict"
  printf '  当前电池    : %s\n' "$(compgen -G '/sys/class/power_supply/BAT*' >/dev/null && echo 存在 || echo 不存在)"

  local klog=""
  if have_sudo; then
    klog="$(sudo -n journalctl -k --since '-10 min' --no-pager 2>/dev/null | grep -c 'power_supply' || true)"
  fi
  [ -n "$klog" ] && printf '  内核日志    : 近 10 分钟 power_supply 相关 %s 行\n' "$klog"
  [ "$miss" -gt 0 ] || return 0
  return 1
}

# ---- 外设 -------------------------------------------------------------------
show_displays() {
  local f dir st modes
  for f in /sys/class/drm/card*-*/status; do
    [ -r "$f" ] || continue
    dir="$(dirname "$f")"
    st="$(cat "$f" 2>/dev/null)"
    [ "$st" = "connected" ] || continue
    modes="$(head -1 "$dir/modes" 2>/dev/null)"
    printf '  %-18s %-10s 首选 %s\n' "$(basename "$dir")" "$st" "${modes:-未知模式}"
  done
}

show_typec() {
  local p n=0
  for p in /sys/class/typec/port[0-9]*; do
    [ -d "$p" ] || continue
    n=$((n + 1))
    printf '  %-10s data=%s power=%s partner=%s\n' \
      "$(basename "$p")" \
      "$(cat "$p/data_role" 2>/dev/null | tr '\n' ' ')" \
      "$(cat "$p/power_role" 2>/dev/null | tr '\n' ' ')" \
      "$([ -d "$p/partner" ] && echo 已连接 || echo 无)"
  done
  [ "$n" -eq 0 ] && echo "  （无 typec 节点，可能不是 USB-C 机型）"
}

show_printers() {
  if have lpstat; then
    local out; out="$(lpstat -p 2>/dev/null | head -5)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /' || echo "  （无打印队列）"
  else
    echo "  （cups 未安装）"
  fi
}

show_scanners() {
  if have scanimage; then
    local out; out="$(scanimage -L 2>/dev/null | head -3)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /' || echo "  （未发现扫描仪）"
  else
    echo "  （sane 未安装）"
  fi
}

show_bt() {
  if have bluetoothctl; then
    local out; out="$(timeout 5 bluetoothctl devices Connected 2>/dev/null | head -5)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /' || echo "  （无已连接设备）"
  else
    echo "  （bluez 未安装）"
  fi
}

show_battery_brief() {
  local b found=0
  for b in /sys/class/power_supply/BAT*; do
    [ -d "$b" ] || continue
    found=1
    printf '  %s: %s%% 状态=%s 阈值=%s/%s\n' "$(basename "$b")" \
      "$(cat "$b/capacity" 2>/dev/null)" "$(cat "$b/status" 2>/dev/null)" \
      "$(cat "$b/charge_control_start_threshold" 2>/dev/null || echo -)" \
      "$(cat "$b/charge_control_end_threshold" 2>/dev/null || echo -)"
  done
  [ "$found" -eq 1 ] || echo "  （当前无 BAT* 设备；可能是电池枚举抖动，跑 --battery 确认）"
}

# ---- 主流程 -----------------------------------------------------------------
if [ "$ACTION" = "gate" ]; then
  SECS=$((MINUTES * 60))
  step "交付前电源门禁：${MINUTES} 分钟连续观测（$SECS 秒）"
  if report_battery "$SECS"; then
    ok "电池全程存在，门禁通过"
    exit 0
  fi
  warn "观测期内电池消失过：不得交付"
  log "处置顺序见 docs/28-外设与电源.md §3：EC 静电复位 → BIOS 复位电池 → 报修"
  exit 1
fi

if [ "$ACTION" = "battery" ]; then
  echo
  echo "════════ 电池枚举连续性 ════════"
  if report_battery "$SECS"; then exit 0; else exit 1; fi
fi

# status
{
  echo
  echo "════════ 外设矩阵 ════════"
  echo "  显示输出:"
  show_displays | sed 's/^/  /'
  echo "  USB-C / 扩展坞:"
  show_typec
  echo "  打印机:"
  show_printers
  echo "  扫描仪:"
  show_scanners
  echo "  蓝牙已连接:"
  show_bt
  echo "  电池:"
  show_battery_brief
  echo "  触摸板: $(gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click 2>/dev/null) 点按 / $(gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll 2>/dev/null) 自然滚动"
} | if [ "$AUDIT" -eq 1 ]; then
  OUT="$LOG_DIR/peripherals-$RUN_ID.txt"
  tee "$OUT"
  log "已落盘: ${OUT#$PROJECT_ROOT/}"
else
  cat
fi
