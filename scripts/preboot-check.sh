#!/usr/bin/env bash
# ============================================================================
# preboot-check.sh - 重启前安全检查
# 逐项验证可能导致「开不了机 / 进不了桌面」的配置是否完好
# 用法: ./scripts/preboot-check.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PASS=0; FAIL=0; WARN=0
ok_()   { printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$1"; PASS=$((PASS+1)); }
bad_()  { printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }
warn_() { printf '  %s!%s %s\n' "$C_WARN" "$C_RESET" "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; WARN=$((WARN+1)); }

require_sudo

echo
echo "════════ 1. GRUB 引导配置 ════════"

if sudo grub-script-check /boot/grub/grub.cfg 2>/dev/null; then
  ok_ "grub.cfg 语法正确"
else
  bad_ "grub.cfg 语法错误" "立即修复: sudo update-grub；若失败: ./scripts/rollback.sh --list"
fi

if sudo grep -q "vmlinuz-$(uname -r)" /boot/grub/grub.cfg 2>/dev/null; then
  ok_ "启动菜单包含当前内核 $(uname -r)"
else
  bad_ "启动菜单缺少当前内核条目" "检查 /etc/default/grub 的 GRUB_DISABLE_LINUX_UUID 等设置"
fi

INITRD="/boot/initrd.img-$(uname -r)"
if [ -f "$INITRD" ]; then
  ok_ "initramfs 存在 ($(du -h "$INITRD" | cut -f1))"
else
  bad_ "initramfs 缺失: $INITRD" "sudo update-initramfs -u -k all"
fi

LINE=$(sudo grep -m1 -o 'linux\s\+.*vmlinuz.*' /boot/grub/grub.cfg 2>/dev/null)
echo "      当前内核行: $(echo "$LINE" | cut -c1-110)"
case "$LINE" in
  *root=UUID=*) ok_ "根分区以 UUID 挂载（不依赖设备名变化）" ;;
  *) warn_ "根分区未使用 UUID" "设备名变化可能导致找不到根分区" ;;
esac

# 双系统感知：菜单里有 Windows 时超时不能太短，否则选不到
if sudo grep -q 'Windows Boot Manager' /boot/grub/grub.cfg 2>/dev/null; then
  GT=$(grep '^GRUB_TIMEOUT=' /etc/default/grub 2>/dev/null | cut -d= -f2)
  if [ -n "$GT" ] && [ "$GT" -ge 3 ] 2>/dev/null; then
    ok_ "双系统（含 Windows），GRUB 超时 ${GT}s 足够选择"
  else
    warn_ "双系统但 GRUB 超时 ${GT:-?}s 过短，可能选不到 Windows" \
          "sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub && sudo update-grub"
  fi
fi
sudo grep -q 'recovery mode' /boot/grub/grub.cfg 2>/dev/null \
  && ok_ "菜单包含 recovery mode（启动失败首选入口）"

echo
echo "════════ 2. 磁盘与挂载 ════════"

BAD_UUID=0
while read -r uuid; do
  [ -n "$uuid" ] || continue
  if [ -e "/dev/disk/by-uuid/$uuid" ] || [ "$uuid" = "none" ]; then
    :
  else
    BAD_UUID=1; bad_ "fstab 中的 UUID $uuid 找不到对应设备"
  fi
done < <(awk '$1 ~ /^UUID=/ {sub("UUID=","",$1); print $1}' /etc/fstab 2>/dev/null)
[ $BAD_UUID -eq 0 ] && ok_ "/etc/fstab 所有 UUID 均可解析"

FREE_ROOT=$(df -Pm / | awk 'NR==2{print $4}')
[ "$FREE_ROOT" -gt 1024 ] && ok_ "根分区剩余 ${FREE_ROOT}MB" || bad_ "根分区空间不足 (${FREE_ROOT}MB)"

FREE_BOOT=$(df -Pm /boot 2>/dev/null | awk 'NR==2{print $4}')
[ -n "$FREE_BOOT" ] && { [ "$FREE_BOOT" -gt 50 ] && ok_ "/boot 剩余 ${FREE_BOOT}MB" || warn_ "/boot 空间紧张 (${FREE_BOOT}MB)"; }

echo
echo "════════ 3. 系统关键单元 ════════"

DEF_TARGET=$(systemctl get-default)
[ "$DEF_TARGET" = "graphical.target" ] && ok_ "默认目标 graphical.target" || warn_ "默认目标为 $DEF_TARGET"

for u in systemd-logind.service NetworkManager.service polkit.service dbus.service; do
  EN=$(systemctl is-enabled "$u" 2>/dev/null)
  case "$EN" in
    enabled|enabled-runtime|static|indirect) ok_ "$u = $EN" ;;
    *) bad_ "$u 状态异常 = ${EN:-unknown}" "sudo systemctl enable $u" ;;
  esac
done

# 显示管理器：Debian/Ubuntu 通过 display-manager.service 符号链接启用，
# gdm.service 本身显示 disabled 是正常的，不能直接判为异常
if [ -L /etc/systemd/system/display-manager.service ]; then
  DM_TARGET=$(readlink -f /etc/systemd/system/display-manager.service)
  if [ -f "$DM_TARGET" ]; then
    ok_ "显示管理器 -> $(basename "$DM_TARGET")（$(systemctl is-active display-manager.service 2>/dev/null)）"
  else
    bad_ "display-manager.service 指向不存在的文件: $DM_TARGET"
  fi
