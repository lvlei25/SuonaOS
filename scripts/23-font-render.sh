#!/usr/bin/env bash
# ============================================================================
# 23-font-render.sh - 字体渲染参数（只调渲染，不换字体族）
#
# 为什么单独做：观感差异的大头不在换字体，而在 hinting / 抗锯齿 / 次像素。
# REQ-06 已按 ADR-26 定为「保留系统默认字体」，所以这里只改渲染参数，
# 字体族、字号、gsettings 的 font-name 一律不动。
#
# 落盘位置：~/.config/fontconfig/conf.d/99-suona-render.conf
#   刻意不用 ~/.config/fontconfig/fonts.conf：
#   99-verify 的「回退态」断言依赖该文件不存在，另建文件可避免互相踩（ADR-21）。
#
# 诚实边界：GNOME Wayland 下多数应用走灰度抗锯齿，rgba 只在 XWayland / 部分
#   GTK3 场景生效。脚本照写，但文档明确「以截图对比为准，不宣称必然生效」。
#
# 用法:
#   ./scripts/23-font-render.sh --install                 # 默认 sharp（hintslight + rgb）
#   ./scripts/23-font-render.sh --install --hintstyle hintslight|hintfull|none
#   ./scripts/23-font-render.sh --install --rgba rgb|bgr|none
#   ./scripts/23-font-render.sh --status
#   ./scripts/23-font-render.sh --restore
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF_DIR="$HOME/.config/fontconfig/conf.d"
CONF="$CONF_DIR/99-suona-render.conf"
ACTION=""
HINTSTYLE="hintslight"
RGBA="rgb"
LCDFILTER="lcddefault"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install)   ACTION=install ;;
    --status)    ACTION=status ;;
    --restore)   ACTION=restore ;;
    --dry-run)   DRY=1 ;;
    --hintstyle) HINTSTYLE="${2:-}"; shift ;;
    --rgba)      RGBA="${2:-}"; shift ;;
    --lcdfilter) LCDFILTER="${2:-}"; shift ;;
    -h|--help)   sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=install

case "$HINTSTYLE" in hintslight|hintmedium|hintfull|none) ;; *) die "--hintstyle 取值非法: $HINTSTYLE" ;; esac
case "$RGBA" in rgb|bgr|vrgb|vbgr|none) ;; *) die "--rgba 取值非法: $RGBA" ;; esac
case "$LCDFILTER" in lcdnone|lcddefault|lcdlight|lcdlegacy) ;; *) die "--lcdfilter 取值非法: $LCDFILTER" ;; esac

if [ "$ACTION" = status ]; then
  echo
  echo "════════ 字体渲染 ════════"
  echo "  字体族      : $(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")（不改）"
  echo "  等宽字体    : $(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null | tr -d "'")（不改）"
  if [ -f "$CONF" ]; then
    echo "  渲染覆盖层  : $CONF"
    echo "  参数        : $(grep -oE '<const>[a-z]+</const>' "$CONF" | sed 's/<[^>]*>//g' | tr '\n' ' ')"
  else
    echo "  渲染覆盖层  : 未安装（使用 fontconfig 系统默认）"
  fi
  echo "  实际匹配    : $(fc-match -f '%{family} hintstyle=%{hintstyle} rgba=%{rgba} antialias=%{antialias}' 'Adwaita Sans' 2>/dev/null)"
  echo "  中文字体    : $(fc-match -f '%{family}' 'sans-serif:lang=zh-cn' 2>/dev/null)"
  exit 0
fi

if [ "$ACTION" = restore ]; then
  if [ -f "$CONF" ] && grep -q 'SuonaOS' "$CONF" 2>/dev/null; then
    rm -f "$CONF" && ok "已删除 $CONF"
    fc-cache -f >/dev/null 2>&1 && ok "字体缓存已刷新"
  elif [ -e "$CONF" ]; then
    warn "$CONF 不是本脚本生成，未删除"
  else
    ok "没有需要回滚的渲染覆盖层"
  fi
  ok "渲染参数回到系统默认（字体族本来就未改动）"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/3 写入 fontconfig 覆盖层"
XML_ANTIALIAS=true
XML_HINTING=true
[ "$HINTSTYLE" = none ] && XML_HINTING=false

CONTENT="<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">
<!-- SuonaOS 字体渲染覆盖层，由 scripts/23-font-render.sh 生成
     只调渲染参数，不指定 family / size；字体族保持系统默认（ADR-26）
     回滚: 运行 23-font-render.sh 的 restore 子命令
     注意：XML 注释内不能出现两个连续的减号，改注释时别写成长参数形式
-->
<fontconfig>
  <match target=\"font\">
    <edit name=\"antialias\" mode=\"assign\"><bool>${XML_ANTIALIAS}</bool></edit>
    <edit name=\"hinting\" mode=\"assign\"><bool>${XML_HINTING}</bool></edit>
    <edit name=\"hintstyle\" mode=\"assign\"><const>${HINTSTYLE}</const></edit>
    <edit name=\"rgba\" mode=\"assign\"><const>${RGBA}</const></edit>
    <edit name=\"lcdfilter\" mode=\"assign\"><const>${LCDFILTER}</const></edit>
    <edit name=\"autohint\" mode=\"assign\"><bool>false</bool></edit>
    <edit name=\"embeddedbitmap\" mode=\"assign\"><bool>false</bool></edit>
  </match>
</fontconfig>
"

if [ "$DRY" -eq 1 ]; then
  log "[dry-run] 将写入 $CONF"
  printf '%s' "$CONTENT" | sed 's/^/    /'
else
  mkdir -p "$CONF_DIR"
  [ -f "$CONF" ] && backup_file "$CONF"
  printf '%s' "$CONTENT" >"$CONF"
  ok "$CONF"
fi

step "2/3 校验 XML 语法"
# 不用 xmllint：fontconfig 的 DOCTYPE 指向 urn:fontconfig:fonts.dtd，
# xmllint 会尝试解析外部实体并失败（离线机器必红）。python 的 expat 不取外部 DTD，
# 更适合做"只看格式"的校验。
if command -v python3 >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] python3 minidom 校验（跳过实际校验）"
  elif python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$CONF" 2>/dev/null; then
    ok "XML 语法正确"
  else
    rm -f "$CONF"
    die "生成的 XML 不合法，已删除（不会留下坏配置）"
  fi
else
  warn "缺少 python3，跳过 XML 校验（不影响使用）"
fi

step "3/3 刷新字体缓存"
if [ "$DRY" -eq 1 ]; then
  log "[dry-run] fc-cache -f"
else
  fc-cache -f >/dev/null 2>&1 && ok "fc-cache 已刷新"
fi

echo
if [ "$DRY" -eq 0 ]; then
  log "实际匹配: $(fc-match -f '%{family} hintstyle=%{hintstyle} rgba=%{rgba}' 'Adwaita Sans' 2>/dev/null)"
  log "已打开的应用需重开才生效（fontconfig 在进程启动时读取）"
fi
log "对比方法与误区见 docs/22-字体渲染.md；回滚: $0 --restore"
