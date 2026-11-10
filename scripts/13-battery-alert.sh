#!/usr/bin/env bash
# ============================================================================
# 13-battery-alert.sh - 电池关键节点提示（只在节点响一次，不随每 1% 变化）
#   低电量 20% / 10%：由 gsd-power 按 upower 的 warning-level 自动播放
#                     battery-low / battery-caution（主题里已有这两个文件）
#   充满/停止充电  ：gsd-power 没有这一档，由本脚本的 systemd user timer
#                     每 5 分钟检查一次，进入「已到上限」时播放 battery-full
# 用法:
#   ./scripts/13-battery-alert.sh --install   # 装 timer + 写 UPower 阈值（备份）
#   ./scripts/13-battery-alert.sh --check     # 单次检查（timer 调用）
#   ./scripts/13-battery-alert.sh --status    # 查看电量、阈值、timer 状态
#   ./scripts/13-battery-alert.sh --test      # 试听三个电池事件
#   ./scripts/13-battery-alert.sh --restore   # 卸载 timer 并恢复 UPower 阈值
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# BAT_DIR / AC_ONLINE_FILE 仅用于单元测试（伪造 sysfs），生产走默认路径
BAT="${BAT_DIR:-$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)}"
AC_ONLINE="${AC_ONLINE_FILE:-/sys/class/power_supply/AC/online}"
UPOWER_CONF="/etc/UPower/UPower.conf"
LOW_PCT=20
CRIT_PCT=10
STATE_DIR="$HOME/.local/state/linux-tune"
STATE="$STATE_DIR/battery-alert.state"
UNIT_DIR="$HOME/.config/systemd/user"
SVC="suona-battery-alert.service"
TMR="suona-battery-alert.timer"

ACTION="check"
case "${1:-}" in
  --install) ACTION=install ;;
  --check)   ACTION=check ;;
  --status)  ACTION=status ;;
  --test)    ACTION=test ;;
  --restore) ACTION=restore ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "未知参数: $1（--install / --check / --status / --test / --restore）" ;;
esac

[ -n "$BAT" ] || die "未找到电池（/sys/class/power_supply/BAT*）"
read_val() { cat "$1" 2>/dev/null || echo ""; }
play_event() {
  local ev="$1"
  if have canberra-gtk-play; then
    canberra-gtk-play -i "$ev" >/dev/null 2>&1
  else
    local f="$HOME/.local/share/sounds/${SND_THEME:-Suona}/stereo/$ev.oga"
    [ -f "$f" ] && paplay "$f" >/dev/null 2>&1
  fi
}

# 重启 upower 并确保电池没从 sysfs 掉线。
# 本机 thinkpad_acpi 在充电阈值附近会高频重注册电池，restart upower 偶发让
# BAT0 节点消失（ISSUE-29），重载模块可让 ACPI 电池重新注册。
restart_upower_safe() {
  sudo -n systemctl restart upower || die "重启 upower 失败"
  sleep 2
  if ! ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    warn "重启 upower 后电池节点消失，重载 thinkpad_acpi 恢复"
    sudo -n modprobe -r thinkpad_acpi 2>/dev/null && sudo -n modprobe thinkpad_acpi 2>/dev/null
    sleep 3
    ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1 \
      || die "电池节点仍未恢复，请执行 dmesg | tail 检查 thinkpad_acpi"
    ok "电池节点已恢复（$(ls -d /sys/class/power_supply/BAT* | xargs -n1 basename)）"
  fi
}

# ---- 单次检查（timer 调用，必须静默、快、幂等）-----------------------------
if [ "$ACTION" = check ]; then
  mkdir -p "$STATE_DIR"
  status="$(read_val "$BAT/status")"
  cap="$(read_val "$BAT/capacity")"
  ac="$(read_val "$AC_ONLINE")"
  end="$(read_val "$BAT/charge_control_end_threshold")"
  end="${end:-100}"
  prev="$(read_val "$STATE")"

  # 只要不在充电方向，就复位「已提示」标记
  if [ "$status" = "Discharging" ] || [ "$ac" = "0" ]; then
    [ "$prev" = "full-notified" ] && echo "idle" >"$STATE"
    exit 0
  fi

  # 已到充电上限：Full，或达到 end_threshold 且仍插着电
  if [ "$status" = "Full" ] || { [ -n "$cap" ] && [ "$cap" -ge "$end" ] 2>/dev/null; }; then
    if [ "$prev" != "full-notified" ]; then
      play_event battery-full
      have notify-send && notify-send -a "SuonaOS" -i battery-full-charged \
        -h string:x-canonical-private-synchronous:suona-battery \
        "电池已充至上限" "当前 ${cap}%，已按养护阈值 ${end}% 停止充电" 2>/dev/null
      echo "full-notified" >"$STATE"
      printf '[%s] battery-full 已提示（%s%%，上限 %s%%）\n' "$(date '+%F %T')" "$cap" "$end" >>"$LOG_DIR/battery-alert.log"
    fi
  fi
  exit 0
