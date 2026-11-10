#!/usr/bin/env bash
# ============================================================================
# 03-perf-tune.sh - 阶段 2：性能优化
#   1) 启动关键路径（NetworkManager-wait-online / GRUB 超时）
#   2) 冗余服务裁剪（cloud-init / apport / cups / sssd / ModemManager ...）
#      avahi-daemon 属白名单，不再禁用（mDNS 设备发现，见 ADR-14）
#   3) zram 压缩内存
#   4) sysctl 内核参数
#   5) crashkernel 释放预留内存
# 用法: ./scripts/03-perf-tune.sh [--dry-run]
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

SUDO="sudo"
[ $DRY_RUN -eq 1 ] && SUDO="echo [dry-run] sudo"

# dry-run 是只读预览，绝不生成真实回滚记录：
# 否则会在 logs/ 留下 0 字节 tsv，被 preboot-check / rollback 当作最新记录取到（ISSUE-25）。
if [ $DRY_RUN -eq 1 ]; then
  UNIT_STATE=/dev/null
else
  UNIT_STATE="$PROJECT_ROOT/logs/disabled-units-$RUN_ID.tsv"
  : >"$UNIT_STATE"
fi

step "阶段 2 - 性能优化 $([ $DRY_RUN -eq 1 ] && echo '(dry-run 预览)')"
[ $DRY_RUN -eq 0 ] && require_sudo

# ---- 禁止精简白名单（ADR-14 / ISSUE-18）------------------------------------
# 阶段 2 曾按「桌面机不需要」批量禁用 21 个单元，未考虑后续功能依赖，
# 结果 avahi-daemon 被裁掉后手机互联完全无法发现对端（ISSUE-16）。
# 这里做成脚本级硬约束：disable_unit 对白名单单元直接拒绝，不靠注释自觉。
#
# 【新增任何禁用项前，必须走完这 4 步依赖检查】
#   1. 查它是否被按需功能依赖：网络发现(avahi/mDNS)、打印(cups.socket)、
#      蓝牙、音频(PipeWire/WirePlumber)、登录与显示管理(logind/gdm/polkit)。
#   2. 查启动关键路径：preboot-check.sh 的「系统关键单元」清单与之取交集。
#   3. 查已有回滚记录 logs/disabled-units-*.tsv，确认不是已恢复过的单元。
#   4. 确认后在此处同步更新白名单说明 + docs/03-性能优化.md 的服务表。
# 原则：只禁「明确无依赖且可随时恢复」的单元；有疑问就保留。
PROTECTED_UNITS=(
  avahi-daemon.service avahi-daemon.socket
  NetworkManager.service systemd-logind.service polkit.service dbus.service
  display-manager.service gdm.service gdm3.service
  bluetooth.service
  pipewire.service pipewire-pulse.service wireplumber.service
)

is_protected() {
  local u="$1" p
  for p in "${PROTECTED_UNITS[@]}"; do
    [ "$u" = "$p" ] && return 0
  done
  return 1
}

# ---- 工具函数 --------------------------------------------------------------
disable_unit() {
  local u="$1" reason="${2:-}"
  if is_protected "$u"; then
    warn "拒绝禁用 $u：白名单保护（ADR-14）；如需调整先做依赖检查"
    return 1
  fi
  if systemctl is-enabled --quiet "$u" 2>/dev/null; then
    printf '%s\t%s\n' "$u" "$(systemctl is-enabled "$u" 2>/dev/null)" >>"$UNIT_STATE"
    if [ $DRY_RUN -eq 1 ]; then
      log "[dry-run] 将禁用 $u  ($reason)"
    else
      $SUDO systemctl disable --now "$u" >/dev/null 2>&1 \
        && ok "已禁用 $u  $reason" \
        || warn "禁用失败 $u"
    fi
  else
    log "跳过（未启用）: $u"
  fi
}

# ---- 1. 启动关键路径 -------------------------------------------------------
step "1/6 启动关键路径"
disable_unit NetworkManager-wait-online.service "开机阻塞 6.6s，桌面机无需等待网络"

# ---- 2. 冗余服务 -----------------------------------------------------------
step "2/6 冗余服务裁剪"
for u in cloud-init-main.service cloud-init-local.service cloud-init-network.service \
         cloud-config.service cloud-final.service; do
  disable_unit "$u" "云镜像残留"
done
[ $DRY_RUN -eq 0 ] && $SUDO touch /etc/cloud/cloud-init.disabled

# 白名单：avahi-daemon 不可禁用
# KDE Connect / GSConnect / LocalSend 依赖 mDNS(DNS-SD) 在同一 Wi-Fi 内发现设备。
# 早期版本曾把它当作"桌面机冗余"裁掉，导致手机互联完全无法发现对端（ISSUE-16 / ADR-14）。
# 若确需禁用，必须先确认没有任何局域网发现类功能在用。
for u in apport.service whoopsie.path \
         ModemManager.service openvpn.service sssd.service sssd-autofs.socket \
         sssd-nss.socket sssd-pac.socket sssd-pam.socket sssd-ssh.socket sssd-sudo.socket; do
  disable_unit "$u" "桌面机冗余"
done

# 防止历史配置里 avahi 仍处于 disabled：主动恢复
if [ $DRY_RUN -eq 0 ] && ! systemctl is-enabled --quiet avahi-daemon.service 2>/dev/null; then
  $SUDO systemctl enable --now avahi-daemon.service >/dev/null 2>&1 \
    && ok "已恢复 avahi-daemon（mDNS 设备发现，ADR-14）"
