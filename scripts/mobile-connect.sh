#!/usr/bin/env bash
# ============================================================================
# mobile-connect.sh — 一键连接红米并投屏（免去每次手输长命令）
#
# 用法:
#   ./scripts/mobile-connect.sh              # 自动连接 + 投屏（用上次成功地址）
#   ./scripts/mobile-connect.sh 39959        # 端口变了：指定一次，之后自动记住
#   ./scripts/mobile-connect.sh 192.168.31.196:39959   # IP 也变了：写完整地址
#   ./scripts/mobile-connect.sh --tcpip      # 把设备切到固定 5555，此后长期免输端口
#   ./scripts/mobile-connect.sh --status     # 只看状态，不启动投屏
#   ./scripts/mobile-connect.sh --stop       # 断开连接
#   ./scripts/mobile-connect.sh --x11        # 用 XWayland 启动（scrcpy 拖放可用）
#   ./scripts/mobile-connect.sh --recover    # 手机重启后：插 USB 一键恢复固定 5555
#   ./scripts/mobile-connect.sh --scan       # 扫描本网段 5555（IP 变了也能找到）
#   ./scripts/mobile-connect.sh --port-prompt  # 交互填写 IP 与端口（启动器右键同名）
#
# 端口来源：HyperOS「无线调试」主页面显示的 IP:端口（会变，故支持记忆 + 单次覆盖）
# 注意：本机实测 adb mdns services 为空，HyperOS 不广播 ADB 服务，无法全自动发现端口。
# 根治思路：--recover 把端口固定为 5555（手机重启后重跑一次），IP 侧在路由器做
# DHCP 静态绑定；两者都固定后地址就再也不变。
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

# 窗口高度（逻辑像素）：环境变量 > 配置 > 自动（屏幕逻辑高 - 80）> 840
# 本机 GNOME 200% 缩放：物理 1920 / 2 = 960 逻辑，减顶栏与边距约 880。
# 覆盖：MC_HEIGHT=900 mobile-connect.sh
auto_height() {
  local ph dpi scale h
  ph="$(xrandr --current 2>/dev/null | awk '/ primary /{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+\+/){split($i,a,"x"); split(a[2],b,"+"); print b[1]; exit}}')"
  dpi="$(xrdb -query 2>/dev/null | awk -F'\t' '/Xft\.dpi/ {print int($2); exit}')"
  scale=$(( ${dpi:-96} / 96 ))
  [ "$scale" -ge 1 ] || scale=1
  if [ -n "$ph" ]; then
    # 只留顶栏 32 逻辑像素 + 8 边距，尽量占满屏幕
    h=$(( ph / scale - 40 ))
    [ "$h" -ge 480 ] && { echo "$h"; return; }
  fi
  echo 840
}

if [ -n "${MC_HEIGHT:-}" ]; then
  MC_H="$MC_HEIGHT"
elif [ -n "${WINDOW_HEIGHT:-}" ] && [ "${WINDOW_HEIGHT}" != "auto" ]; then
  MC_H="$WINDOW_HEIGHT"
else
  MC_H="$(auto_height)"
fi

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }
warn() { printf '  ! %s\n' "$*" | tee -a "$LOG"; }
die()  { printf '  x %s\n' "$*" | tee -a "$LOG" >&2; exit 1; }

