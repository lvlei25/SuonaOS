#!/usr/bin/env bash
# ============================================================================
# 10-wallpaper-water.sh - 水系壁纸轮换
#   扫描 ~/Pictures/Wallpapers/water/final/*.jpg，生成 GNOME 动态壁纸 XML 并设为桌面背景
#   图片本身不由此脚本下载（授权各异的素材应由人工确认），只负责轮换与设置
# 用法:
#   ./scripts/10-wallpaper-water.sh                 # 默认每 30 分钟
#   ./scripts/10-wallpaper-water.sh --interval 600  # 每 10 分钟
#   ./scripts/10-wallpaper-water.sh --list          # 只查看当前配置
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WALL_DIR="$HOME/Pictures/Wallpapers/water"
IMG_DIR="$WALL_DIR/final"
XML="$WALL_DIR/water-cycle.xml"
INTERVAL=1800
ACTION=apply

while [ $# -gt 0 ]; do
  case "$1" in
    --interval) INTERVAL="${2:-1800}"; shift ;;
    --list) ACTION=list ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

if [ "$ACTION" = list ]; then
  echo "壁纸目录: $WALL_DIR"
  echo "图片数量: $(ls -1 "$IMG_DIR"/*.jpg 2>/dev/null | wc -l)"
  echo "XML     : $XML"
  echo "当前 URI: $(gsettings get org.gnome.desktop.background picture-uri)"
  echo "轮换间隔: $(grep -m1 '<duration>' "$XML" 2>/dev/null | tr -dc '0-9.') 秒"
  exit 0
fi

# ---- 1. 检查图片 -----------------------------------------------------------
step "1/3 检查壁纸图片"
mapfile -t IMGS < <(ls -1 "$IMG_DIR"/*.jpg 2>/dev/null | sort)
[ "${#IMGS[@]}" -ge 2 ] || die "至少需要 2 张图：$IMG_DIR/*.jpg（当前 ${#IMGS[@]} 张）"
ok "找到 ${#IMGS[@]} 张：$(for f in "${IMGS[@]}"; do printf '%s ' "$(basename "$f")"; done)"

# ---- 2. 生成轮换 XML -------------------------------------------------------
step "2/3 生成轮换配置（每 $((INTERVAL/60)) 分钟，过渡 3 秒）"
mkdir -p "$WALL_DIR"
{
  printf '<background>\n  <starttime>\n'
  printf '    <year>%s</year><month>%s</month><day>%s</day>\n' "$(date +%Y)" "$(date +%m)" "$(date +%d)"
  printf '    <hour>0</hour><minute>0</minute><second>0</second>\n  </starttime>\n'
  for i in "${!IMGS[@]}"; do
    f="${IMGS[$i]}"
    nxt="${IMGS[$(( (i + 1) % ${#IMGS[@]} ))]}"
    printf '  <static>\n    <duration>%d.0</duration>\n    <file>%s</file>\n  </static>\n' "$INTERVAL" "$f"
    printf '  <transition>\n    <duration>3.0</duration>\n    <from>%s</from>\n    <to>%s</to>\n  </transition>\n' "$f" "$nxt"
  done
  printf '</background>\n'
} >"$XML"
ok "已写入 ${XML#$HOME/}（末张自动回到首张，循环）"

# ---- 3. 应用 ---------------------------------------------------------------
step "3/3 设为桌面背景"
URI="file://$XML"
gsettings set org.gnome.desktop.background picture-uri "$URI"
gsettings set org.gnome.desktop.background picture-uri-dark "$URI"
gsettings set org.gnome.desktop.background picture-options 'zoom'
ok "深/浅色桌面均已指向轮换 XML"

echo
log "当前: $(gsettings get org.gnome.desktop.background picture-uri)"
warn "新增图片后重跑本脚本即可；图片授权信息请记入 $WALL_DIR/CREDITS.txt"
log "查看: $0 --list"
