#!/usr/bin/env bash
# ============================================================================
# 06-theme-whitesur.sh - 阶段 5：WhiteSur (macOS 风) 主题美化
#   GTK 主题 / GNOME Shell 主题 / 图标 / 光标 / Dock / 窗口按钮
#   全部装在用户目录（~/.themes、~/.icons），不污染系统目录
# 用法: ./scripts/06-theme-whitesur.sh [--light|--dark]
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
export PATH="$HOME/.local/bin:$PATH"

SCHEME="dark"
[ "${1:-}" = "--light" ] && SCHEME="light"
VARIANT="Dark"; [ "$SCHEME" = "light" ] && VARIANT="Light"

VENDOR="$PROJECT_ROOT/vendor"
mkdir -p "$VENDOR" "$HOME/.themes" "$HOME/.icons"

step "阶段 5 - WhiteSur 主题美化（$SCHEME）"
require_sudo

# ---- 1. 依赖 ---------------------------------------------------------------
step "1/6 主题依赖"
apt_install sassc libglib2.0-dev-bin gnome-shell-extension-user-theme

# ---- 2. 拉取源码 -----------------------------------------------------------
step "2/6 获取主题源码"
clone_repo() {
  local name="$1" url="$2"
  local dir="$VENDOR/$name"
  if [ -d "$dir/.git" ]; then
    log "已存在，跳过克隆: $name"
    return 0
  fi
  log "克隆 $name ..."
  git clone --depth=1 "$url" "$dir" >/dev/null 2>&1 \
    && ok "$name 就绪" || { warn "$name 克隆失败: $url"; return 1; }
}

clone_repo WhiteSur-gtk-theme   https://github.com/vinceliuice/WhiteSur-gtk-theme
clone_repo WhiteSur-icon-theme  https://github.com/vinceliuice/WhiteSur-icon-theme
clone_repo WhiteSur-cursors     https://github.com/vinceliuice/WhiteSur-cursors

# ---- 3. 安装 GTK + Shell 主题 ----------------------------------------------
step "3/6 安装 GTK / Shell 主题"
GTK_DIR="$VENDOR/WhiteSur-gtk-theme"
if [ -d "$GTK_DIR" ]; then
  ( cd "$GTK_DIR" && ./install.sh -t all -c "$SCHEME" -l -d "$HOME/.themes" ) >/dev/null 2>&1 \
    && ok "GTK 主题已安装到 ~/.themes" || warn "GTK 主题安装失败，请查看 $GTK_DIR/install.sh 输出"
  # GNOME Shell 主题
  if [ -d "$HOME/.themes/WhiteSur-$VARIANT" ]; then
    ( cd "$GTK_DIR" && ./tweaks.sh -g -d "$HOME/.themes" -c "$SCHEME" ) >/dev/null 2>&1 \
      && ok "Shell 主题已安装" || log "Shell 主题已由 install.sh 一并生成"
  fi
else
  warn "跳过 GTK 主题（源码缺失）"
fi

# ---- 4. 图标与光标 ---------------------------------------------------------
step "4/6 安装图标与光标"
ICON_DIR="$VENDOR/WhiteSur-icon-theme"
if [ -d "$ICON_DIR" ]; then
  ( cd "$ICON_DIR" && ./install.sh -d "$HOME/.icons" -a ) >/dev/null 2>&1 \
    && ok "WhiteSur 图标已安装" || warn "图标安装失败"
fi