save_conf() {
  cat >"$CONF" <<EOF
# 由 mobile-connect.sh 自动生成（$(date '+%F %T')）
DEVICE_IP="$DEVICE_IP"
LAST_ADDR="$LAST_ADDR"
# 投屏窗口高度（逻辑像素）：auto=按屏幕可用高度自动，或填具体数字
WINDOW_HEIGHT="${MC_HEIGHT:-auto}"
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

# 扫描本网段的 5555 端口（仅在设备已用 --recover 固定端口后有效）。
# HyperOS 不广播 mDNS，无法自动发现随机端口；把端口固定成 5555 后，
# 即使 IP 被 DHCP 换掉，也能靠扫描重新找到。
scan_5555() {
  local gw subnet found
  gw="$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')"
  [ -n "$gw" ] || return 1
  subnet="${gw%.*}"
  log "扫描 $subnet.0/24 的 5555 端口（最多约 8 秒）..."
  found="$(seq 1 254 | xargs -P 64 -I{} sh -c \
    "timeout 2 nc -z '$subnet'.{} 5555 2>/dev/null && echo '$subnet'.{}" 2>/dev/null | head -1)"
  [ -n "$found" ] || return 1
  log "发现设备: $found:5555"
  LAST_ADDR="$found:5555"
  DEVICE_IP="$found"
  try_connect "$LAST_ADDR"
}

# ---- 参数处理 --------------------------------------------------------------
# scrcpy 基于 SDL2，而 SDL2 的 Wayland 后端没有实现拖放（SDL_DROPFILE），
# 所以「拖文件进窗口」在原生 Wayland 下无反应；--x11 切到 XWayland 即可恢复。
MC_X11=0
_args=()
for _a in "$@"; do
  if [ "$_a" = "--x11" ]; then MC_X11=1; else _args+=("$_a"); fi
done
set -- "${_args[@]}"

ARG="${1:-}"

case "$ARG" in
  --status)
    adb devices -l
    scrcpy_running && echo 'scrcpy: 运行中' || echo 'scrcpy: 未运行'
    echo "已保存地址: ${LAST_ADDR:-无}"

    if [ -n "$LAST_ADDR" ]; then
      D_IP="${LAST_ADDR%%:*}"
      D_PORT="${LAST_ADDR##*:}"
      echo
      echo '诊断:'
      echo "  手机 IP : $D_IP"
      # HyperOS 默认丢弃 ICMP，先 ping 触发 ARP 解析，再看邻居表状态
      ping -c1 -W1 "$D_IP" >/dev/null 2>&1 || true
      D_ST="$(ip neigh show "$D_IP" 2>/dev/null | awk '{print $NF; exit}')"
      D_MAC="$(ip neigh show "$D_IP" 2>/dev/null | awk '/lladdr/ {print $5; exit}')"
      case "$D_ST" in
        REACHABLE|STALE|DELAY|PROBE)
          echo "  网络可达: 是${D_MAC:+（ARP $D_MAC）}" ;;
        *)
          echo "  网络可达: 否（${D_ST:-无 ARP 记录}）"
          echo '  结论: 手机不在同一 Wi-Fi、已关机，或 IP 变了'
          echo '  建议: 确认手机连着同一网络，并核对无线调试页面上的 IP'
          exit 0 ;;
      esac
      if timeout 2 bash -c "echo > /dev/tcp/$D_IP/$D_PORT" 2>/dev/null; then
        echo "  端口 $D_PORT: 开放"
        if [ -n "$(get_device)" ]; then
          echo '  结论: 连接正常'
        else
          echo '  结论: 端口开放但 adb 未完成握手'
          echo '  建议: 看手机是否弹出「允许调试」，或执行 mobile-connect.sh 重连'
        fi
      else
        echo "  端口 $D_PORT: 关闭"
        echo '  结论: 无线调试已关闭，或端口已变（HyperOS 每次重开都换端口）'
        echo '  建议: 手机打开「无线调试」后执行 mobile-connect.sh <新端口>'
      fi
    fi
    exit 0 ;;

  --stop)
    # 兜底：投屏被异常终止时 trap 可能没跑到，这里把息屏超时还原
    _tb="$HOME/.local/state/linux-tune/screen-timeout.bak"
    if [ -f "$_tb" ]; then
      _d="$(get_device)"
      if [ -n "$_d" ]; then
        adb -s "$_d" shell settings put system screen_off_timeout "$(cat "$_tb")" >/dev/null 2>&1
        warn "已恢复自动息屏（$(cat "$_tb")ms）"
      fi
      rm -f "$_tb"
    fi
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

  --recover)
    # 手机重启 / 重开无线调试后端口回到随机值，插一次 USB 即可恢复固定 5555。
    # 与 --tcpip 的区别：--tcpip 依赖「当前已有无线连接」，本命令走 USB 取 IP。
    USB_DEV="$(adb devices 2>/dev/null | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')"
    [ -n "$USB_DEV" ] || die '未检测到 USB 设备：请插线，并在手机弹窗中允许 USB 调试'
    log "检测到 USB 设备: $USB_DEV"
    IP="$(adb -s "$USB_DEV" shell ip -4 addr show wlan0 2>/dev/null \
      | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}' | tr -d '\r')"
    [ -n "$IP" ] || die '无法从设备读取 WLAN IP（确认手机已连 Wi-Fi）'
    log "手机 WLAN IP = $IP，切换到固定 5555..."
    adb -s "$USB_DEV" tcpip 5555 2>&1 | tee -a "$LOG"
    sleep 3
    DEVICE_IP="$IP"
    LAST_ADDR="$IP:5555"
    save_conf
    if try_connect "$LAST_ADDR"; then
      log "已固定为 $LAST_ADDR（手机重启后重跑 --recover 即可）"
    else
      warn "5555 连接失败：HyperOS 可能不响应 tcpip，请改用 <端口> 手动模式"
    fi
    exit 0 ;;

  --scan)
    if scan_5555; then
      log "扫描命中并已连接"
    else
      die '未发现 5555 设备：确认手机已 --recover 固定端口，且与本机同网段'
    fi
    exit 0 ;;

  --port-prompt)
    # 供桌面启动器调用：交互填写 IP 与端口，之后自动记住。
    # 端口每次重开无线调试都会变，IP 也可能被 DHCP 换掉，所以两项都给输入口；
    # 直接回车 = 沿用已记录的值。输入 q 取消。
    CUR_IP="${DEVICE_IP:-}"
    [ -z "$CUR_IP" ] && [ -n "${LAST_ADDR:-}" ] && CUR_IP="${LAST_ADDR%%:*}"
    CUR_PORT=""
    [ -n "${LAST_ADDR:-}" ] && CUR_PORT="${LAST_ADDR##*:}"

    cat <<'HINT'
  手机：设置 → 更多设置 → 开发者选项 → 无线调试
  打开「无线调试」，主页面上显示「IP 地址和端口」，按实际值填写。
  · 直接回车 = 沿用方括号里的值
  · 只输数字 = 视为「新端口」，IP 沿用（日常最常见）
  · 输入 q 取消
