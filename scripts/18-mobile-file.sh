#!/usr/bin/env bash
# ============================================================================
# 18-mobile-file.sh - 手机文件互传（ADB，复用 mobile-connect 的记忆地址）
#   补 scrcpy 的能力缺口：scrcpy 只支持「拖入」，不支持「拖出」
#   默认推送目标 /sdcard/Download/，默认拉取到 ~/Downloads/
# 用法:
#   ./scripts/18-mobile-file.sh --push <文件或目录>...   # 电脑 → 手机
#   ./scripts/18-mobile-file.sh --pull <手机路径>...      # 手机 → 电脑
#   ./scripts/18-mobile-file.sh --ls [/sdcard/Download]  # 列目录
#   ./scripts/18-mobile-file.sh --to <路径> --push ...   # 覆盖目标位置
#   ./scripts/18-mobile-file.sh --status
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="$HOME/.config/linux-tune/mobile.conf"
DEST_REMOTE="/sdcard/Download"
DEST_LOCAL="$HOME/Downloads"
LAST_ADDR=""
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

ACTION=""
TARGET=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --push|--pull|--ls|--status) ACTION="${1#--}" ;;
    --to) TARGET="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "未知参数: $1" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

[ -n "$ACTION" ] || { usage; exit 1; }

get_device() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /^emulator/ {print $1; exit}'
}

# 有设备直接用；没有就复用 mobile.conf 里记住的地址尝试一次。
# 结果写全局 DEV：命令替换里的 exit 不会退出主脚本，所以不在函数里 die。
ensure_device() {
  DEV="$(get_device)"
  if [ -z "$DEV" ] && [ -n "$LAST_ADDR" ]; then
    log "当前无设备，尝试复用已保存地址 $LAST_ADDR"
    timeout 10 adb connect "$LAST_ADDR" >/dev/null 2>&1
    sleep 1
    DEV="$(get_device)"
  fi
}

need_device() {
  ensure_device
  [ -n "$DEV" ] || die "没有已连接设备。先执行 ./scripts/mobile-connect.sh --status 诊断（多为无线调试已关闭）"
}

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  adb devices -l
  echo "已保存地址  : ${LAST_ADDR:-无}"
  echo "默认推送目标: $DEST_REMOTE"
  echo "默认拉取目录: $DEST_LOCAL"
  if [ -d "$DEST_LOCAL" ]; then
    echo "本地目录    : 存在"
  else
    echo "本地目录    : 不存在（拉取时自动创建）"
  fi
  exit 0
fi

# ---- ls --------------------------------------------------------------------
if [ "$ACTION" = ls ]; then
  need_device
  REMOTE="${TARGET:-${ARGS[0]:-$DEST_REMOTE}}"
  echo "== $REMOTE =="
  adb -s "$DEV" shell ls -la "$REMOTE" 2>&1 | sed 's/\r$//' | head -60
  exit 0
fi

# ---- push ------------------------------------------------------------------
if [ "$ACTION" = push ]; then
  [ ${#ARGS[@]} -gt 0 ] || die "用法: --push <文件或目录>..."
  need_device
  REMOTE="${TARGET:-$DEST_REMOTE}"
  adb -s "$DEV" shell mkdir -p "$REMOTE" >/dev/null 2>&1
  ok_n=0; bad_n=0
  for f in "${ARGS[@]}"; do
    if [ ! -e "$f" ]; then
      warn "跳过（不存在）: $f"
      bad_n=$((bad_n + 1))
      continue
    fi
    name="$(basename "$f")"
    log "推送 $name → $REMOTE/"
    if adb -s "$DEV" push "$f" "$REMOTE/" 2>&1 | sed 's/\r$//' | tail -1; then
      ok_n=$((ok_n + 1))
    else
      warn "失败: $f"
      bad_n=$((bad_n + 1))
    fi
  done
  echo
  if [ "$bad_n" -eq 0 ]; then
    ok "已推送 $ok_n 项到 $REMOTE/"
  else
    warn "成功 $ok_n 项，失败 $bad_n 项"
  fi
  exit 0
fi

# ---- pull ------------------------------------------------------------------
if [ "$ACTION" = pull ]; then
  [ ${#ARGS[@]} -gt 0 ] || die "用法: --pull <手机路径>..."
  need_device
  LOCAL="${TARGET:-$DEST_LOCAL}"
  mkdir -p "$LOCAL"
  ok_n=0; bad_n=0
  for p in "${ARGS[@]}"; do
    log "拉取 $p → $LOCAL/"
    if adb -s "$DEV" pull "$p" "$LOCAL/" 2>&1 | sed 's/\r$//' | tail -1; then
      ok_n=$((ok_n + 1))
    else
      warn "失败: $p"
      bad_n=$((bad_n + 1))
    fi
  done
  echo
  if [ "$bad_n" -eq 0 ]; then
    ok "已拉取 $ok_n 项到 $LOCAL/"
  else
    warn "成功 $ok_n 项，失败 $bad_n 项"
  fi
  exit 0
fi