else
  bad_ "缺少 /etc/systemd/system/display-manager.service" "sudo systemctl enable gdm.service"
fi

FAILED=$(systemctl --failed --no-legend --no-pager 2>/dev/null | wc -l)
[ "$FAILED" -eq 0 ] && ok_ "当前无失败单元" || warn_ "有 $FAILED 个失败单元" "systemctl --failed"

# 被禁用单元里是否有启动链必需的
# 取「最新的非空」记录：dry-run 或异常中断可能留下 0 字节 tsv，
# 旧写法 ls|tail -1 会抓到它，且 grep -vqE 对空文件返回假 → 误报启动关键项（ISSUE-25）。
UNIT_FILE=""
for f in $(ls -t "$PROJECT_ROOT"/logs/disabled-units-*.tsv 2>/dev/null); do
  [ -s "$f" ] && { UNIT_FILE="$f"; break; }
done
if [ -n "$UNIT_FILE" ]; then
  CRIT="systemd-logind|NetworkManager.service|gdm.service|dbus|polkit|udev"
  HITS=$(grep -E "$CRIT" "$UNIT_FILE" 2>/dev/null || true)
  if [ -z "$HITS" ]; then
    ok_ "被禁用的 $(wc -l <"$UNIT_FILE") 个单元中无启动关键项 [$(basename "$UNIT_FILE")]"
  else
    bad_ "禁用列表包含启动关键单元" "$HITS"
  fi
else
  warn_ "未找到非空的禁用单元记录" "若从未执行过 03-perf-tune.sh 属正常"
fi

echo
echo "════════ 4. 本次改动项 ════════"

# zram
if [ -f /etc/systemd/zram-generator.conf ]; then
  if systemctl cat systemd-zram-setup@zram0.service >/dev/null 2>&1; then
    ok_ "zram generator 配置可被 systemd 解析"
  else
    warn_ "zram unit 未生成" "sudo systemctl daemon-reload"
  fi
fi
swapon --show | grep -q zram0 && ok_ "zram0 已激活" || warn_ "zram0 未激活（重启后由 generator 创建）"

# sysctl 语法
SYSCTL_BAD=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  key=$(echo "$line" | cut -d= -f1 | tr -d ' ')
  sysctl -n "$key" >/dev/null 2>&1 || { SYSCTL_BAD=1; bad_ "sysctl 未知键: $key"; }
done < /etc/sysctl.d/99-linux-tune.conf 2>/dev/null
[ $SYSCTL_BAD -eq 0 ] && ok_ "/etc/sysctl.d/99-linux-tune.conf 全部键有效"

# 登录 shell
USER_SHELL=$(getent passwd "$USER" | cut -d: -f7)
if [ -x "$USER_SHELL" ]; then
  ok_ "登录 shell $USER_SHELL 可执行"
else
  bad_ "登录 shell $USER_SHELL 不存在" "sudo chsh -s /bin/bash $USER"
fi
if [ "$USER_SHELL" = "/usr/bin/zsh" ]; then
  if zsh -n ~/.zshrc 2>/dev/null; then
    ok_ "~/.zshrc 语法正确（zsh -n）"
  else
    bad_ "~/.zshrc 有语法错误，登录后终端会报错" "zsh -n ~/.zshrc 查看行号"
  fi
  # 交互式加载测试（超时保护）
  if timeout 10 zsh -i -c exit >/dev/null 2>&1; then
    ok_ "~/.zshrc 可在 10s 内完整加载"
  else
    warn_ "~/.zshrc 加载超时或有报错" "可能是 fastfetch/compinit 较慢，可接受"
  fi
fi

# environment.d 语法（每行必须 KEY=VALUE）
ENVF="$HOME/.config/environment.d/99-input-method.conf"
if [ -f "$ENVF" ]; then
  if grep -qvE '^\s*(#|$|[A-Za-z_][A-Za-z0-9_]*=)' "$ENVF"; then
    bad_ "$ENVF 存在格式错误的行" "每行必须是 KEY=VALUE"
  else
    ok_ "输入法环境变量文件格式正确"
  fi
fi

# 主题（不影响启动，仅提示）
gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | grep -q WhiteSur \
  && warn_ "GTK 主题已设为 WhiteSur（若主题文件损坏，桌面仍可进，只是外观异常）"

echo
echo "════════ 汇总 ════════"
printf '  通过 %s%d%s   警告 %s%d%s   失败 %s%d%s\n' \
  "$C_OK" "$PASS" "$C_RESET" "$C_WARN" "$WARN" "$C_RESET" "$C_ERR" "$FAIL" "$C_RESET"
echo
if [ $FAIL -eq 0 ]; then
  ok "可以安全重启: sudo reboot"
  [ $WARN -gt 0 ] && warn "有 $WARN 项警告，属非阻断问题"
else
  printf '%s不要重启%s，先修复上面的 ✗ 项，或执行 ./scripts/rollback.sh --list\n' "$C_ERR" "$C_RESET"
  exit 1
fi