HINT
    printf '  IP 地址或新端口 [%s]: ' "${CUR_IP:-必填}"
    read -r IN1 || true
    [ "$IN1" = "q" ] && { log '已取消'; exit 0; }

    # 容错：只输纯数字时按端口处理。端口每次重开无线调试都会变，
    # 而 IP 很少动，用户往往只想填端口，不能把数字塞进 IP 校验。
    if [[ "$IN1" =~ ^[0-9]{2,5}$ ]]; then
      CUR_PORT="$IN1"
      log "识别为新端口 $CUR_PORT（IP 沿用 $CUR_IP）"
    else
      [ -n "$IN1" ] && CUR_IP="$IN1"
      [[ "${CUR_IP:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "IP 格式不正确: ${CUR_IP:-空}"

      printf '  端口 [%s]: ' "${CUR_PORT:-必填}"
      read -r IN2 || true
      [ "$IN2" = "q" ] && { log '已取消'; exit 0; }
      [ -n "$IN2" ] && CUR_PORT="$IN2"
      [[ "${CUR_PORT:-}" =~ ^[0-9]{2,5}$ ]] || die "端口应为 2~5 位数字: ${CUR_PORT:-空}"
    fi

    exec "$0" "$CUR_IP:$CUR_PORT"      # 交给地址分支连接并记住
    ;;

  '')
    # 自动模式：已有 device → 直接投屏；否则用上次地址重连
    ADDR="$(get_device)"
    if [ -z "$ADDR" ] && [ -n "$LAST_ADDR" ]; then
      try_connect "$LAST_ADDR" || true
      ADDR="$(get_device)"
    fi
    # 上次用的是固定 5555 ⇒ IP 可能被 DHCP 换掉，扫一遍网段兜底
    if [ -z "$ADDR" ] && [ "${LAST_ADDR##*:}" = "5555" ]; then
      scan_5555 && ADDR="$(get_device)"
    fi
    ;;

  *)
    # 支持两种写法：纯端口（沿用已记录 IP）或完整地址 IP:端口
    if [[ "$ARG" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{2,5}$ ]]; then
      IP="${ARG%%:*}"
      PORT="${ARG##*:}"
    else
      [[ "$ARG" =~ ^[0-9]{2,5}$ ]] || die "参数应为端口号(39959)或完整地址(192.168.31.196:39959)"
      PORT="$ARG"
      IP="${DEVICE_IP:-}"
      if [ -z "$IP" ] && [ -n "$LAST_ADDR" ]; then IP="${LAST_ADDR%%:*}"; fi
      if [ -z "$IP" ]; then
        warn '尚未记录手机 IP，请在下方输入手机无线调试页面显示的 IP'
        printf '  手机 IP (如 192.168.31.196): '
        read -r IP
        [ -n "$IP" ] || die '未输入 IP'
      fi
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
# SDL2 的 X11 后端按「物理像素」建窗，不像 Wayland 后端按逻辑坐标，
# 在 200% 缩放下会把 378x840 建成 378x840 物理像素（只占屏幕 12% 宽），
# 所以 --x11 模式要按 DPI 换算放大。
if [ "$MC_X11" = "1" ]; then
  _dpi="$(xrdb -query 2>/dev/null | awk -F'\t' '/Xft\.dpi/ {print int($2); exit}')"
  _scale=$(( ${_dpi:-96} / 96 ))
  [ "$_scale" -ge 1 ] || _scale=1
  MC_W=$(( MC_W * _scale ))
  MC_H=$(( MC_H * _scale ))
  log "XWayland 缩放 ×${_scale}（Xft.dpi ${_dpi:-96}）"
