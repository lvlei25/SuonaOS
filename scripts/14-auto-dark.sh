#!/usr/bin/env bash
# ============================================================================
# 14-auto-dark.sh - 按当地日出日落自动切换深色 / 浅色
#   日落之后 → prefer-dark + Yaru-prussiangreen-dark
#   日出之后 → default     + Yaru-prussiangreen
#   日出日落由 NOAA 简化算法本地计算，不联网、不依赖 geoclue
# 用法:
#   ./scripts/14-auto-dark.sh --install          # 装 timer（每 10 分钟检查）
#   ./scripts/14-auto-dark.sh --status           # 经纬度、日出日落、当前模式
#   ./scripts/14-auto-dark.sh --check            # 单次检查（timer 调用）
#   ./scripts/14-auto-dark.sh --force dark       # 立即切深色（light 反之）
#   ./scripts/14-auto-dark.sh --restore          # 停 timer 并回浅色
#   ./scripts/14-auto-dark.sh --lat 39.9 --lon 116.4   # 换城市
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="$HOME/.config/linux-tune/auto-dark.conf"
STATE_DIR="$HOME/.local/state/linux-tune"
STATE="$STATE_DIR/auto-dark.state"
UNIT_DIR="$HOME/.config/systemd/user"
SVC="suona-auto-dark.service"
TMR="suona-auto-dark.timer"

# 默认上海；--lat/--lon 或配置文件可覆盖
LAT="31.2304"; LON="121.4737"; CITY="上海"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

DARK_SCHEME="prefer-dark";  LIGHT_SCHEME="default"
DARK_THEME="Yaru-prussiangreen-dark"
LIGHT_THEME="Yaru-prussiangreen"

ACTION=""
FORCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --install) ACTION=install ;;
    --status)  ACTION=status ;;
    --check)   ACTION=check ;;
    --restore) ACTION=restore ;;
    --force)   ACTION=force; FORCE="${2:-}"; shift ;;
    --lat)     LAT="${2:-}";  shift ;;
    --lon)     LON="${2:-}";  shift ;;
    --city)    CITY="${2:-}"; shift ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=check

# 本地计算日出日落（NOAA 简化算法），输出 "日出 日落" 的 HH:MM
sun_times() {
  python3 - "$LAT" "$LON" <<'PY'
import math, sys, datetime
lat, lon = float(sys.argv[1]), float(sys.argv[2])
tz = datetime.datetime.now().astimezone().utcoffset().total_seconds() / 3600.0
day = datetime.date.today()
n = day.timetuple().tm_yday

def event(is_rise):
    lng_hour = lon / 15.0
    t = n + ((6 - lng_hour) / 24 if is_rise else (18 - lng_hour) / 24)
    M = (0.9856 * t) - 3.289
    L = M + 1.916 * math.sin(math.radians(M)) + 0.020 * math.sin(math.radians(2 * M)) + 282.634
    L %= 360
    RA = math.degrees(math.atan(0.91764 * math.tan(math.radians(L)))) % 360
    RA += (math.floor(L / 90) * 90) - (math.floor(RA / 90) * 90)
    RA /= 15.0
    sin_dec = 0.39782 * math.sin(math.radians(L))
    cos_dec = math.cos(math.asin(sin_dec))
    zenith = 90.833
    cos_h = ((math.cos(math.radians(zenith)) - sin_dec * math.sin(math.radians(lat)))
             / (cos_dec * math.cos(math.radians(lat))))
    if cos_h > 1 or cos_h < -1:
        return None
    H = (360 - math.degrees(math.acos(cos_h))) if is_rise else math.degrees(math.acos(cos_h))
    T = (H / 15.0) + RA - 0.06571 * t - 6.622
    return ((T - lng_hour) + tz) % 24

def fmt(h):
    if h is None:
        return "N/A"
    hh = int(h); mm = int(round((h - hh) * 60))
    if mm == 60:
        hh = (hh + 1) % 24; mm = 0
    return f"{hh:02d}:{mm:02d}"

print(fmt(event(True)), fmt(event(False)))
PY
}

current_mode() {
  local rise set now
  read -r rise set <<<"$(sun_times)"
  if [ "$rise" = "N/A" ] || [ "$set" = "N/A" ]; then
    echo ""; return    # 极昼极夜，不切换
  fi
  now=$(date +%s)
  local r s
  r=$(date -d "today $rise" +%s 2>/dev/null) || { echo ""; return; }
  s=$(date -d "today $set" +%s 2>/dev/null)  || { echo ""; return; }
  if [ "$now" -ge "$r" ] && [ "$now" -lt "$s" ]; then echo light; else echo dark; fi
}

