#!/usr/bin/env bash
# ============================================================================
# 16-ime-icon.sh - 让输入法顶栏图标跟随系统单色风格
#   1) 在用户图标目录提供 fcitx-pinyin-symbolic.svg（Adwaita 键盘图标）
#   2) 给 kimpanel 扩展打补丁：顶栏主图标请求 symbolic 版本
#   3) 找不到 symbolic 时 GTK 自动回落原彩色图标，不会变空
# 用法:
#   ./scripts/16-ime-icon.sh --install   # 幂等
#   ./scripts/16-ime-icon.sh --status
#   ./scripts/16-ime-icon.sh --restore   # 撤销补丁与图标
# 注意: 修改扩展代码后需要「注销重登」才生效（Wayland 下不能 Alt+F2 r）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

EXT="$HOME/.local/share/gnome-shell/extensions/kimpanel@kde.org"
LIB="$EXT/lib.js"
IND="$EXT/indicator.js"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
ICON="$ICON_DIR/fcitx-pinyin-symbolic.svg"
SRC_ICON="/usr/share/icons/Adwaita/symbolic/devices/input-keyboard-symbolic.svg"

ACTION=""
case "${1:-}" in
  --install) ACTION=install ;;
  --status)  ACTION=status ;;
  --restore) ACTION=restore ;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "未知参数: ${1:-}（--install / --status / --restore）" ;;
esac

[ -f "$LIB" ] || die "找不到 kimpanel 扩展: $LIB"

if [ "$ACTION" = status ]; then
  echo "扩展      : $EXT"
  echo "图标文件  : $([ -f "$ICON" ] && echo "存在（$(wc -c <"$ICON") 字节）" || echo 缺失)"
  echo "lib 补丁  : $(grep -q 'createSymbolicIcon' "$LIB" && echo 已应用 || echo 未应用)"
  echo "indicator : $(grep -q 'Lib.createSymbolicIcon(iconName)' "$IND" && echo 已应用 || echo 未应用)"
  echo "当前输入法: $(fcitx5-remote -n 2>/dev/null || echo '未知')"
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  step "1/2 撤销 indicator.js 调用"
  if grep -q 'Lib.createSymbolicIcon(iconName)' "$IND"; then
    python3 - "$IND" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
p.write_text(s.replace('Lib.createSymbolicIcon(iconName)', 'Lib.createIcon(iconName)'))
PY
    ok "已改回 Lib.createIcon(iconName)"
  else
    ok "未被修改，跳过"
  fi

  step "2/2 删除用户级 symbolic 图标"
  if [ -f "$ICON" ]; then
    rm -f "$ICON" && ok "已删除 ${ICON#$HOME/}"
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  else
    ok "图标不存在，跳过"
  fi
  # lib.js 里的 createSymbolicIcon 留着无害（不再被调用），避免误删破坏文件
  warn "注销重登后恢复原彩色图标"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/3 安装 symbolic 图标"
[ -f "$SRC_ICON" ] || die "缺少源图标: $SRC_ICON"
mkdir -p "$ICON_DIR"
cp -f "$SRC_ICON" "$ICON" && ok "${ICON#$HOME/}（Adwaita input-keyboard-symbolic）"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

step "2/3 给 kimpanel 打补丁"
mkdir -p "$BACKUP_DIR/$RUN_ID/files$EXT"
cp -a "$LIB" "$BACKUP_DIR/$RUN_ID/files$EXT/" 2>/dev/null
cp -a "$IND" "$BACKUP_DIR/$RUN_ID/files$EXT/" 2>/dev/null
if grep -q 'createSymbolicIcon' "$LIB" && grep -q 'Lib.createSymbolicIcon(iconName)' "$IND"; then
  ok "补丁已存在，跳过（幂等）"
else
  python3 - "$LIB" "$IND" <<'PY' || die "打补丁失败"
import sys, pathlib

lib, ind = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

t = lib.read_text()
if 'createSymbolicIcon' not in t:
    marker = 'export function createMenuItem(property) {'
    fn = '''/**
 * SuonaOS 补丁：顶栏主图标优先使用 symbolic 版本，使其跟随主题明暗着色。
 * 原 createIcon() 故意请求 name + '-symbolic-hack' 来拿彩色图标，
 * 浅色顶栏上会显示成红色的 fcitx-pinyin.png，与系统单色图标冲突。
 * 找不到 symbolic 版本时 GTK 会自动回落到原彩色图标，不会变空。
 */
export function createSymbolicIcon(name) {
    if (!name)
        return null;
    if (name[0] == '/')
        return Gio.FileIcon.new(Gio.File.new_for_path(name));
    return Gio.ThemedIcon.new_with_default_fallbacks(name + '-symbolic');
}

''' + marker
    if marker not in t:
        sys.exit('lib.js 中找不到插入点')
    lib.write_text(t.replace(marker, fn, 1))

s = ind.read_text()
if 'Lib.createSymbolicIcon(iconName)' not in s:
    if 'let gicon = Lib.createIcon(iconName);' not in s:
        sys.exit('indicator.js 中找不到替换点')
    ind.write_text(s.replace('let gicon = Lib.createIcon(iconName);',
                             'let gicon = Lib.createSymbolicIcon(iconName);'))
PY
  ok "lib.js / indicator.js 补丁完成"
fi

step "3/3 校验"
[ -f "$ICON" ] || die "图标未写入"
grep -q 'createSymbolicIcon' "$LIB" || die "lib.js 补丁缺失"
grep -q 'Lib.createSymbolicIcon(iconName)' "$IND" || die "indicator.js 补丁缺失"
ok "图标与补丁均已就位"

echo
warn "需要注销重登才生效（Wayland 下 Alt+F2 → r 不可用）"
log "状态: $0 --status    回滚: $0 --restore"
log "扩展升级会覆盖 lib.js/indicator.js，升级后重跑 --install 即可"