fi

log "窗口: ${MC_W}x${MC_H}（视频源 ${VW:-?}x${VH:-?}）"

if [ "$MC_X11" = "1" ]; then
  export SDL_VIDEODRIVER=x11
  log '视频后端: XWayland（拖放可用）'
fi

log "启动投屏: $ADDR"

# 无线投屏且未插电时，stay_on_while_plugged_in 不生效，
# 手机按 screen_off_timeout（本机 15000ms）息屏，画面随即变黑。
# 投屏期间把息屏超时拉满，退出（含 Ctrl+C）时恢复原值。
TIMEOUT_BAK="$HOME/.local/state/linux-tune/screen-timeout.bak"
restore_timeout() {
  [ -f "$TIMEOUT_BAK" ] || return 0
  local orig
  orig="$(cat "$TIMEOUT_BAK")"
  adb -s "$ADDR" shell settings put system screen_off_timeout "$orig" >/dev/null 2>&1
  rm -f "$TIMEOUT_BAK"
  log "已恢复自动息屏（${orig}ms）"
}
trap restore_timeout EXIT INT TERM

mkdir -p "$(dirname "$TIMEOUT_BAK")"
adb -s "$ADDR" shell settings get system screen_off_timeout 2>/dev/null | tr -d '\r' >"$TIMEOUT_BAK"
if adb -s "$ADDR" shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1; then
  log "投屏期间已关闭自动息屏（原值 $(cat "$TIMEOUT_BAK" 2>/dev/null)ms，退出后恢复）"
else
  warn "设置息屏超时失败，手机仍可能自动锁屏"
fi

# --max-size 1920 只限制编码分辨率（864x1920），控制无线带宽；
# 窗口大小由 --window-* 独立决定，不会再被视频尺寸带小。
# 这里不用 exec，否则 trap 会随进程替换丢失、息屏超时无法恢复。
#
# 主机侧常亮：GNOME 默认 idle-delay=300s 会直接把笔记本屏幕熄掉并锁屏，
# 用户盯着手机画面不动键盘时，看起来就像「投屏自己熄屏」。
# 用 systemd-inhibit 在投屏期间阻止 idle 与 suspend，退出自动释放。
SCRCPY_ARGS=(
  -s "$ADDR"
  --shortcut-mod=lctrl
  --max-size=1920 --max-fps 60 --stay-awake
  --window-width="$MC_W" --window-height="$MC_H"
  --window-title "红米投屏 ($ADDR)"
)
[ "${MC_FULLSCREEN:-0}" = "1" ] && SCRCPY_ARGS+=(--fullscreen)

if command -v systemd-inhibit >/dev/null 2>&1; then
  log '已禁止主机空闲熄屏（systemd-inhibit idle:sleep）'
  systemd-inhibit --what=idle:sleep --who="SuonaOS 投屏" \
    --why="投屏期间保持屏幕常亮" scrcpy "${SCRCPY_ARGS[@]}"
else
  warn 'systemd-inhibit 不可用，主机仍可能在 idle-delay 后熄屏'
  scrcpy "${SCRCPY_ARGS[@]}"
fi