apply_mode() {
  local mode="$1" scheme theme
  if [ "$mode" = dark ]; then scheme=$DARK_SCHEME; theme=$DARK_THEME
  else scheme=$LIGHT_SCHEME; theme=$LIGHT_THEME; fi
  gsettings set org.gnome.desktop.interface color-scheme "$scheme" \
    && gsettings set org.gnome.desktop.interface gtk-theme "$theme" \
    && ok "已切换 $mode（$scheme / $theme）"
}

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  read -r rise set <<<"$(sun_times)"
  echo "城市      : $CITY（$LAT, $LON）"
  echo "日出/日落 : $rise / $set"
  echo "应有模式  : $(current_mode)"
  echo "color-scheme: $(gsettings get org.gnome.desktop.interface color-scheme)"
  echo "gtk-theme   : $(gsettings get org.gnome.desktop.interface gtk-theme)"
  tmr_en="$(systemctl --user is-enabled "$TMR" 2>/dev/null)"
  tmr_act="$(systemctl --user is-active "$TMR" 2>/dev/null)"
  echo "timer     : ${tmr_en:-未安装} / ${tmr_act:-inactive}"
  echo "上次记录  : $(cat "$STATE" 2>/dev/null || echo 无)"
  exit 0
fi

# ---- force -----------------------------------------------------------------
if [ "$ACTION" = force ]; then
  case "$FORCE" in
    dark|light) apply_mode "$FORCE"; mkdir -p "$STATE_DIR"; echo "$FORCE" >"$STATE" ;;
    *) die "用法: --force dark|light" ;;
  esac
  exit 0
fi

# ---- check（timer 调用，静默、幂等）----------------------------------------
if [ "$ACTION" = check ]; then
  mode="$(current_mode)"
  [ -z "$mode" ] && exit 0
  prev="$(cat "$STATE" 2>/dev/null)"
  [ "$mode" = "$prev" ] && exit 0          # 状态未变，不重复写 gsettings
  mkdir -p "$STATE_DIR"
  apply_mode "$mode"
  echo "$mode" >"$STATE"
  exit 0
fi

# ---- install ---------------------------------------------------------------
if [ "$ACTION" = install ]; then
  step "1/2 保存位置配置"
  mkdir -p "$(dirname "$CONF")"
  printf '# 由 14-auto-dark.sh 生成（%s）\nLAT="%s"\nLON="%s"\nCITY="%s"\n' \
    "$(date '+%F %T')" "$LAT" "$LON" "$CITY" >"$CONF"
  ok "$CITY（$LAT, $LON） → ${CONF#$HOME/}"

  step "2/2 安装 systemd user timer（每 10 分钟检查）"
  mkdir -p "$UNIT_DIR" "$STATE_DIR"
  cat >"$UNIT_DIR/$SVC" <<EOF
[Unit]
Description=SuonaOS 日落自动深色

[Service]
Type=oneshot
ExecStart=$PROJECT_ROOT/scripts/14-auto-dark.sh --check
EOF
  cat >"$UNIT_DIR/$TMR" <<EOF
[Unit]
Description=SuonaOS 日落自动深色（每 10 分钟）

[Timer]
OnBootSec=45
OnUnitActiveSec=600
AccuracySec=30

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$TMR" || die "启用 $TMR 失败"
  ok "$TMR 已启用（$(systemctl --user is-active "$TMR")）"
  echo
  log "当前应有模式: $(current_mode)（$(date +%T)）"
  log "立即生效一次: $0 --check    查看状态: $0 --status"
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  systemctl --user disable --now "$TMR" 2>/dev/null && ok "已停用 $TMR" || warn "$TMR 未运行"
  rm -f "$UNIT_DIR/$TMR" "$UNIT_DIR/$SVC"
  systemctl --user daemon-reload
  rm -f "$STATE"
  gsettings set org.gnome.desktop.interface color-scheme "$LIGHT_SCHEME"
  gsettings set org.gnome.desktop.interface gtk-theme "$LIGHT_THEME"
  ok "已回浅色（$LIGHT_SCHEME / $LIGHT_THEME），timer 与状态已清理"
  exit 0
fi
