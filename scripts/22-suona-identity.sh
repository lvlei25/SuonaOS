#!/usr/bin/env bash
# ============================================================================
# 22-suona-identity.sh - SuonaOS 视觉令牌落地（用户级，可回滚）
#
# 定位：不做 macOS 外观克隆（ADR-36）。只收口四件事：
#   1) 强调色：木腔/黄铜取向，优先 brown → orange → yellow，由 GNOME 支持集决定
#   2) 窗口按钮：统一回到右侧（当前残留 WhiteSur 的左置 close,minimize,maximize:）
#   3) 光标：收敛到系统原生 Yaru，并把 WhiteSur-cursors 移入备份（不直接删）
#   4) 圆角梯度：只校验 15-rounding.sh 的令牌是否为 14/18/20，不改别人的参数
#
# 用法:
#   ./scripts/22-suona-identity.sh --install            # 落地（幂等）
#   ./scripts/22-suona-identity.sh --install --dry-run  # 只打印将做什么
#   ./scripts/22-suona-identity.sh --accent orange      # 指定强调色（需在支持集内）
#   ./scripts/22-suona-identity.sh --status
#   ./scripts/22-suona-identity.sh --restore            # 按备份回滚三项 gsettings
#
# 只改用户级 gsettings 与 ~/.local/share/icons，不碰系统目录。
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="$HOME/.config/linux-tune/identity.conf"
ROUND_CONF="$HOME/.config/linux-tune/rounding.conf"
WANT_ACCENT=""
ACTION=""
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install) ACTION=install ;;
    --status)  ACTION=status ;;
    --restore) ACTION=restore ;;
    --dry-run) DRY=1 ;;
    --accent)  WANT_ACCENT="${2:-}"; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=install

# 记录原值，供 --restore 精确回滚
ORIG_ACCENT=""; ORIG_BUTTONS=""; ORIG_CURSOR=""; ORIG_CURSOR_SIZE=""
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

has_iface_key() { gsettings list-keys org.gnome.desktop.interface 2>/dev/null | grep -qx "$1"; }

# 支持集由 gsettings range 决定，不硬编码枚举值
accent_options() {
  gsettings range org.gnome.desktop.interface accent-color 2>/dev/null \
    | tail -n +2 | tr -d "'"
}

