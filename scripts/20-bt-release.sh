#!/usr/bin/env bash
# ============================================================================
# 20-bt-release.sh - 释放被应用占用的蓝牙耳机（多点连接切不过去时用）
#   原理：蓝牙 multipoint 切换要求「当前设备的 A2DP 链路空闲」。
#   某些应用（典型：Chromium 残留的媒体会话）会一直保持流不释放，
#   耳机就认为电脑还在用，不肯把手交给手机/平板。
#   本脚本把这类流移到内置扬声器，让耳机回到 IDLE。
# 用法:
#   ./scripts/20-bt-release.sh             # 列出占用蓝牙的音频流
#   ./scripts/20-bt-release.sh --release   # 全部移到内置输出
#   ./scripts/20-bt-release.sh --watch     # 前台监控：静默 60 秒自动释放
#   ./scripts/20-bt-release.sh --reset     # 清除「应用→扬声器」的记忆（--release 的副作用）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ACTION=list
SILENT_THRESHOLD=6      # watch 模式连续静默次数（× 10 秒）
POLL=10

while [ $# -gt 0 ]; do
  case "$1" in
    --list|--release|--watch|--reset) ACTION="${1#--}" ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

find_bt_sink() {
  LC_ALL=C pactl list short sinks 2>/dev/null | awk '/bluez_output/ {print $1; exit}'
}

find_local_sink() {
  # 优先扬声器，其次任意非蓝牙输出
  LC_ALL=C pactl list short sinks 2>/dev/null \
    | awk '/alsa_output/ && /Speaker/ {print $1; exit}' \
    || true
}

local_sink() {
  local s
  s="$(find_local_sink)"
  [ -n "$s" ] || s="$(LC_ALL=C pactl list short sinks 2>/dev/null | awk '!/bluez/ {print $1; exit}')"
  printf '%s' "$s"
}

# 输出「流 ID \t 应用名 \t 媒体名」，只含挂在指定 sink 上的
list_streams() {
  local bt="$1"
  pactl -f json list sink-inputs 2>/dev/null | jq -r --arg bt "$bt" '
    .[] | select((.sink|tostring) == $bt)
    | "\(.index)\t\(.properties["application.name"] // "?")\t\(.properties["media.name"] // "")"
  ' 2>/dev/null
}

has_streams() { [ -n "$(list_streams "$1")" ]; }

do_release() {
  local bt="$1" target="$2" id app media n=0
  while IFS=$'\t' read -r id app media; do
    [ -n "$id" ] || continue
    if pactl move-sink-input "$id" "$target" 2>/dev/null; then
      ok "已移走 #$id（$app）→ 内置输出"
      n=$((n + 1))
    else
      warn "移动 #$id（$app）失败"
    fi
  done < <(list_streams "$bt")
  [ "$n" -gt 0 ] && ok "共释放 $n 个流" || warn "没有可移动的流"
}

# ---- 前置检查 --------------------------------------------------------------
BT_SINK="$(find_bt_sink)"
[ -n "$BT_SINK" ] || die "未找到蓝牙输出设备。请先连接耳机：bluetoothctl connect <MAC>"
BT_NAME="$(LC_ALL=C pactl list short sinks 2>/dev/null | awk -v s="$BT_SINK" '$1==s {print $2}')"
TARGET="$(local_sink)"
[ -n "$TARGET" ] || die "找不到内置输出设备"

case "$ACTION" in
  list)
    echo "蓝牙输出: #$BT_SINK ($BT_NAME)"
    echo "内置输出: #$TARGET"
    echo
    STREAMS="$(list_streams "$BT_SINK")"
    if [ -z "$STREAMS" ]; then
      ok "蓝牙上没有音频流，耳机应可被其他设备接管"
    else
      warn "以下流正占用耳机（会阻止 multipoint 切换）："
      printf '%s\n' "$STREAMS" | while IFS=$'\t' read -r id app media; do
        printf '  #%-5s %-18s %s\n' "$id" "$app" "$media"
      done
      echo
      echo "释放: $0 --release"
    fi
    ;;

  release)
    log "把 #$BT_SINK 上的流移到 #$TARGET"
    do_release "$BT_SINK" "$TARGET"
    sleep 1
    STATE="$(LC_ALL=C pactl list short sinks 2>/dev/null | awk -v s="$BT_SINK" '$1==s {print $NF}')"
    log "耳机当前状态: ${STATE:-unknown}"
    ;;

  reset)
    # --release 把流移到扬声器后，PipeWire 的 stream-restore 会把这件事
    # 记成「用户为这个应用选了设备」，导致该应用以后默认走扬声器。
    # 这里清掉这类记忆，让它们重新跟随默认设备（通常是耳机）。
    SP="$HOME/.local/state/wireplumber/stream-properties"
    [ -f "$SP" ] || die "找不到 $SP"
    LOCAL_NAME="$(LC_ALL=C pactl list short sinks 2>/dev/null | awk '!/bluez/ {print $2; exit}')"
    [ -n "$LOCAL_NAME" ] || die "找不到内置输出设备名"
    N="$(grep -c "$LOCAL_NAME" "$SP" 2>/dev/null || true)"
    N="${N:-0}"
    if [ "$N" -le 0 ]; then
      ok "没有指向内置输出的记忆，无需清理"
      exit 0
    fi
    warn "有 $N 条应用被记住指向内置输出，清理需重启 WirePlumber（音频会中断约 2 秒）"
    cp "$SP" "$SP.bak"
    systemctl --user stop wireplumber
    sed -i "\|$LOCAL_NAME|d" "$SP"
    systemctl --user start wireplumber
    sleep 2
    ok "已清除 $N 条（备份 ${SP}.bak），这些应用将重新跟随默认设备"
    ;;

  watch)
    log "监控中（每 ${POLL}s 检查一次，连续 $((SILENT_THRESHOLD * POLL))s 静默则释放）"
    log "Ctrl+C 退出"
    silent=0
    while true; do
      if ! has_streams "$BT_SINK"; then
        silent=0
      else
        # pw-top 的 RATE 列为第 4 列；bluez 无数据时 RATE=0
        rate="$(pw-top -b -n 1 2>/dev/null | awk '/bluez_playback/ {print $4; exit}')"
        if [ "${rate:-0}" = "0" ]; then
          silent=$((silent + 1))
          log "静默 ${silent}/${SILENT_THRESHOLD}（rate=${rate:-0}）"
        else
          [ "$silent" -gt 0 ] && log "检测到音频数据（rate=$rate），重新计数"
          silent=0
        fi
        if [ "$silent" -ge "$SILENT_THRESHOLD" ]; then
          log "蓝牙流已静默 $((SILENT_THRESHOLD * POLL)) 秒，释放耳机"
          do_release "$BT_SINK" "$TARGET"
          silent=0
        fi
      fi
      sleep "$POLL"
    done
    ;;
esac
