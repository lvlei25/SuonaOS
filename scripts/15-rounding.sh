#!/usr/bin/env bash
# ============================================================================
# 15-rounding.sh - GTK 窗口/弹层圆角覆盖层
#   写 ~/.config/gtk-4.0/gtk.css 与 ~/.config/gtk-3.0/gtk.css
#   注意：GTK4 的覆盖层不再 @import gtk-Dark.css，否则 libadwaita 永远暗色，
#         会让 14-auto-dark.sh 的日落切换失效（旧软链已按 ADR-30 移除）
# 用法:
#   ./scripts/15-rounding.sh --install              # 默认 14px
#   ./scripts/15-rounding.sh --install --radius 18  # 自定义圆角
#   ./scripts/15-rounding.sh --status
#   ./scripts/15-rounding.sh --restore              # 删除覆盖层
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="$HOME/.config/linux-tune/rounding.conf"
GTK4_DIR="$HOME/.config/gtk-4.0"
GTK3_DIR="$HOME/.config/gtk-3.0"
SHELL_THEME="Suona-Round"
SHELL_CSS="$HOME/.themes/$SHELL_THEME/gnome-shell/gnome-shell.css"
RADIUS=14
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) ACTION=install ;;
    --status)  ACTION=status ;;
    --restore) ACTION=restore ;;
    --radius)  RADIUS="${2:-14}"; shift ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=install

case "$RADIUS" in
  ''|*[!0-9]*) die "--radius 必须是整数，收到: $RADIUS" ;;
esac

if [ "$ACTION" = status ]; then
  echo "圆角      : ${RADIUS}px"
  for f in "$GTK4_DIR/gtk.css" "$GTK3_DIR/gtk.css"; do
    if [ -L "$f" ]; then
      echo "$f → 软链（$(readlink "$f")）"
    elif [ -f "$f" ]; then
      echo "$f → 存在（$(wc -l <"$f") 行）"
    else
      echo "$f → 不存在（使用主题默认）"
    fi
  done
  echo "当前 gtk-theme: $(gsettings get org.gnome.desktop.interface gtk-theme)"
  st="$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | tr -d "'")"
  echo "Shell 主题: ${st:-默认}（$([ -f "$SHELL_CSS" ] && echo 覆盖层就绪 || echo 未创建)）"
  exit 0
fi

if [ "$ACTION" = restore ]; then
  for f in "$GTK4_DIR/gtk.css" "$GTK3_DIR/gtk.css"; do
    if [ -f "$f" ] && grep -q 'SuonaOS' "$f" 2>/dev/null; then
      rm -f "$f" && ok "已删除 $f"
    elif [ -e "$f" ]; then
      warn "跳过 $f（不是本脚本生成，未删除）"
    fi
  done
  st="$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | tr -d "'")"
  if [ "$st" = "$SHELL_THEME" ]; then
    gsettings set org.gnome.shell.extensions.user-theme name ''
    ok "Shell 主题已恢复默认"
  fi
  rm -f "$SHELL_CSS"
  rmdir "$(dirname "$SHELL_CSS")" "$(dirname "$(dirname "$SHELL_CSS")")" 2>/dev/null || true
  rm -f "$CONF"
  ok "圆角覆盖层已移除，GTK 与 Shell 回到主题默认值"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/3 备份现有 gtk.css"
mkdir -p "$BACKUP_DIR/$RUN_ID/files$GTK4_DIR" "$BACKUP_DIR/$RUN_ID/files$GTK3_DIR"
for f in "$GTK4_DIR/gtk.css" "$GTK3_DIR/gtk.css"; do
  if [ -e "$f" ]; then
    cp -a "$f" "$BACKUP_DIR/$RUN_ID/files$f" 2>/dev/null && ok "已备份 $f"
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$f" "$RUN_ID/files$f" >>"$MANIFEST"
  fi
done

