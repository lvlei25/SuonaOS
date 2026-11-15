#!/usr/bin/env bash
# ============================================================================
# 26-snapshot.sh - 系统级快照（Timeshift / rsync on ext4）
#
# 与 rollback.sh 的分工（ADR-34）：
#   rollback.sh   脚本级变更，按 backup/<RUN_ID> 精确还原单个文件/服务状态
#   Timeshift     系统级状态，整机回滚到某个时间点（装驱动、改内核、误删文件）
# 两者不互相替代：滚脚本不会撤销 apt 装的东西，Timeshift 也不认识 changes.tsv。
#
# 为什么不用 Btrfs（ADR-34）：
#   本机 ext4 单分区 + Windows 双系统，btrfs-convert 在线转换风险不可控；
#   Btrfs + snapper 留给 UM870 出厂镜像（SREQ-09）。
#
# 诚实边界：同盘快照只能防误操作，**防不了盘损**。真正的备份必须异地。
#
# 用法:
#   ./scripts/26-snapshot.sh --install             # 安装并检查配置
#   ./scripts/26-snapshot.sh --setup               # 调起 Timeshift 配置向导
#   ./scripts/26-snapshot.sh --snapshot "改前基线"  # 立即建快照
#   ./scripts/26-snapshot.sh --status
#   ./scripts/26-snapshot.sh --restore-help        # 恢复步骤（不自动执行）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="/etc/timeshift/timeshift.json"
ACTION=""
COMMENT="manual"
AUTO_CONFIG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install)  ACTION=install ;;
    --setup)    ACTION=setup ;;
    --snapshot) ACTION=snapshot; COMMENT="${2:-manual}"; shift ;;
    --status)   ACTION=status ;;
    --auto-config) AUTO_CONFIG=1 ;;
    --restore-help) ACTION=restore_help ;;
    -h|--help)  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=status

have_sudo() { sudo -n true 2>/dev/null; }

list_snapshots() {
  sudo -n timeshift --list 2>/dev/null | sed -n '/Num/,/^$/p'
}

snapshot_count() {
  sudo -n timeshift --list 2>/dev/null | awk '/^[[:space:]]*[0-9]+[[:space:]]+>/ {n++} END{print n+0}'
}

# 非交互初始化：Timeshift 的 --setup 是 ncurses，脚本里无法可靠驱动。
# 这里按官方 JSON 结构写最小可用配置（rsync 模式、目标=根分区、排除 /home）。
# 若版本不接受该结构，timeshift --list 会报错，此时请改用 --setup 向导。
write_auto_config() {
  local uuid
  uuid="$(findmnt -no UUID / 2>/dev/null)"
  [ -n "$uuid" ] || die "读不到根分区 UUID（findmnt）"
  [ -f "$CONF" ] && backup_file "$CONF"
  sudo -n tee "$CONF" >/dev/null <<EOF
{
  "backup_device_uuid" : "$uuid",
  "parent_device_uuid" : "",
  "do_first_run" : "no",
  "btrfs_mode" : "false",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "false",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "5",
  "count_boot" : "5",
  "snapshots" : [],
  "exclude" : [],
  "exclude-apps" : []
}
EOF
  ok "已写入 $CONF（rsync / 目标 UUID $uuid）"
  warn "exclude 留空：实测把 /home/** 写进 exclude 会让 timeshift 在建快照时崩溃"
  warn "  （string_strip assertion，ISSUE-38）；代价是首份快照包含 /home，本机约 42G"
}

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  echo
  echo "════════ 系统快照（Timeshift）════════"
  if ! have timeshift; then
    echo "  状态        : 未安装（--install 安装）"
    echo "  root fs     : $(findmnt -no FSTYPE / 2>/dev/null)（rsync 模式，非 Btrfs）"
    exit 0
  fi
  if ! have_sudo; then
    warn "免密 sudo 不可用，无法读取快照列表（不猜测、不编造）"
    exit 1
  fi
  if [ ! -f "$CONF" ]; then
    echo "  配置        : 未初始化（/etc/timeshift/timeshift.json 不存在）"
    echo "  下一步      : $0 --setup"
    exit 0
  fi
  N="$(snapshot_count)"
  echo "  快照数量    : ${N}"
  echo "  root fs     : $(findmnt -no FSTYPE / 2>/dev/null) / $(findmnt -no SOURCE / 2>/dev/null)"
  echo "  快照占用    : $(sudo -n du -sh /timeshift 2>/dev/null | cut -f1 || echo '不可读')"
  echo "  剩余空间    : $(df -Ph / | awk 'NR==2{print $4" / "$2}')"
  echo "  最近一次    : $(sudo -n timeshift --list 2>/dev/null | awk '/^[[:space:]]*[0-9]+[[:space:]]+>/{print $3" "$4; exit}')"
  echo "  与脚本回滚  : rollback.sh 按批次还原文件；本脚本按时间点还原系统（ADR-34）"
  exit 0
