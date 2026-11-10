#!/usr/bin/env bash
# ============================================================================
# 09-grub-transparency.sh - 阶段 8：GRUB 主题 + Dock/顶栏透明度
#   1) GRUB：vinceliuice/grub2-themes 的 Vimix（2K、白色图标）
#   2) Dock：dash-to-dock 原生固定透明度（不依赖扩展）
#   3) 顶栏：Blur my Shell 扩展（毛玻璃），需注销重登生效
# 用法: ./scripts/09-grub-transparency.sh [--dry-run]
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
SUDO="sudo"; [ $DRY_RUN -eq 1 ] && SUDO="echo [dry-run] sudo"

THEME="vimix"
SIZE="2k"
ICONS="white"
THEME_SRC="$PROJECT_ROOT/vendor/grub2-themes"
THEME_DST="/usr/share/grub/themes/$THEME"
EXT_UUID="blur-my-shell@aunetx"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
DOCK_SCHEMA="org.gnome.shell.extensions.dash-to-dock"
BLUR_PANEL="org.gnome.shell.extensions.blur-my-shell.panel"

step "阶段 8 - GRUB 与透明度美化 $([ $DRY_RUN -eq 1 ] && echo '(dry-run)')"
[ $DRY_RUN -eq 0 ] && require_sudo

# ---- 1. 依赖 ---------------------------------------------------------------
step "1/5 检查依赖"
if have convert || have magick; then
  ok "ImageMagick 可用（GRUB 主题生成背景与图标）"
else
  if [ $DRY_RUN -eq 1 ]; then
    log "[dry-run] 将安装 imagemagick"
  else
    apt_install imagemagick || die "ImageMagick 安装失败"
  fi
fi
have grub-mkconfig && have grub-script-check || die "缺少 grub 工具"

# ---- 2. GRUB 主题 ----------------------------------------------------------
step "2/5 安装 GRUB 主题：$THEME ($SIZE / $ICONS 图标)"
if [ ! -d "$THEME_SRC" ]; then
  if [ $DRY_RUN -eq 1 ]; then
    log "[dry-run] 将克隆 grub2-themes 到 vendor/"
  else
    mkdir -p "$PROJECT_ROOT/vendor"
    timeout 180 git clone --depth 1 https://github.com/vinceliuice/grub2-themes "$THEME_SRC" \
      || die "克隆失败（检查网络或 ghfast 镜像）"
  fi
fi

if [ $DRY_RUN -eq 1 ]; then
  log "[dry-run] 将备份 /etc/default/grub"
  log "[dry-run] 将执行: sudo ./install.sh -t $THEME -i $ICONS -s $SIZE"
else
  backup_file /etc/default/grub
  # install.sh 只改 GRUB_THEME / GRUB_GFXMODE 两行，并自动 update-grub
  ( cd "$THEME_SRC" && timeout 300 $SUDO ./install.sh -t "$THEME" -i "$ICONS" -s "$SIZE" ) \
    && ok "GRUB 主题已安装并更新引导" || die "install.sh 失败，检查 /etc/default/grub"
fi

# ---- 3. Dock 透明度 --------------------------------------------------------
step "3/5 Dock 固定半透明"
if [ $DRY_RUN -eq 1 ]; then
  log "[dry-run] transparency-mode=FIXED background-opacity=0.5"
else
  gsettings set "$DOCK_SCHEMA" transparency-mode 'FIXED' \
    && gsettings set "$DOCK_SCHEMA" background-opacity 0.5 \
    && ok "Dock：FIXED / 0.5（改数值即调深浅，0=全透 1=不透明）"
fi

# ---- 4. 顶栏毛玻璃 ---------------------------------------------------------
step "4/5 顶栏毛玻璃（Blur my Shell）"
if [ ! -f "$EXT_DIR/metadata.json" ]; then
  if [ $DRY_RUN -eq 1 ]; then
    log "[dry-run] 将解压 vendor/blur-my-shell.zip 到扩展目录"
  else
    [ -f "$PROJECT_ROOT/vendor/blur-my-shell.zip" ] \
      || die "缺少 vendor/blur-my-shell.zip（可重新下载后放入）"
    mkdir -p "$EXT_DIR"
    unzip -oq "$PROJECT_ROOT/vendor/blur-my-shell.zip" -d "$EXT_DIR" \
      && ok "扩展已解压到 ${EXT_DIR#$HOME/}"
  fi
fi

if [ $DRY_RUN -eq 0 ]; then
  glib-compile-schemas "$EXT_DIR/schemas" 2>/dev/null || warn "schema 编译失败"

  CUR_EXT="$(gsettings get org.gnome.shell enabled-extensions)"
  if echo "$CUR_EXT" | grep -q "$EXT_UUID"; then
    log "扩展已在启用列表"
  elif [ "$CUR_EXT" = "[]" ] || [ "$CUR_EXT" = "@as []" ]; then
    gsettings set org.gnome.shell enabled-extensions "['$EXT_UUID']" && ok "已启用扩展"
  else
    gsettings set org.gnome.shell enabled-extensions \
      "$(echo "$CUR_EXT" | sed "s/]$/, '$EXT_UUID']/")" && ok "已启用扩展"
  fi

  # 注意：gsettings 不接受 --schemadir（本机 glib 版本），用环境变量
  export GSETTINGS_SCHEMA_DIR="$EXT_DIR/schemas"
  gsettings set "$BLUR_PANEL" blur true
  gsettings set "$BLUR_PANEL" customize true
  gsettings set "$BLUR_PANEL" override-background true
  gsettings set "$BLUR_PANEL" brightness 0.6
  gsettings set "$BLUR_PANEL" sigma 30
  gsettings set "$BLUR_PANEL" static-blur false
  gsettings set "$BLUR_PANEL" unblur-in-overview false
  ok "顶栏参数已写入（brightness 0.6 / sigma 30）"
  warn "顶栏效果需注销重登才生效（新装扩展在当前会话不加载）"
fi

# ---- 5. 验证 ---------------------------------------------------------------
step "5/5 验证"
if [ $DRY_RUN -eq 1 ]; then
  log "[dry-run] 跳过验证"
else
  grep -q "^GRUB_THEME=\"$THEME_DST/theme.txt\"" /etc/default/grub \
    && ok "GRUB_THEME -> $THEME_DST/theme.txt" || warn "GRUB_THEME 未写入"
  grep -q '^GRUB_GFXMODE=' /etc/default/grub \
    && ok "GFXMODE = $(grep '^GRUB_GFXMODE=' /etc/default/grub | cut -d= -f2)" \
    || warn "GFXMODE 缺失"
  sudo grub-script-check /boot/grub/grub.cfg >/dev/null 2>&1 \
    && ok "grub.cfg 语法正确" || die "grub.cfg 语法错误！先回滚"
  grep -q "theme.txt" /boot/grub/grub.cfg && ok "grub.cfg 已引用主题"
  [ "$(gsettings get "$DOCK_SCHEMA" transparency-mode | tr -d "'")" = FIXED ] \
    && ok "Dock 透明度：$(gsettings get "$DOCK_SCHEMA" background-opacity)"
  gsettings get org.gnome.shell enabled-extensions | grep -q "$EXT_UUID" \
    && ok "Blur my Shell 已启用（待重登加载）"
fi

echo
log "生效方式：GRUB 需重启；顶栏需注销重登；Dock 即时生效"
log "回滚：./scripts/rollback.sh --restore 20261106-075444 --only /etc/default/grub"
log "      再 sudo update-grub；Dock/顶栏见 docs/13 第 5 节"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