fi

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  echo "电池路径   : $BAT"
  echo "当前状态   : $(read_val "$BAT/status")"
  echo "当前电量   : $(read_val "$BAT/capacity")%"
  echo "交流供电   : $(read_val "$AC_ONLINE")（1=已插电）"
  echo "充电上限   : $(read_val "$BAT/charge_control_end_threshold")%"
  echo "低电阈值   : $(grep -E '^Percentage(Low|Critical|Action)=' "$UPOWER_CONF" 2>/dev/null | tr '\n' ' ')"
  echo "主题事件   : $(ls -1 "$HOME/.local/share/sounds/Suona/stereo/" 2>/dev/null | grep -c '^battery-')/3（low / caution / full）"
  tmr_en="$(systemctl --user is-enabled "$TMR" 2>/dev/null)"
  tmr_act="$(systemctl --user is-active "$TMR" 2>/dev/null)"
  echo "timer      : ${tmr_en:-未安装} / ${tmr_act:-inactive}"
  echo "内部标记   : $(read_val "$STATE" | tr -d '\n')"
  exit 0
fi

# ---- test ------------------------------------------------------------------
if [ "$ACTION" = test ]; then
  for ev in battery-low battery-caution battery-full; do
    printf '  ♪ %-18s' "$ev"
    play_event "$ev" && echo '已播放'
    sleep 0.2
  done
  exit 0
fi

# ---- install ---------------------------------------------------------------
if [ "$ACTION" = install ]; then
  step "1/3 校准 upower 低电量阈值（20% / 10%）"
  cur_low="$(grep -E '^PercentageLow=' "$UPOWER_CONF" | cut -d= -f2)"
  cur_crit="$(grep -E '^PercentageCritical=' "$UPOWER_CONF" | cut -d= -f2)"
  if [ "${cur_low%.*}" = "$LOW_PCT" ] && [ "${cur_crit%.*}" = "$CRIT_PCT" ]; then
    ok "已是 $LOW_PCT% / $CRIT_PCT%，无需修改"
  else
    backup_file "$UPOWER_CONF"
    sudo -n sed -i -E "s/^PercentageLow=.*/PercentageLow=${LOW_PCT}.0/; s/^PercentageCritical=.*/PercentageCritical=${CRIT_PCT}.0/" "$UPOWER_CONF" \
      || die "写入 $UPOWER_CONF 失败（需要免密 sudo）"
    restart_upower_safe
    ok "阈值已改为 low=${LOW_PCT}% / critical=${CRIT_PCT}%，upower 已重启"
  fi

  step "2/3 检查主题事件文件"
  miss=0
  for ev in battery-low battery-caution battery-full; do
    [ -s "$HOME/.local/share/sounds/Suona/stereo/$ev.oga" ] || { warn "缺少 $ev.oga（先跑 11-sound-theme.sh）"; miss=$((miss+1)); }
  done
  [ "$miss" -eq 0 ] || die "$miss 个电池事件音缺失"
  ok "battery-low / battery-caution / battery-full 就绪"

  step "3/3 安装 systemd user timer（每 5 分钟检查一次，仅充满时提示）"
  mkdir -p "$UNIT_DIR" "$STATE_DIR"
  cat >"$UNIT_DIR/$SVC" <<EOF
[Unit]
Description=SuonaOS 电池充满提示

[Service]
Type=oneshot
ExecStart=$PROJECT_ROOT/scripts/13-battery-alert.sh --check
EOF
  cat >"$UNIT_DIR/$TMR" <<EOF
[Unit]
Description=SuonaOS 电池充满提示（每分钟）

[Timer]
OnBootSec=90
OnUnitActiveSec=300
AccuracySec=30

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$TMR" || die "启用 $TMR 失败"
  ok "$TMR 已启用（$(systemctl --user is-active "$TMR")）"
  echo
  log "低电量 20% / 10% 由 gsd-power 自动播放；充满由 timer 播放"
  log "试听: $0 --test    状态: $0 --status"
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  step "1/2 停用并删除 timer"
  systemctl --user disable --now "$TMR" 2>/dev/null && ok "已停用 $TMR" || warn "$TMR 未在运行"
  rm -f "$UNIT_DIR/$TMR" "$UNIT_DIR/$SVC"
  systemctl --user daemon-reload
  rm -f "$STATE"
  ok "unit 与状态文件已清理"

  step "2/2 恢复 upower 阈值"
  latest=""
  for d in $(ls -1d "$BACKUP_DIR"/*/ 2>/dev/null | sort); do
    [ -f "$d/files$UPOWER_CONF" ] && latest="$d"
  done
  if [ -n "$latest" ]; then
    sudo -n cp -a "$latest/files$UPOWER_CONF" "$UPOWER_CONF" || die "恢复 $UPOWER_CONF 失败"
    restart_upower_safe
    ok "已从 ${latest#$PROJECT_ROOT/} 恢复 $UPOWER_CONF"
  else
    warn "未找到备份，手动检查 $UPOWER_CONF"
  fi
  exit 0
fi