fi

if [ "$ACTION" = restore_help ]; then
  cat <<'EOF'

Timeshift 恢复不在脚本里自动执行——它在图形/引导环境下操作，误点代价极高。

推荐顺序：
  1) 能进桌面：sudo timeshift --restore   （交互式，按提示选快照）
  2) 进不了桌面：GRUB → recovery mode → root shell
        mount -o remount,rw /
        timeshift --restore
  3) 系统完全起不来：Live USB → 安装 timeshift → 指定根分区 → 选快照恢复
  4) 只想救单个文件：不用 Timeshift，去 /timeshift/snapshots/<时间>/localhost/ 里取

恢复前先确认：
  - 目标快照的时间点（Timeshift 按创建顺序编号）
  - 当前是否有未提交的代码/文档（快照只回滚系统，不回滚 /home 之外的业务数据）
EOF
  exit 0
fi

if [ "$ACTION" = setup ]; then
  have timeshift || die "先执行 --install"
  if [ -t 0 ]; then
    log "调起 Timeshift 配置向导（选 rsync / 目标盘 / 排除 /home）"
    sudo timeshift --setup
  else
    warn "当前不是交互终端，无法调起向导"
    log "请在终端手工执行: sudo timeshift --setup"
    log "选择：RSYNC 模式 → 目标为本机根分区 → 排除 /home（业务数据另备）"
  fi
  exit 0
fi

if [ "$ACTION" = install ]; then
  step "1/3 安装 timeshift"
  if have timeshift; then
    ok "已安装"
  else
    apt_install timeshift || die "timeshift 安装失败"
  fi

  step "2/3 检查配置"
  if [ -f "$CONF" ]; then
    ok "配置存在: $CONF"
    grep -E '"btrfs_mode"|"schedule_daily"|"count_daily"' "$CONF" 2>/dev/null | sed 's/^/    /' || true
  elif [ "$AUTO_CONFIG" -eq 1 ]; then
    write_auto_config
  else
    warn "尚未初始化配置（首次必须走一次向导）"
    if [ -t 0 ]; then
      log "现在调起向导；选 RSYNC 模式、目标盘为本机根分区、排除 /home"
      sudo timeshift --setup || warn "向导中断，可稍后执行 $0 --setup"
    else
      log "非交互环境：二选一"
      log "  a) $0 --install --auto-config   （按根分区 UUID 写最小配置）"
      log "  b) sudo timeshift --setup       （交互向导，选 RSYNC / 根分区 / 排除 /home）"
    fi
  fi

  step "3/3 校验配置可用性（不自动建快照）"
  if [ -f "$CONF" ]; then
    # timeshift --list 在「没有快照」时返回非 0，但配置其实可用；
    # 因此按输出里的 Mode/Device 判定，而不是看退出码（ADR-19 同类教训）。
    # 注意：脚本开了 pipefail，`cmd | grep` 会继承 cmd 的非 0 状态，必须先落变量。
    TS_OUT="$(sudo -n timeshift --list 2>&1 || true)"
    if printf '%s' "$TS_OUT" | grep -qE '^(Mode|Device)[[:space:]]*:'; then
      ok "timeshift 可读配置（当前快照 $(snapshot_count) 个）"
      log "首次基线请手动执行: $0 --snapshot \"基线\"（整盘写入，通常几分钟）"
    else
      warn "配置写入后 timeshift 仍不可用；改用向导: sudo timeshift --setup"
    fi
  else
    warn "配置未初始化，跳过校验"
  fi
  exit 0
fi

if [ "$ACTION" = snapshot ]; then
  have timeshift || die "未安装 timeshift（--install）"
  [ -f "$CONF" ] || die "配置未初始化，先执行 $0 --setup"
  have_sudo || die "需要免密 sudo"
  step "创建快照: $COMMENT"
  sudo -n timeshift --create --comments "suona: $COMMENT" --tags D --scripted \
    && ok "快照完成" || die "快照失败"
  echo
  log "当前快照数: $(snapshot_count)"
  exit 0
fi
