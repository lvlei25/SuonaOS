#!/usr/bin/env bash
# ============================================================================
# 17-sleep-hook.sh - 挂起/恢复后自愈 upower（修键盘背光失效等）
#   背景：upowerd 缓存的 sysfs 句柄在 resume 后失效，导致
#         键盘背光不可调（ISSUE-31）、电池图标异常（ISSUE-29）。
#   做法：resume 后先检测 KbdBacklight 是否还活着，**只在失效时**重启 upower，
#         重启后若 BAT* 消失则自动重载 thinkpad_acpi 兜底。
#   只在需要时重启，避免每次唤醒都触发 ISSUE-29 的竞争条件。
# 用法:
#   ./scripts/17-sleep-hook.sh --install   # 写 /etc/systemd/system-sleep/
#   ./scripts/17-sleep-hook.sh --status
#   ./scripts/17-sleep-hook.sh --test      # 模拟 post 阶段执行一次
#   ./scripts/17-sleep-hook.sh --restore
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

HOOK_DIR="/etc/systemd/system-sleep"
HOOK="$HOOK_DIR/50-suona-upower"

ACTION=""
case "${1:-}" in
  --install) ACTION=install ;;
  --status)  ACTION=status ;;
  --test)    ACTION=test ;;
  --restore) ACTION=restore ;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "未知参数: ${1:-}（--install / --status / --test / --restore）" ;;
esac

kbd_ok() {
  gdbus call --system --dest org.freedesktop.UPower \
    --object-path /org/freedesktop/UPower/KbdBacklight \
    --method org.freedesktop.UPower.KbdBacklight.GetBrightness >/dev/null 2>&1
}

if [ "$ACTION" = status ]; then
  echo "hook 路径 : $HOOK"
  echo "安装状态  : $([ -x "$HOOK" ] && echo 已安装 || echo 未安装)"
  echo "键盘背光  : $(kbd_ok && echo 可读 || echo '不可读（需要重启 upower）')"
  echo "upower    : $(systemctl is-active upower 2>/dev/null)"
  echo "BAT0      : $([ -d /sys/class/power_supply/BAT0 ] && echo 存在 || echo 缺失)"
  echo "最近日志  :"
  journalctl -t suona-upower --no-pager -n 3 2>/dev/null | sed 's/^/  /' | tail -3
  [ -z "$(journalctl -t suona-upower --no-pager -n 1 2>/dev/null)" ] && echo "  （暂无）"
  exit 0
fi

if [ "$ACTION" = test ]; then
  [ -x "$HOOK" ] || die "hook 未安装，先执行 --install"
  step "模拟 post 阶段执行（当前键盘背光可读时会直接跳过）"
  sudo -n "$HOOK" post; rc=$?
  echo "退出码: $rc"
  echo "--- 日志 ---"
  journalctl -t suona-upower --no-pager -n 5 2>/dev/null | tail -5
  exit 0
fi

if [ "$ACTION" = restore ]; then
  if [ -e "$HOOK" ]; then
    sudo -n rm -f "$HOOK" && ok "已删除 $HOOK"
  else
    ok "hook 不存在，无需删除"
  fi
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/2 备份既有 hook"
if [ -e "$HOOK" ]; then
  mkdir -p "$BACKUP_DIR/$RUN_ID/files$HOOK_DIR"
  sudo -n cp -a "$HOOK" "$BACKUP_DIR/$RUN_ID/files$HOOK_DIR/"
  printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$HOOK" "$RUN_ID/files$HOOK_DIR/50-suona-upower" >>"$MANIFEST"
  ok "已备份 → backup/$RUN_ID/"
else
  ok "无既有文件（新建）"
fi

step "2/2 写入 hook"
TMP="$(mktemp)"
cat >"$TMP" <<'HOOK_EOF'
#!/bin/sh
# SuonaOS: 挂起/恢复后自愈 upower
#   1) upowerd 的 sysfs 句柄在 resume 后失效 -> 键盘背光不可调（ISSUE-31）
#   2) 只在 KbdBacklight 读不出来时才重启 upower，避免每次唤醒都触发
#      upower 与 thinkpad_acpi 的竞争（ISSUE-29）
#   3) 重启后若 BAT* 消失，自动重载 thinkpad_acpi 兜底
[ "$1" = "post" ] || exit 0

log() { logger -t suona-upower "$*"; }

# 等 upower 就绪（resume 早期 dbus 可能还没通）
i=0
while [ $i -lt 5 ]; do
    systemctl is-active --quiet upower && break
    sleep 1
    i=$((i + 1))
done

if gdbus call --system --dest org.freedesktop.UPower \
        --object-path /org/freedesktop/UPower/KbdBacklight \
        --method org.freedesktop.UPower.KbdBacklight.GetBrightness >/dev/null 2>&1; then
    log "kbd backlight OK after resume, skip"
    exit 0
fi

log "kbd backlight broken after resume, restarting upower"
systemctl restart upower
sleep 2


if ! ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    log "BAT missing after upower restart, reloading thinkpad_acpi"
    modprobe -r thinkpad_acpi 2>/dev/null
    modprobe thinkpad_acpi 2>/dev/null
    sleep 2
fi

if gdbus call --system --dest org.freedesktop.UPower \
        --object-path /org/freedesktop/UPower/KbdBacklight \
        --method org.freedesktop.UPower.KbdBacklight.GetBrightness >/dev/null 2>&1; then
    if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        log "recovered: kbd backlight OK, battery OK"
    else
        log "recovered: kbd backlight OK, but battery still missing"
    fi
else
    log "ERROR: kbd backlight still broken, manual fix needed"
fi
HOOK_EOF
sudo -n mkdir -p "$HOOK_DIR" || die "创建 $HOOK_DIR 失败"
sudo -n install -m 0755 -o root -g root "$TMP" "$HOOK" || die "写入 $HOOK 失败"
rm -f "$TMP"
[ -x "$HOOK" ] || die "hook 不可执行"
ok "$HOOK 已安装（0755 root:root）"

echo
log "resume 后自动检测：键盘背光不可读时才重启 upower"
log "状态: $0 --status    模拟: $0 --test    回滚: $0 --restore"
