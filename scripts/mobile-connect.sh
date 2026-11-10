#!/usr/bin/env bash
# ============================================================================
# mobile-connect.sh — 一键连接红米并投屏（免去每次手输长命令）
#
# 用法:
#   ./scripts/mobile-connect.sh              # 自动连接 + 投屏（用上次成功地址）
#   ./scripts/mobile-connect.sh 39959        # 端口变了：指定一次，之后自动记住
#   ./scripts/mobile-connect.sh --tcpip      # 把设备切到固定 5555，此后长期免输端口
#   ./scripts/mobile-connect.sh --status     # 只看状态，不启动投屏
#   ./scripts/mobile-connect.sh --stop       # 断开连接
#
# 端口来源：HyperOS「无线调试」主页面显示的 IP:端口（会变，故支持记忆 + 单次覆盖）
# 注意：本机实测 adb mdns services 为空，HyperOS 不广播 ADB 服务，无法全自动发现端口。
# ============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$HOME/.config/linux-tune/mobile.conf"
LOG="$PROJECT_ROOT/logs/mobile-connect.log"
mkdir -p "$(dirname "$CONF")" "$(dirname "$LOG")"

DEVICE_IP=""
LAST_ADDR=""
WINDOW_HEIGHT=""
[ -f "$CONF" ] && . "$CONF"

# 窗口高度（逻辑像素）：环境变量 > 配置 > 默认
# 本机 GNOME 200% 缩放，逻辑桌面 1536x960，去掉顶栏后约 900 可用，取 840 留余量。
# 覆盖：MC_HEIGHT=900 mobile-connect.sh
MC_H="${MC_HEIGHT:-${WINDOW_HEIGHT:-840}}"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }
warn() { printf '  ! %s\n' "$*" | tee -a "$LOG"; }
die()  { printf '  x %s\n' "$*" | tee -a "$LOG" >&2; exit 1; }

save_conf() {
  cat >"$CONF" <<EOF
# 由 mobile-connect.sh 自动生成（$(date '+%F %T')）
DEVICE_IP="$DEVICE_IP"
LAST_ADDR="$LAST_ADDR"
# 投屏窗口高度（逻辑像素），改这里即可调整默认大小
WINDOW_HEIGHT="$MC_H"
EOF
}

# 读取手机视频源尺寸，按手机宽高比算出窗口宽度
get_video_size() {
  local line
  line="$(adb -s "$1" shell wm size 2>/dev/null | grep -i 'Override size' | head -1)"
  [ -z "$line" ] && line="$(adb -s "$1" shell wm size 2>/dev/null | grep -i 'Physical size' | head -1)"
  echo "$line" | sed -nE 's/.*: ([0-9]+)x([0-9]+).*/\1 \2/p'
}

# 取第一个 device 状态的地址（排除 offline / unauthorized / emulator）
get_device() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /^emulator/ {print $1; exit}'
}

try_connect() {
  local addr="$1"
  [ -z "$addr" ] && return 1
  log "尝试连接 $addr"
  timeout 12 adb connect "$addr" >/dev/null 2>&1
  local i
  for i in 1 2 3 4 5; do
    [ -n "$(get_device)" ] && return 0
    sleep 1
  done
  return 1
}

scrcpy_running() { pgrep -f 'scrcpy -s ' >/dev/null 2>&1; }

# ---- 参数处理 --------------------------------------------------------------
ARG="${1:-}"

case "$ARG" in
  --status)
    adb devices -l
    scrcpy_running && echo 'scrcpy: 运行中' || echo 'scrcpy: 未运行'
    echo "已保存地址: ${LAST_ADDR:-无}"
    exit 0 ;;

  --stop)
    [ -n "$LAST_ADDR" ] && adb disconnect "$LAST_ADDR" >/dev/null 2>&1
    pkill -f 'scrcpy -s ' 2>/dev/null || true
    log '已断开'
    exit 0 ;;

  --tcpip)
    ADDR="$(get_device)"
    [ -z "$ADDR" ] && die '当前无已连接设备，请先 USB 连接或执行 mobile-connect.sh <端口>'
    IP="${ADDR%%:*}"
    log "把设备切换到固定 5555 端口..."
    adb -s "$ADDR" tcpip 5555 2>&1 | tee -a "$LOG"
    sleep 2
    LAST_ADDR="$IP:5555"
    DEVICE_IP="$IP"
    save_conf
    if try_connect "$LAST_ADDR"; then
      log "已固定为 $LAST_ADDR（手机重启后需重新 USB 执行 adb tcpip 5555）"
    else
      warn "5555 连接未成功；部分 HyperOS 需先插 USB 线执行 adb tcpip 5555"
    fi
    exit 0 ;;

  --port-prompt)
    # 供桌面启动器「端口已变化」调用：交互输入端口，之后自动记住
    cat <<'HINT'
  请打开手机：设置 → 更多设置 → 开发者选项 → 无线调试
  查看主页面的「IP 地址和端口」，输入端口号（IP 会沿用已记录的）。
  输入 q 取消。