CURSOR_DIR="$VENDOR/WhiteSur-cursors"
if [ -d "$CURSOR_DIR" ]; then
  ( cd "$CURSOR_DIR" && ./install.sh ) >/dev/null 2>&1 \
    && ok "WhiteSur 光标已安装" || {
      # 无 install.sh 时手动拷贝
      mkdir -p "$HOME/.icons/WhiteSur-cursors"
      cp -r "$CURSOR_DIR/dist"/* "$HOME/.icons/WhiteSur-cursors/" 2>/dev/null && ok "光标已手动拷贝"
    }
fi

# ---- 5. 应用设置 -----------------------------------------------------------
step "5/6 应用主题设置"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  warn "非图形会话，跳过 gsettings。请在桌面终端重跑本脚本"
  exit 0
fi

# 启用 User Themes 扩展
# 注意：gnome-extensions enable 对「本次会话中新安装」的系统扩展会报"不存在"（Shell 缓存了扩展列表），
# 因此直接写 gsettings 的 enabled-extensions，注销重登后由 Shell 加载。
UT_UUID="user-theme@gnome-shell-extensions.gcampax.github.com"
CUR_EXT="$(gsettings get org.gnome.shell enabled-extensions)"
if echo "$CUR_EXT" | grep -q "$UT_UUID"; then
  ok "User Themes 已在启用列表中"
elif [ "$CUR_EXT" = "[]" ] || [ "$CUR_EXT" = "@as []" ]; then
  gsettings set org.gnome.shell enabled-extensions "['$UT_UUID']" && ok "已启用 User Themes"
else
  gsettings set org.gnome.shell enabled-extensions "$(echo "$CUR_EXT" | sed "s/]$/, '$UT_UUID']/")" \
    && ok "已启用 User Themes（注销后生效）"
fi

# 主题
gsettings set org.gnome.desktop.interface gtk-theme "WhiteSur-$VARIANT"
# 图标目录名是小写 dark/light，注意与 GTK 主题的 Dark/Light 不同
ICON_VARIANT="$SCHEME"
gsettings set org.gnome.desktop.interface icon-theme "WhiteSur-$ICON_VARIANT"
gsettings set org.gnome.desktop.interface cursor-theme "WhiteSur-cursors"
gsettings set org.gnome.desktop.interface cursor-size 24
gsettings set org.gnome.desktop.interface color-scheme "prefer-$SCHEME"
gsettings set org.gnome.shell.extensions.user-theme name "WhiteSur-$VARIANT" 2>/dev/null \
  && ok "Shell 主题: WhiteSur-$VARIANT"
ok "GTK/图标/光标: WhiteSur-$VARIANT"

# 窗口按钮：macOS 布局（左上角红绿灯）
gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
ok "窗口按钮 -> 左侧 close,minimize,maximize"

# Dock：底部 macOS 风格
DS="org.gnome.shell.extensions.dash-to-dock"
if gsettings list-schemas 2>/dev/null | grep -q "^$DS$"; then
  gsettings set $DS dock-position BOTTOM
  gsettings set $DS extend-height false
  gsettings set $DS dock-fixed false
  gsettings set $DS autohide true
  gsettings set $DS autohide-in-fullscreen true
  gsettings set $DS intellihide true
  gsettings set $DS dash-max-icon-size 44
  gsettings set $DS icon-size-fixed true
  gsettings set $DS transparency-mode 'FIXED'
  gsettings set $DS background-opacity 0.55
  gsettings set $DS show-trash false
  gsettings set $DS show-mounts false
  gsettings set $DS running-indicator-style 'DOTS'
  gsettings set $DS click-action 'minimize-or-previews'
  gsettings set $DS scroll-action 'cycle-windows'
  ok "Dock -> 底部悬浮 / 半透明 / 44px 图标"
fi

# 触控板：自然滚动 + 轻点
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true 2>/dev/null

# ---- 6. 校验 ---------------------------------------------------------------
step "6/6 校验"
for k in gtk-theme icon-theme cursor-theme color-scheme; do
  printf '  %-14s %s\n' "$k" "$(gsettings get org.gnome.desktop.interface $k)"
done
printf '  %-14s %s\n' "button-layout" "$(gsettings get org.gnome.desktop.wm.preferences button-layout)"
printf '  %-14s %s\n' "shell-theme" "$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null)"
echo
echo "  已安装主题: $(ls ~/.themes 2>/dev/null | tr '\n' ' ')"
echo "  已安装图标: $(ls ~/.icons 2>/dev/null | tr '\n' ' ')"
echo
ok "主题部署完成。部分应用需注销重登录才能完全生效"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
