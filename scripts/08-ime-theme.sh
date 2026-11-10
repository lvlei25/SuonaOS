#!/usr/bin/env bash
# ============================================================================
# 08-ime-theme.sh - 阶段 7：输入法（fcitx5 候选框）美化
#   安装 Catppuccin（深色圆角）与 Material-Color（浅色扁平）两套主题
#   Catppuccin 默认启用圆角（panel.svg / highlight.svg）
# 用法:
#   ./scripts/08-ime-theme.sh                 # 安装全部并保持当前主题
#   ./scripts/08-ime-theme.sh --set mocha-mauve   # 安装并切换到指定主题
#   ./scripts/08-ime-theme.sh --list          # 只列出可用主题
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

THEME_DIR="$HOME/.local/share/fcitx5/themes"
CONF_DIR="$HOME/.config/fcitx5/conf"
VENDOR="$PROJECT_ROOT/vendor/ime-themes"
mkdir -p "$THEME_DIR" "$CONF_DIR" "$VENDOR"

ACTION=install; SET_THEME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) ACTION=list ;;
    --set) ACTION=install; SET_THEME="${2:-}"; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

list_themes() {
  echo "已安装主题："
  for d in "$THEME_DIR"/*/; do
    [ -f "$d/theme.conf" ] || continue
    local name id
    name=$(grep -m1 '^Name=' "$d/theme.conf" | cut -d= -f2-)
    id=$(basename "$d")
    printf '  %-34s %s\n' "$id" "$name"
  done
  echo
  echo "切换: $0 --set <主题目录名>"
}

[ "$ACTION" = list ] && { list_themes; exit 0; }

# ---- 1. 获取源码 -----------------------------------------------------------
step "1/4 获取主题源码"
fetch() { # fetch <目标文件> <github仓库> <分支>
  local out="$1" repo="$2" br="${3:-main}"
  [ -s "$out" ] && { log "已缓存 $(basename "$out")"; return 0; }
  wget -q -T 60 -O "$out" "https://codeload.github.com/$repo/tar.gz/refs/heads/$br" 2>/dev/null \
    || wget -q -T 60 -O "$out" "https://ghfast.top/https://github.com/$repo/archive/refs/heads/$br.tar.gz" 2>/dev/null
  [ -s "$out" ] && ok "$(basename "$out") $(du -h "$out" | cut -f1)" || { warn "下载失败: $repo"; return 1; }
}

fetch "$VENDOR/catppuccin.tar.gz" "catppuccin/fcitx5" main
fetch "$VENDOR/material-color.tar.gz" "hosxy/Fcitx5-Material-Color" master

rm -rf "$VENDOR/src"; mkdir -p "$VENDOR/src"
[ -s "$VENDOR/catppuccin.tar.gz" ] && tar -xzf "$VENDOR/catppuccin.tar.gz" -C "$VENDOR/src"
[ -s "$VENDOR/material-color.tar.gz" ] && tar -xzf "$VENDOR/material-color.tar.gz" -C "$VENDOR/src"

# ---- 2. 安装 Catppuccin（深色/浅色，圆角）----------------------------------
step "2/4 安装 Catppuccin"
CTP=$(find "$VENDOR/src" -maxdepth 2 -type d -name 'fcitx5-*' | head -1)
if [ -n "$CTP" ] && [ -d "$CTP/src" ]; then
  N=0
  for src in "$CTP"/src/catppuccin-*/; do
    [ -f "$src/theme.conf" ] || continue
    base=$(basename "$src")                 # catppuccin-mocha-mauve
    target="$THEME_DIR/Catppuccin-${base#catppuccin-}"   # Catppuccin-mocha-mauve
    mkdir -p "$target"
    cp -a "$src/." "$target/"
    # 启用圆角：取消 panel.svg / highlight.svg 的注释
    sed -i -e 's/^#\s*Image=panel\.svg/Image=panel.svg/' \
           -e 's/^#\s*Image=highlight\.svg/Image=highlight.svg/' "$target/theme.conf"
    N=$((N+1))
  done
  ok "已安装 Catppuccin $N 套（已启用圆角）"
else
  warn "Catppuccin 源码结构异常，跳过"
fi

# ---- 3. 安装 Material-Color（浅色扁平）-------------------------------------
step "3/4 安装 Material-Color"
MAT=$(find "$VENDOR/src" -maxdepth 2 -type d -name 'Fcitx5-Material-Color-*' | head -1)
if [ -n "$MAT" ]; then
  N=0
  for conf in "$MAT"/theme-*.conf; do
    [ -f "$conf" ] || continue
    color=$(basename "$conf" .conf); color=${color#theme-}   # blue
    target="$THEME_DIR/Material-Color-$color"
    mkdir -p "$target"
    cp -a "$MAT/arrow.png" "$MAT/radio.png" "$target/" 2>/dev/null
    # 原名都叫 Material-Color，改成带颜色名以便在列表中区分
    sed "s/^Name=Material-Color/Name=Material-Color ($color)/" "$conf" >"$target/theme.conf"
    N=$((N+1))
  done
  ok "已安装 Material-Color $N 套"
else
  warn "Material-Color 源码结构异常，跳过"
fi

# ---- 4. 应用 ---------------------------------------------------------------
step "4/4 应用主题"
CUR=""
if [ -f "$CONF_DIR/classicui.conf" ]; then
  CUR=$(grep -m1 '^Theme=' "$CONF_DIR/classicui.conf" | cut -d= -f2-)
fi

# 未指定时：优先沿用当前主题，否则用 Mocha Mauve（深色圆角）
[ -z "$SET_THEME" ] && {
  if [ -n "$CUR" ] && [ -d "$THEME_DIR/$CUR" ]; then
    SET_THEME="$CUR"
  else
    SET_THEME="Catppuccin-mocha-mauve"
  fi
}

if [ ! -d "$THEME_DIR/$SET_THEME" ]; then
  warn "主题不存在: $SET_THEME，可用："
  list_themes
  exit 1
fi

cp -a "$CONF_DIR/classicui.conf" "$BACKUP_DIR/$RUN_ID-fcitx-classicui.conf" 2>/dev/null || true
cat >"$CONF_DIR/classicui.conf" <<EOF
# 由 linux-tune 生成
# 候选框主题
Theme=$SET_THEME
# 候选框字体（含中文，不要只写 Inter 否则汉字会回落）
Font="Noto Sans CJK SC 12"
# 右键菜单字体
MenuFont="Noto Sans CJK SC 10"
# 托盘图标文字
TrayFont="Noto Sans CJK SC Bold 10"
# 竖向候选列表（习惯竖排可改 True）
Vertical Candidate List=False
# 候选词分页（滚轮翻页）
WheelForPaging=True
EOF
ok "classicui.conf 已写入，主题 = $SET_THEME"

# 重启 fcitx5 使主题生效（ADR-04：进程已由 systemd 用户服务托管）
# 坑：classicui 主题/字体在 `fcitx5-remote -r` 热重载下可能不刷新，必须重启进程；
#     `pkill` 之后若手工启动失败会把输入法彻底弄没；
#     `fcitx5 -d` 会继承 stdout 导致后续输出丢失。
# 因此优先交给 systemd 重启（有 Restart=on-failure 兜底），逐级降级并始终校验存活。
restart_fcitx5() {
  # 1) 首选：systemd 托管下整服务重启，主题必定重新加载
  if systemctl --user is-active --quiet fcitx5.service 2>/dev/null; then
    systemctl --user restart fcitx5.service >/dev/null 2>&1
    sleep 2
    systemctl --user is-active --quiet fcitx5.service 2>/dev/null && return 0
  fi
  # 2) 无服务托管但有进程：退而求其次做热重载
  if pgrep -x fcitx5 >/dev/null; then
    fcitx5-remote -r >/dev/null 2>&1
    sleep 1
    pgrep -x fcitx5 >/dev/null && return 0
  fi
  # 3) 进程已死且无服务：用 setsid 完全脱离当前会话冷启动
  setsid fcitx5 -d >/dev/null 2>&1 </dev/null &
  sleep 2
  pgrep -x fcitx5 >/dev/null
}

if restart_fcitx5; then
  ok "fcitx5 已就绪（pid $(pgrep -x fcitx5))"
else
  warn "fcitx5 启动失败，检查: systemctl --user status fcitx5.service"
fi

echo
list_themes
echo "提示：执行 fcitx5-configtool 可在图形界面预览候选框效果"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