cur() { gsettings get "$1" "$2" 2>/dev/null | tr -d "'"; }

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  echo
  echo "════════ SuonaOS 视觉令牌 ════════"
  if has_iface_key accent-color; then
    echo "  强调色      : $(cur org.gnome.desktop.interface accent-color)"
  else
    echo "  强调色      : 本机 GNOME 不支持 accent-color（跳过，不伪造）"
  fi
  echo "  窗口按钮    : $(cur org.gnome.desktop.wm.preferences button-layout)"
  echo "  光标        : $(cur org.gnome.desktop.interface cursor-theme) / $(cur org.gnome.desktop.interface cursor-size)px"
  echo "  图标        : $(cur org.gnome.desktop.interface icon-theme)"
  echo "  GTK         : $(cur org.gnome.desktop.interface gtk-theme)"
  if [ -f "$ROUND_CONF" ]; then
    # shellcheck disable=SC1090
    R=$(bash -c '. "$1"; echo "$RADIUS"' _ "$ROUND_CONF" 2>/dev/null)
    echo "  圆角令牌    : ${R:-?}px（梯度 14 / 18 / 20，见 docs/21）"
  else
    echo "  圆角令牌    : 未安装（15-rounding.sh 未运行）"
  fi
  if [ -d "$HOME/.local/share/icons/WhiteSur-cursors" ]; then
    echo "  残留        : WhiteSur-cursors 仍在（--install 会移入 backup/）"
  else
    echo "  残留        : 无 WhiteSur 光标"
  fi
  echo "  配置文件    : $([ -f "$CONF" ] && echo "$CONF" || echo 未创建)"
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  if has_iface_key accent-color && [ -n "$ORIG_ACCENT" ]; then
    gsettings set org.gnome.desktop.interface accent-color "$ORIG_ACCENT" \
      && ok "强调色恢复为 $ORIG_ACCENT"
  fi
  if [ -n "$ORIG_BUTTONS" ]; then
    gsettings set org.gnome.desktop.wm.preferences button-layout "$ORIG_BUTTONS" \
      && ok "窗口按钮恢复为 $ORIG_BUTTONS"
  else
    gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' \
      && ok "窗口按钮恢复为 Ubuntu 默认（右侧）"
  fi
  if [ -n "$ORIG_CURSOR" ]; then
    gsettings set org.gnome.desktop.interface cursor-theme "$ORIG_CURSOR" \
      && ok "光标恢复为 $ORIG_CURSOR"
  fi
  [ -n "$ORIG_CURSOR_SIZE" ] && gsettings set org.gnome.desktop.interface cursor-size "$ORIG_CURSOR_SIZE"

  # 把移入备份的 WhiteSur-cursors 放回原处（只放回自己移走的）
  BAK=$(ls -dt "$BACKUP_DIR"/*/dirs"$HOME"/.local/share/icons/WhiteSur-cursors 2>/dev/null | head -1)
  if [ -n "$BAK" ] && [ ! -d "$HOME/.local/share/icons/WhiteSur-cursors" ]; then
    mkdir -p "$HOME/.local/share/icons"
    mv "$BAK" "$HOME/.local/share/icons/WhiteSur-cursors" \
      && ok "WhiteSur-cursors 已从 ${BAK#$PROJECT_ROOT/} 放回"
  fi
  rm -f "$CONF"
  ok "视觉令牌已回滚（圆角由 15-rounding.sh --restore 单独管理）"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/4 选择强调色（木腔/黄铜取向）"
ACCENT=""
if has_iface_key accent-color; then
  OPTIONS="$(accent_options)"
  if [ -n "$WANT_ACCENT" ]; then
    echo "$OPTIONS" | grep -qx "$WANT_ACCENT" \
      || die "本机不支持强调色 '$WANT_ACCENT'，可选: $(echo "$OPTIONS" | tr '\n' ' ')"
    ACCENT="$WANT_ACCENT"
  else
    for c in brown orange yellow; do
      if echo "$OPTIONS" | grep -qx "$c"; then ACCENT="$c"; break; fi
    done
  fi
  [ -n "$ACCENT" ] || { ACCENT="$(echo "$OPTIONS" | head -1)"; warn "预设色不在支持集内，回退首个可用值"; }
  info="强调色候选: $(echo "$OPTIONS" | tr '\n' ' ')"
  log "$info"
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] gsettings set org.gnome.desktop.interface accent-color $ACCENT"
  else
    [ -z "$ORIG_ACCENT" ] && ORIG_ACCENT="$(cur org.gnome.desktop.interface accent-color)"
    gsettings set org.gnome.desktop.interface accent-color "$ACCENT" \
      && ok "强调色 → $ACCENT"
  fi
else
  warn "本机 GNOME 无 accent-color 键：跳过强调色，不伪造效果（设计需退回 Yaru 默认强调色）"
fi

step "2/4 窗口按钮统一回到右侧"
[ -z "$ORIG_BUTTONS" ] && ORIG_BUTTONS="$(cur org.gnome.desktop.wm.preferences button-layout)"
if [ "$ORIG_BUTTONS" = "close,minimize,maximize:" ]; then
  # 这是 WhiteSur 遗留的左置布局，必须清掉
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] button-layout → ':minimize,maximize,close'（原值 $ORIG_BUTTONS 已记录）"
  else
    gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close' \
      && ok "按钮布局 → ':minimize,maximize,close'（原 $ORIG_BUTTONS）"
  fi
else
  ok "按钮布局已是 $(cur org.gnome.desktop.wm.preferences button-layout)，无需改动"
fi

step "3/4 光标收敛到系统原生"
[ -z "$ORIG_CURSOR" ] && ORIG_CURSOR="$(cur org.gnome.desktop.interface cursor-theme)"
[ -z "$ORIG_CURSOR_SIZE" ] && ORIG_CURSOR_SIZE="$(cur org.gnome.desktop.interface cursor-size)"
if echo "$ORIG_CURSOR" | grep -qi WhiteSur; then
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] cursor-theme → Yaru"
  else
    gsettings set org.gnome.desktop.interface cursor-theme 'Yaru' && ok "光标 → Yaru"
  fi
else
  ok "光标已是 $ORIG_CURSOR"
fi

WS="$HOME/.local/share/icons/WhiteSur-cursors"
if [ -d "$WS" ]; then
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] 移入 $BACKUP_DIR/$RUN_ID/dirs$HOME/.local/share/icons/"
  else
    DST="$BACKUP_DIR/$RUN_ID/dirs$HOME/.local/share/icons"
    mkdir -p "$DST"
    mv "$WS" "$DST/" && ok "WhiteSur-cursors 已移入 ${DST#$PROJECT_ROOT/}（--restore 可放回）"
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$WS" "$RUN_ID/dirs$HOME/.local/share/icons/WhiteSur-cursors" >>"$MANIFEST"
  fi
else
  ok "无 WhiteSur-cursors 残留"
fi

step "4/4 校验圆角梯度"
if [ -f "$ROUND_CONF" ]; then
  R=$(bash -c '. "$1"; echo "$RADIUS"' _ "$ROUND_CONF" 2>/dev/null)
  case "$R" in
    14) ok "圆角令牌 ${R}px（14 / 18 / 20 梯度，符合 docs/21）" ;;
    *)  warn "圆角为 ${R}px，与令牌梯度基线 14px 不一致；如非有意，跑 15-rounding.sh --install" ;;
  esac
else
  warn "未安装圆角覆盖层；视觉令牌只剩配色与按钮布局（跑 15-rounding.sh --install）"
fi

if [ "$DRY" -eq 0 ]; then
  mkdir -p "$(dirname "$CONF")"
  {
    printf '# 由 22-suona-identity.sh 生成（%s）\n' "$(date '+%F %T')"
    printf 'ORIG_ACCENT=%q\n' "${ORIG_ACCENT:-}"
    printf 'ORIG_BUTTONS=%q\n' "${ORIG_BUTTONS:-}"
    printf 'ORIG_CURSOR=%q\n' "${ORIG_CURSOR:-}"
    printf 'ORIG_CURSOR_SIZE=%q\n' "${ORIG_CURSOR_SIZE:-}"
    printf 'ACCENT=%q\n' "${ACCENT:-}"
  } >"$CONF"
  ok "原值已记录: ${CONF/#$HOME/~}"
fi

echo
log "查看: $0 --status    回滚: $0 --restore"
log "设计规范: docs/21-SuonaOS视觉语言.md（禁止项：红绿灯按钮 / 全局菜单 / Launchpad 仿制）"