HINT
    printf '  新端口号 (如 39959): '
    read -r PORT || true
    [ "$PORT" = "q" ] && { log '已取消'; exit 0; }
    [[ "$PORT" =~ ^[0-9]{2,5}$ ]] || die "端口应为 2~5 位数字，收到: $PORT"
    exec "$0" "$PORT"      # 交给端口分支处理并记住
    ;;

  '')
    # 自动模式：已有 device → 直接投屏；否则用上次地址重连
    ADDR="$(get_device)"
    if [ -z "$ADDR" ] && [ -n "$LAST_ADDR" ]; then
      try_connect "$LAST_ADDR" || true
      ADDR="$(get_device)"
    fi
    ;;

  *)
    # 端口变更：只允许纯数字端口
    [[ "$ARG" =~ ^[0-9]{2,5}$ ]] || die "参数应为 2~5 位端口号，例如: mobile-connect.sh 39959"
    PORT="$ARG"
    IP="${DEVICE_IP:-}"
    if [ -z "$IP" ] && [ -n "$LAST_ADDR" ]; then IP="${LAST_ADDR%%:*}"; fi
    if [ -z "$IP" ]; then
      # 从当前 ARP / 同网段里找红米（仅作兜底提示）
      warn '尚未记录手机 IP，请在下方输入手机无线调试页面显示的 IP'
      printf '  手机 IP (如 192.168.31.196): '
      read -r IP
      [ -n "$IP" ] || die '未输入 IP'
    fi
    LAST_ADDR="$IP:$PORT"
    DEVICE_IP="$IP"
    try_connect "$LAST_ADDR" || die "连接 $LAST_ADDR 失败：确认手机解锁、无线调试开关打开、IP/端口与页面一致"
    save_conf
    ADDR="$(get_device)"
    log "已记住 $LAST_ADDR"
    ;;
esac

# ---- 兜底：仍无设备则提示一次 ----------------------------------------------
if [ -z "${ADDR:-}" ]; then
  cat <<'HINT'
  未找到已连接设备。手机端请确认：
    1. 设置 → 更多设置 → 开发者选项 → 「无线调试」开关为开
    2. 手机保持解锁（HyperOS 锁屏 / Wi-Fi 切换会自动关闭）
    3. 查看「无线调试」主页面的 IP:端口

  然后执行（只输这一次，脚本会记住端口）：
    mobile-connect.sh <端口号>        # 例如 mobile-connect.sh 39959

  想长期免输端口：先连上后执行 mobile-connect.sh --tcpip
HINT
  exit 1
fi

LAST_ADDR="$ADDR"
IP="${ADDR%%:*}"
DEVICE_IP="$IP"
save_conf

# ---- 启动投屏 --------------------------------------------------------------
if scrcpy_running; then
  log "scrcpy 已在运行，不再重复启动（$ADDR）"
  exit 0
fi

# 按桌面可用高度决定窗口大小，不再用 --max-size 压缩视频流
# （竖屏手机 --max-size 1080 会把高度限到 1080、宽度只剩 ~486，窗口过窄）
read -r VW VH <<<"$(get_video_size "$ADDR")"
if [[ "${VW:-0}" -gt 0 && "${VH:-0}" -gt 0 ]]; then
  MC_W=$(( MC_H * VW / VH ))
else
  MC_W=$(( MC_H * 9 / 20 ))     # 回退：按 9:20 竖屏比例
fi
log "窗口: ${MC_W}x${MC_H}（视频源 ${VW:-?}x${VH:-?}，桌面逻辑 1536x960）"

log "启动投屏: $ADDR"
# --max-size 1920 只限制编码分辨率（864x1920），控制无线带宽；
# 窗口大小由 --window-* 独立决定，不会再被视频尺寸带小。
exec scrcpy -s "$ADDR" \
  --shortcut-mod=lctrl \
  --max-size=1920 --max-fps 60 --stay-awake \
  --window-width="$MC_W" --window-height="$MC_H" \
  --window-title "红米投屏 ($ADDR)"