fi

# cups 只关 service，保留 socket 以便按需唤醒
disable_unit cups.service "保留 cups.socket 按需激活"
disable_unit cups-browsed.service "网络打印机发现"
disable_unit kdump-tools.service "无内核转储需求"

if [ $DRY_RUN -eq 0 ]; then
  backup_file /etc/default/apport
  if [ -f /etc/default/apport ]; then
    $SUDO sed -i 's/^enabled=1/enabled=0/' /etc/default/apport
    ok "已关闭 apport 崩溃上报"
  fi
fi

# ---- 3. zram ---------------------------------------------------------------
step "3/6 启用 zram 压缩内存"
if [ $DRY_RUN -eq 0 ]; then
  apt_install systemd-zram-generator

  ZRAM_CONF=/etc/systemd/zram-generator.conf
  backup_file "$ZRAM_CONF"
  $SUDO tee "$ZRAM_CONF" >/dev/null <<'EOF'
# 由 linux-tune 生成：zram0 作为高优先级交换，减少 SSD 写入
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl start systemd-zram-setup@zram0.service 2>/dev/null || true
  if swapon --show | grep -q zram0; then
    ok "zram0 已启用：$(swapon --show=NAME,SIZE --noheadings | grep zram0)"
  else
    warn "zram0 未生效，重启后再确认"
  fi
fi

# ---- 4. sysctl -------------------------------------------------------------
step "4/6 内核参数调优"
SYSCTL_CONF=/etc/sysctl.d/99-linux-tune.conf
if [ $DRY_RUN -eq 0 ]; then
  backup_file "$SYSCTL_CONF"
  $SUDO tee "$SYSCTL_CONF" >/dev/null <<'EOF'
# 由 linux-tune 生成
# --- 内存/交换：配合 zram，尽量不用磁盘 swap ---
vm.swappiness = 10
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
# --- 脏页回写：降低突发 IO 抖动 ---
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 1500
# --- 网络：BBR 拥塞控制 + fq 队列 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 4096
# --- 文件监视/句柄：IDE、Webpack、文件同步友好 ---
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
fs.file-max = 2097152
EOF
  $SUDO sysctl --system >/dev/null 2>&1 && ok "sysctl 已加载" || warn "sysctl 加载有警告"
  log "swappiness=$(cat /proc/sys/vm/swappiness)  拥塞控制=$(sysctl -n net.ipv4.tcp_congestion_control)"
fi

# ---- 5. GRUB：超时 + crashkernel -------------------------------------------
step "5/6 GRUB 超时与 crashkernel"
GRUB_FILE=/etc/default/grub
if [ $DRY_RUN -eq 0 ]; then
  backup_file "$GRUB_FILE"
  # 超时 5s -> 1s
  $SUDO sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$GRUB_FILE"
  grep -q '^GRUB_TIMEOUT_STYLE=' "$GRUB_FILE" \
    && $SUDO sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' "$GRUB_FILE" \
    || echo 'GRUB_TIMEOUT_STYLE=menu' | $SUDO tee -a "$GRUB_FILE" >/dev/null
  # crashkernel=0：去掉 320M 预留（无 kdump 需求）
  if grep -q 'crashkernel=' "$GRUB_FILE"; then
    $SUDO sed -i -E 's/crashkernel=[^ "]*//g' "$GRUB_FILE"
  fi
  if ! grep -q 'crashkernel=0' "$GRUB_FILE"; then
    $SUDO sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")(.*)"/\1\2 crashkernel=0"/' "$GRUB_FILE"
  fi
  # 关键：/etc/default/grub.d/*.cfg 里的 crashkernel 会在主配置之后追加，
  # 内核采用后出现者为准，必须先清掉，否则 crashkernel=0 无效
  for f in /etc/default/grub.d/*.cfg; do
    [ -f "$f" ] || continue
    if grep -q 'crashkernel=' "$f"; then
      backup_file "$f"
      $SUDO sed -i -E 's/ ?crashkernel=[^ "]*//g' "$f"
      ok "已清理 $(basename "$f") 中的 crashkernel 覆盖"
    fi
  done
  $SUDO update-grub >/dev/null 2>&1 && ok "GRUB 已更新（超时 1s，crashkernel=0）" || warn "update-grub 失败"
fi

# ---- 6. journald -----------------------------------------------------------
step "6/6 限制日志占用"
JOURNAL_DIR=/etc/systemd/journald.conf.d
if [ $DRY_RUN -eq 0 ]; then
  $SUDO mkdir -p "$JOURNAL_DIR"
  $SUDO tee "$JOURNAL_DIR/99-linux-tune.conf" >/dev/null <<'EOF'
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
RuntimeMaxUse=50M
Compress=yes
EOF
  $SUDO systemctl restart systemd-journald 2>/dev/null && ok "journald 限制为 200M"
fi

step "完成"
if [ $DRY_RUN -eq 0 ]; then
  log "被禁用的单元记录在: ${UNIT_STATE#$PROJECT_ROOT/}"
  log "变更登记: logs/changes.tsv"
  log "生效时间：GRUB 与 crashkernel 需重启；zram/sysctl/服务已即时生效"
  echo
  systemd-analyze 2>/dev/null | head -2
  free -h | head -3
fi
