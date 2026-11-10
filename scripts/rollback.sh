#!/usr/bin/env bash
# ============================================================================
# rollback.sh - 一键回滚
# 用法:
#   ./scripts/rollback.sh --list                       列出所有备份批次
#   ./scripts/rollback.sh --restore <RUN_ID>           还原该批次全部文件与服务
#   ./scripts/rollback.sh --restore <RUN_ID> --dry-run 预览将还原什么
#   ./scripts/rollback.sh --restore <RUN_ID> --only /etc/default/grub
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

ACTION=""; TARGET=""; ONLY=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) ACTION=list ;;
    --restore) ACTION=restore; TARGET="${2:-}"; shift ;;
    --only) ONLY="${2:-}"; shift ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

# ---- 列表 ------------------------------------------------------------------
if [ "$ACTION" = "list" ] || [ -z "$ACTION" ]; then
  echo "备份批次："
  echo
  for d in "$BACKUP_DIR"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    nfiles=$(find "$d" -type f 2>/dev/null | wc -l)
    units="$LOG_DIR/disabled-units-$id.tsv"
    nunit=0; [ -f "$units" ] && nunit=$(wc -l <"$units")
    printf '  %-20s 文件 %-4s 服务 %-3s\n' "$id" "$nfiles" "$nunit"
  done
  echo
  echo "用法: $0 --restore <RUN_ID>"
  exit 0
fi

# ---- 还原 ------------------------------------------------------------------
SRC="$BACKUP_DIR/$TARGET"
[ -d "$SRC" ] || die "备份批次不存在: $TARGET（用 --list 查看）"

restore_one() {
  local from="$1" to="$2"
  if [ $DRY -eq 1 ]; then
    log "[dry-run] $from -> $to"
  else
    sudo cp -a "$from" "$to" && ok "已还原 $to"
  fi
}

step "回滚批次 $TARGET $([ $DRY -eq 1 ] && echo '(dry-run)')"

if [ -d "$SRC/files" ]; then
  log "还原文件..."
  while IFS= read -r f; do
    rel="${f#$SRC/files}"
    [ -n "$ONLY" ] && [ "$rel" != "$ONLY" ] && continue
    restore_one "$f" "$rel"
  done < <(find "$SRC/files" -type f 2>/dev/null)
fi

if [ -d "$SRC/dirs" ]; then
  log "还原目录..."
  while IFS= read -r d; do
    rel="${d#$SRC/dirs}"
    [ -n "$ONLY" ] && [ "$rel" != "$ONLY" ] && continue
    if [ $DRY -eq 1 ]; then
      log "[dry-run] 目录 $rel"
    else
      sudo rm -rf "$rel" && sudo cp -a "$d" "$rel" && ok "已还原目录 $rel"
    fi
  done < <(find "$SRC/dirs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# 服务还原
UNITS="$LOG_DIR/disabled-units-$TARGET.tsv"
if [ -f "$UNITS" ] && [ -z "$ONLY" ]; then
  log "恢复被禁用的服务..."
  while IFS=$'\t' read -r u _state; do
    [ -z "$u" ] && continue
    if [ $DRY -eq 1 ]; then
      log "[dry-run] enable $u"
    else
      sudo systemctl enable "$u" >/dev/null 2>&1 && ok "已重新启用 $u"
    fi
  done <"$UNITS"
fi

if [ $DRY -eq 0 ]; then
  if [ -f /etc/default/grub ] && [ -n "$(ls "$SRC/files/etc/default/grub" 2>/dev/null)" ]; then
    sudo update-grub >/dev/null 2>&1 && ok "已重新生成 GRUB 配置"
  fi
  if [ -d /etc/sysctl.d ]; then
    sudo sysctl --system >/dev/null 2>&1 || true
  fi
  ok "回滚完成，建议重启使全部改动失效"
  warn "GRUB 超时、crashkernel 需要重启才恢复"
fi
