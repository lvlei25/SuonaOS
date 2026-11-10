#!/usr/bin/env bash
# ============================================================================
# rescue.sh - 启动异常后的一键抢救
# 场景: 重启后卡在启动、进不了桌面、黑屏，需要在 TTY / 恢复模式下修复
# 用法:
#   cd ~/CodeBuddy/work/linux-tune_SuonaOS && ./scripts/rescue.sh
#   ./scripts/rescue.sh --dry-run      只看会做什么
#   ./scripts/rescue.sh --themes-only  只重置主题（能进桌面但界面崩了）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DRY=0; THEMES_ONLY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --themes-only) THEMES_ONLY=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

run() {
  if [ $DRY -eq 1 ]; then
    printf '  %s[dry-run]%s %s\n' "$C_WARN" "$C_RESET" "$*"
  else
    "$@" && printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$*" || printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$*"
  fi
}

echo
echo "══════════════════════════════════════════"
echo "  linux-tune 抢救脚本  $([ $DRY -eq 1 ] && echo '(dry-run)')"
echo "══════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 模式 A：只重置主题（能进桌面但界面崩溃 / 顶栏消失 / 图标全白）
# ---------------------------------------------------------------------------
if [ $THEMES_ONLY -eq 1 ]; then
  step "重置主题为系统默认"
  run gsettings reset org.gnome.desktop.interface gtk-theme
  run gsettings reset org.gnome.desktop.interface icon-theme
  run gsettings reset org.gnome.desktop.interface cursor-theme
  run gsettings reset org.gnome.desktop.interface color-scheme
  run gsettings reset org.gnome.desktop.wm.preferences button-layout
  run gsettings reset org.gnome.shell.extensions.user-theme name
  run gsettings set org.gnome.desktop.interface cursor-theme Adwaita
  echo
  ok "主题已回默认。若顶栏仍未恢复，注销重登或重启"
  exit 0
fi

require_sudo

# ---------------------------------------------------------------------------
# 1. GRUB / 引导
# ---------------------------------------------------------------------------
step "1/5 还原 GRUB 引导配置"
GRUB_BAK=$(ls "$BACKUP_DIR"/*/files/etc/default/grub 2>/dev/null | head -1)
if [ -n "$GRUB_BAK" ]; then
  log "使用最早的备份: ${GRUB_BAK#$PROJECT_ROOT/}"
  run sudo cp -a "$GRUB_BAK" /etc/default/grub
else
  warn "未找到 /etc/default/grub 备份，跳过"
fi

# grub.d 片段（kdump-tools 的 crashkernel 覆盖就在这里）
for f in "$BACKUP_DIR"/*/files/etc/default/grub.d/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  log "还原片段 $name"
  run sudo cp -a "$f" "/etc/default/grub.d/$name"
  break
done

run sudo update-grub

# ---------------------------------------------------------------------------
# 2. 移除本次优化写入的内核/服务配置
# ---------------------------------------------------------------------------
step "2/5 移除本次写入的系统配置"
for f in /etc/sysctl.d/99-linux-tune.conf \
         /etc/systemd/zram-generator.conf \
         /etc/systemd/journald.conf.d/99-linux-tune.conf; do
  if [ -f "$f" ]; then
    run sudo rm -f "$f"
  else
    log "不存在，跳过: $f"
  fi
done
run sudo systemctl daemon-reload

# apport 恢复
APPORT_BAK=$(ls "$BACKUP_DIR"/*/files/etc/default/apport 2>/dev/null | head -1)
if [ -n "$APPORT_BAK" ]; then
  run sudo cp -a "$APPORT_BAK" /etc/default/apport
fi

# cloud-init 解除禁用标记
[ -f /etc/cloud/cloud-init.disabled ] && run sudo rm -f /etc/cloud/cloud-init.disabled

# ---------------------------------------------------------------------------
# 3. 恢复被禁用的服务
# ---------------------------------------------------------------------------
step "3/5 恢复被禁用的服务单元"
COUNT=0
for tsv in "$PROJECT_ROOT"/logs/disabled-units-*.tsv; do
  [ -f "$tsv" ] || continue
  while IFS=$'\t' read -r u _; do
    [ -z "$u" ] && continue
    if [ $DRY -eq 1 ]; then
      printf '  %s[dry-run]%s systemctl enable %s\n' "$C_WARN" "$C_RESET" "$u"
    else
      sudo systemctl enable "$u" >/dev/null 2>&1 \
        && printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$u"
    fi
    COUNT=$((COUNT+1))
  done <"$tsv"
done
[ $COUNT -eq 0 ] && log "无记录"

# ---------------------------------------------------------------------------
# 4. 校验启动链
# ---------------------------------------------------------------------------
step "4/5 校验启动链"
if sudo grub-script-check /boot/grub/grub.cfg 2>/dev/null; then
  ok "grub.cfg 语法正确"
else
  warn "grub.cfg 语法异常，尝试用 dpkg 重建: sudo dpkg-reconfigure grub-efi-amd64"
fi
sudo grep -q "vmlinuz-$(uname -r)" /boot/grub/grub.cfg 2>/dev/null \
  && ok "内核条目存在" || warn "内核条目缺失"
[ -L /etc/systemd/system/display-manager.service ] && ok "显示管理器符号链接正常" || warn "显示管理器链接缺失"
[ -f "/boot/initrd.img-$(uname -r)" ] && ok "initramfs 存在" || warn "initramfs 缺失: sudo update-initramfs -u -k all"

# ---------------------------------------------------------------------------
# 5. 收尾
# ---------------------------------------------------------------------------
step "5/5 完成"
if [ $DRY -eq 1 ]; then
  warn "以上为预览，未做任何修改。去掉 --dry-run 执行实际操作"
else
  ok "已恢复到优化前的引导与服务状态"
  echo
  echo "  下一步："
  echo "    sudo reboot          # 重启验证"
  echo "    若仍失败，用恢复模式（见 docs/98-启动恢复.md）"
  echo "    或执行完整回滚：./scripts/rollback.sh --list"
fi
