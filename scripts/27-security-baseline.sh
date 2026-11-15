#!/usr/bin/env bash
# ============================================================================
# 27-security-baseline.sh - 安全基线：默认拒绝入站 + 安全更新 + 端口审计
#
# 对应验收指标：A-05（开放端口 0）、A-06（CVE 修复 < 72h）
#
# 为什么允许放行 5353/udp：avahi 的 mDNS 需要入站组播；阶段 2 曾误禁 avahi
# 导致设备发现失效（ISSUE-16），这里显式放行，避免「安全了但功能坏了」。
#
# 用法:
#   ./scripts/27-security-baseline.sh --status        # 只读
#   ./scripts/27-security-baseline.sh --audit         # 端口审计表
#   ./scripts/27-security-baseline.sh --install       # 落地（会启用 ufw）
#   ./scripts/27-security-baseline.sh --install --dry-run
#   ./scripts/27-security-baseline.sh --disable       # 关掉 ufw（仅回退用）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ACTION=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --status)  ACTION=status ;;
    --audit)   ACTION=audit ;;
    --install) ACTION=install ;;
    --disable) ACTION=disable ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=status

have_sudo() { sudo -n true 2>/dev/null; }

ufw_status() { sudo -n ufw status verbose 2>/dev/null | head -20; }

print_ports() {
  printf '  %-8s %-40s %-20s %s\n' 协议 本地地址 进程 暴露面
  # ss 需要 root 才能看到其它用户的进程名；拿不到就如实显示 ?，不猜。
  local S=""
  have_sudo && S="sudo -n"
  # ss -H 无表头：proto state recv-q send-q local peer process
  $S ss -tulpnH 2>/dev/null | while read -r proto _ _ _ local _ prog; do
    [ -n "$local" ] || continue
    addr="${local%:*}"
    case "$addr" in
      127.*|::1|\[::1\]|localhost) face="仅本机" ;;
      0.0.0.0|\[::\]|\*)           face="全接口" ;;
      *)                           face="特定地址" ;;
    esac
    pname="$(printf '%s' "$prog" | sed -nE 's/.*users:\(\("([^"]+)".*/\1/p')"
    printf '  %-8s %-40s %-20s %s\n' "$proto" "$local" "${pname:-?}" "$face"
  done
}

case "$ACTION" in
  status)
    echo
    echo "════════ 安全基线 ════════"
    if ! have ufw; then
      echo "  ufw         : 未安装"
    elif ! have_sudo; then
      echo "  ufw         : 无法读取（需要免密 sudo；不猜测状态）"
    else
      U="$(sudo -n ufw status 2>/dev/null | head -1)"
      echo "  ufw         : ${U:-未知}"
      sudo -n ufw status numbered 2>/dev/null | sed -n '2,12p' | sed 's/^/    /'
    fi
    echo "  自动更新    : $(systemctl is-enabled unattended-upgrades.service 2>/dev/null || echo 未安装)"
    echo "  更新定时器  : $(systemctl is-active apt-daily-upgrade.timer 2>/dev/null || echo 未知)"
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
      echo "  自动更新配置: $(tr '\n' ' ' </etc/apt/apt.conf.d/20auto-upgrades | sed 's/  */ /g')"
    else
      echo "  自动更新配置: 缺失（apt 不会自动装安全更新）"
    fi
    echo "  安全源      : $(grep -c 'security' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null || echo 0) 处（>0 表示含 -security 源）"
    ;;
  audit)
    echo
    echo "════════ 端口审计（$(date '+%F %T')）════════"
    print_ports
    OUT="$LOG_DIR/port-audit-$RUN_ID.txt"
    { echo "# 端口审计 $(date '+%F %T')"; ss -tulpnH; } >"$OUT"
    echo
    log "原始输出: ${OUT#$PROJECT_ROOT/}（含进程与地址，勿公开分享）"
    ;;
  disable)
    have_sudo || die "需要免密 sudo"
    if [ "$DRY" -eq 1 ]; then
      log "[dry-run] ufw disable"
    else
      sudo -n ufw disable && ok "ufw 已关闭（回退到未启用状态）"
    fi
    ;;
  install)
    have_sudo || die "需要免密 sudo（脚本会改防火墙与 apt 配置）"
    step "1/3 入站默认拒绝"
    if [ "$DRY" -eq 1 ]; then
      log "[dry-run] ufw default deny incoming / allow outgoing / allow 5353/udp / enable"
    else
      sudo -n ufw default deny incoming >/dev/null
      sudo -n ufw default allow outgoing >/dev/null
      # mDNS：avahi 需要入站组播，否则局域网设备发现失效（ISSUE-16）
      sudo -n ufw allow 5353/udp comment 'mdns/avahi' >/dev/null 2>&1 || true
      sudo -n ufw --force enable >/dev/null && ok "ufw 已启用"
      sudo -n ufw status verbose | head -12 | sed 's/^/    /'
    fi

    step "2/3 安全更新通道"
    if ! pkg_installed unattended-upgrades; then
      if [ "$DRY" -eq 1 ]; then
        log "[dry-run] apt install unattended-upgrades"
      else
        apt_install unattended-upgrades || warn "unattended-upgrades 安装失败"
      fi
    else
      ok "unattended-upgrades 已安装"
    fi
    AUTO="/etc/apt/apt.conf.d/20auto-upgrades"
    if [ "$DRY" -eq 1 ]; then
      log "[dry-run] 写入 $AUTO（Update-Package-Lists/Unattended-Upgrade 均为 1）"
    else
      [ -f "$AUTO" ] && backup_file "$AUTO"
      printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
        | sudo -n tee "$AUTO" >/dev/null && ok "$AUTO 已写入"
      sudo -n systemctl enable --now unattended-upgrades.service 2>/dev/null || true
      systemctl is-enabled unattended-upgrades.service 2>/dev/null | sed 's/^/    service: /'
    fi

    step "3/3 端口审计"
    print_ports
    echo
    log "回退: $0 --disable（ufw）；自动更新可 systemctl disable unattended-upgrades"
    log "说明见 docs/27-安全基线.md（含误封排查）"
    ;;
esac
