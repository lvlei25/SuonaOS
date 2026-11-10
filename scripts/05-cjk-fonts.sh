#!/usr/bin/env bash
# ============================================================================
# 05-cjk-fonts.sh - 阶段 4：中文与字体渲染
#   Inter（界面）+ JetBrains Mono（终端）+ Noto Sans CJK（中文）
#   附带 fontconfig 渲染调优与 GNOME 字体设置
# 用法: ./scripts/05-cjk-fonts.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

step "阶段 4 - 中文与字体渲染"
require_sudo

# ---- 1. 字体包 -------------------------------------------------------------
step "1/4 安装字体"
apt_install fonts-inter fonts-jetbrains-mono fonts-noto-cjk fonts-noto-color-emoji

# ---- 2. fontconfig ---------------------------------------------------------
step "2/4 字体渲染调优"
FC_CONF="$HOME/.config/fontconfig/fonts.conf"
mkdir -p "$(dirname "$FC_CONF")"
[ -f "$FC_CONF" ] && backup_file "$FC_CONF"
cat >"$FC_CONF" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- 由 linux-tune 生成：LCD 亚像素渲染 + 中文优先级 -->
<fontconfig>
  <!-- 全局渲染参数：笔记本高分屏下 hintslight 更锐利 -->
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
  </match>

  <!-- 等宽字体（终端/编辑器）优先 JetBrains Mono，中文回落到 Noto Sans Mono CJK -->
  <alias><family>monospace</family><prefer>
    <family>JetBrains Mono</family>
    <family>Noto Sans Mono CJK SC</family>
  </prefer></alias>

  <!-- 无衬线（界面）优先 Inter，中文回落 Noto Sans CJK SC -->
  <alias><family>sans-serif</family><prefer>
    <family>Inter</family>
    <family>Noto Sans CJK SC</family>
  </prefer></alias>

  <!-- 衬线 -->
  <alias><family>serif</family><prefer>
    <family>Noto Serif CJK SC</family>
  </prefer></alias>

  <!-- 微软字体名映射，兼容老文档 -->
  <alias binding="same"><family>Microsoft YaHei</family><accept><family>Noto Sans CJK SC</family></accept></alias>
  <alias binding="same"><family>SimSun</family><accept><family>Noto Serif CJK SC</family></accept></alias>
  <alias binding="same"><family>SimHei</family><accept><family>Noto Sans CJK SC</family></accept></alias>

  <!-- 中文字重微调：避免中文比西文粗 -->
  <match target="pattern">
    <test name="lang" compare="contains"><string>zh</string></test>
    <test name="weight" compare="less_eq"><const>medium</const></test>
    <edit name="weight" mode="assign"><const>regular</const></edit>
  </match>
</fontconfig>
EOF
fc-cache -f >/dev/null 2>&1 && ok "字体缓存已重建"

# ---- 3. GNOME 字体 ---------------------------------------------------------
step "3/4 设置 GNOME 字体"
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  gsettings set org.gnome.desktop.interface font-name 'Inter 11' \
    && gsettings set org.gnome.desktop.interface document-font-name 'Inter 12' \
    && gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 11' \
    && gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Bold 11' \
    && ok "界面 Inter 11 / 文档 Inter 12 / 等宽 JetBrains Mono 11"
else
  warn "非图形会话，跳过 gsettings（可在桌面终端重跑本脚本）"
fi

# ---- 4. 校验 ---------------------------------------------------------------
step "4/4 校验"
echo "  界面字体: $(gsettings get org.gnome.desktop.interface font-name 2>/dev/null)"
echo "  等宽字体: $(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null)"
echo "  中文字体数: $(fc-list :lang=zh 2>/dev/null | wc -l)"
echo "  Inter:        $(fc-list 'Inter' family 2>/dev/null | head -1)"
echo "  JetBrains:    $(fc-list 'JetBrains Mono' family 2>/dev/null | head -1)"
echo "  中文首选:     $(fc-match -s 'sans-serif:lang=zh' 2>/dev/null | head -1)"
ok "完成"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
