#!/usr/bin/env bash
# ============================================================================
# 07-ime-fcitx5.sh - 阶段 6：fcitx5 输入法接管 + 登录自启（systemd 用户服务）
# 背景:
#   1) 系统预装 fcitx5，但环境变量指向 ibus，fcitx5 装而不用
#   2) im-config 的 im-launch 在 Wayland 下「不启动」输入法守护进程
#      （只有 X11 会话才 exec 启动），登录自启必须由别的方式保证
#   3) .desktop autostart 多次失败，且与 systemd 服务并存会双重拉起进程
# 做法: im-config + environment.d + systemd user unit + XSettings 四层（ADR-04）
#       旧的 ~/.config/autostart 自启项由本脚本主动清理，避免双重拉起
# 用法: ./scripts/07-ime-fcitx5.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

step "阶段 6 - fcitx5 输入法接管"

have fcitx5 || die "fcitx5 未安装: sudo apt install fcitx5 fcitx5-chinese-addons fcitx5-frontend-all"

# ---- 1. 现状 ---------------------------------------------------------------
step "1/6 当前状态"
echo "  XMODIFIERS    = ${XMODIFIERS:-未设置}"
echo "  GTK_IM_MODULE = ${GTK_IM_MODULE:-未设置}"
echo "  fcitx5        = $(fcitx5 --version 2>&1 | head -1)"
echo "  im-config     = $( [ -f ~/.xinputrc ] && grep run_im ~/.xinputrc || echo '未配置')"
echo "  user unit     = $(systemctl --user is-enabled fcitx5.service 2>/dev/null || echo '未配置')"

# ---- 2. im-config 选 fcitx5 ------------------------------------------------
step "2/6 设置系统输入法为 fcitx5"
if have im-config; then
  backup_file ~/.xinputrc
  im-config -n fcitx5 >/dev/null 2>&1 && ok "已写入 ~/.xinputrc: run_im fcitx5" \
    || warn "im-config 执行失败，将依赖后续手工配置"
else
  warn "im-config 未安装，跳过（sudo apt install im-config）"
fi

# ---- 3. 会话环境变量 -------------------------------------------------------
step "3/6 写入会话环境变量"
ENV_DIR="$HOME/.config/environment.d"
mkdir -p "$ENV_DIR"
ENV_FILE="$ENV_DIR/99-input-method.conf"
[ -f "$ENV_FILE" ] && backup_file "$ENV_FILE"
cat >"$ENV_FILE" <<'EOF'
# 由 linux-tune 生成：让所有图形应用使用 fcitx5
# im-config 只写 ~/.xinputrc，Wayland 会话不会自动导出这些变量
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
# GLFW/游戏类对 fcitx 支持差，交给 ibus 更稳
GLFW_IM_MODULE=ibus
EOF
ok "已写入 ~/.config/environment.d/99-input-method.conf"

# ---- 4. 登录自启（systemd 用户服务，Wayland 关键）--------------------------
step "4/6 配置登录自启（systemd 用户服务）"
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
UNIT="$UNIT_DIR/fcitx5.service"
[ -f "$UNIT" ] && backup_file "$UNIT"

# 防御：旧方案的 .desktop 自启若还在，会与 systemd 服务双重拉起 fcitx5
OLD_AUTO="$HOME/.config/autostart/fcitx5.desktop"
if [ -f "$OLD_AUTO" ]; then
  backup_file "$OLD_AUTO"
  rm -f "$OLD_AUTO"
  ok "已移除旧 autostart 自启项（防止双重拉起）"
fi

cat >"$UNIT" <<'EOF'
[Unit]
Description=Fcitx 5 Input Method
Documentation=man:fcitx5(1)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/fcitx5
Restart=on-failure
RestartSec=3
Environment=GTK_IM_MODULE=fcitx
Environment=QT_IM_MODULE=fcitx
Environment=XMODIFIERS=@im=fcitx

[Install]
WantedBy=graphical-session.target
EOF
ok "已写入 ~/.config/systemd/user/fcitx5.service"

systemctl --user daemon-reload 2>/dev/null || warn "daemon-reload 失败（非图形会话时属正常）"
systemctl --user enable fcitx5.service >/dev/null 2>&1 \
  && ok "fcitx5.service 已设为开机自启" \
  || warn "enable 失败，登录后执行: systemctl --user enable fcitx5.service"

# ---- 5. XSettings（GTK3 应用更可靠）----------------------------------------
step "5/6 设置 GTK/IMModule"
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  gsettings set org.gnome.settings-daemon.plugins.xsettings overrides "{'Gtk/IMModule': <'fcitx'>}" \
    && ok "XSettings: Gtk/IMModule = fcitx"
else
  warn "非图形会话，跳过 gsettings"
fi

# ---- 6. 输入方案 + 服务就绪 -------------------------------------------------
step "6/6 输入方案与服务就绪"
FC_DIR="$HOME/.config/fcitx5"
mkdir -p "$FC_DIR"
if [ ! -f "$FC_DIR/profile" ] || ! grep -q pinyin "$FC_DIR/profile" 2>/dev/null; then
  [ -f "$FC_DIR/profile" ] && backup_file "$FC_DIR/profile"
  cat >"$FC_DIR/profile" <<'EOF'
[Groups/0]
# Group Name
Name=默认
# Layout
Default Layout=us
# Default Input Method
DefaultIM=pinyin

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=pinyin
# Layout
Layout=

[GroupOrder]
0=默认
EOF
  ok "已写入输入方案：英文键盘 + 拼音"
else
  log "输入方案已存在，保留当前配置"
fi

# 进程生命周期交给 systemd：不手工 fcitx5 -d，避免脱离服务托管
if systemctl --user is-active --quiet fcitx5.service 2>/dev/null; then
  ok "fcitx5 由 systemd 服务托管（active）"
elif pgrep -x fcitx5 >/dev/null; then
  warn "fcitx5 进程存在但服务未激活，建议执行: systemctl --user restart fcitx5.service"
else
  systemctl --user start fcitx5.service >/dev/null 2>&1 \
    && ok "已启动 fcitx5.service" \
    || warn "启动失败，检查: systemctl --user status fcitx5.service"
fi

echo
log "当前输入法: $(fcitx5-remote -n 2>/dev/null || echo 未知)"
warn "环境变量需注销重登才对所有应用生效"
log "自启状态: systemctl --user status fcitx5.service"
log "改候选框主题后须: systemctl --user restart fcitx5.service"
log "快捷键: Ctrl+Space 切换中英，Ctrl+Shift 切换方案"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