step "2/3 写入 GTK4 覆盖层（跟随 color-scheme + ${RADIUS}px 圆角）"
mkdir -p "$GTK4_DIR"
cat >"$GTK4_DIR/gtk.css" <<EOF
/* SuonaOS GTK4 覆盖层 —— 由 scripts/15-rounding.sh 生成
 * 1) 不 @import gtk-Dark.css：交给 libadwaita 跟随 color-scheme，
 *    否则 GTK4 应用永远暗色，14-auto-dark.sh 的日落切换对它无效
 * 2) 只覆盖窗口外壳与弹层圆角，不动控件内部间距
 * 回滚：./scripts/15-rounding.sh --restore
 */

window.csd { border-radius: ${RADIUS}px; }
window.csd > .titlebar { border-radius: ${RADIUS}px ${RADIUS}px 0 0; }
window.csd > .titlebar:only-child { border-radius: ${RADIUS}px; }

popover > contents { border-radius: ${RADIUS}px; }
popover.background > contents { border-radius: ${RADIUS}px; }

.osd { border-radius: ${RADIUS}px; }
EOF
ok "$GTK4_DIR/gtk.css"

step "3/4 写入 GTK3 覆盖层（窗口外框）"
mkdir -p "$GTK3_DIR"
cat >"$GTK3_DIR/gtk.css" <<EOF
/* SuonaOS GTK3 圆角覆盖 —— 由 scripts/15-rounding.sh 生成
 * 只调外框 decoration，不改内部控件，避免与 Yaru 自带阴影冲突
 * 回滚：./scripts/15-rounding.sh --restore
 */

decoration,
window.csd decoration {
  border-radius: ${RADIUS}px ${RADIUS}px 0 0;
}

decoration:backdrop,
window.csd decoration:backdrop {
  border-radius: ${RADIUS}px ${RADIUS}px 0 0;
}
EOF
ok "$GTK3_DIR/gtk.css"

step "4/4 安装 Shell 圆角覆盖（菜单 / 通知 / OSD / Dock）"
# 只 @import Yaru 的完整 shell 主题再追加圆角，不改配色与布局；
# 找不到 Yaru 时跳过，避免产生一个空白 shell 主题导致面板丢失样式。
SYS_SHELL_CSS="/usr/share/themes/Yaru/gnome-shell/gnome-shell.css"
if [ -f "$SYS_SHELL_CSS" ]; then
  mkdir -p "$(dirname "$SHELL_CSS")"
  cat >"$SHELL_CSS" <<EOF
/* SuonaOS Shell 圆角覆盖 —— 由 scripts/15-rounding.sh 生成
 * 继承 Yaru 的完整 shell 主题，只放大圆角，不动配色与布局
 * 回滚：gsettings set org.gnome.shell.extensions.user-theme name ''
 */
@import url("file://$SYS_SHELL_CSS");

.popup-menu-content { border-radius: ${RADIUS}px; }
.quick-settings { border-radius: $((RADIUS + 4))px; }
.message-list .message { border-radius: ${RADIUS}px; }
.osd-window { border-radius: ${RADIUS}px; }
#dashtodockContainer .dash-background { border-radius: $((RADIUS + 6))px; }
EOF
  prev_shell="$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | tr -d "'")"
  if [ "$prev_shell" != "$SHELL_THEME" ]; then
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" \
      "org.gnome.shell.extensions.user-theme name" "原值: ${prev_shell:-空}" >>"$MANIFEST"
  fi
  gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME" \
    && ok "Shell 主题 → $SHELL_THEME（仅圆角，立即生效）"
else
  warn "缺少 $SYS_SHELL_CSS，跳过 Shell 圆角"
fi

mkdir -p "$(dirname "$CONF")"
printf '# 由 15-rounding.sh 生成（%s）\nRADIUS="%s"\n' "$(date '+%F %T')" "$RADIUS" >"$CONF"
echo
log "圆角 ${RADIUS}px 已生效；新窗口立即生效，已打开的应用需重开"
log "查看: $0 --status    回滚: $0 --restore"
