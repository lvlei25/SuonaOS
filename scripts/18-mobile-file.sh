#!/usr/bin/env bash
# ============================================================================
# 18-mobile-file.sh - 手机文件互传（ADB，复用 mobile-connect 的记忆地址）
#   补 scrcpy 的能力缺口：scrcpy 只支持「拖入」，不支持「拖出」
#   默认推送目标 /sdcard/Download/，默认拉取到 ~/Downloads/
# 用法:
#   ./scripts/18-mobile-file.sh --push <文件或目录>...   # 电脑 → 手机
#   ./scripts/18-mobile-file.sh --pull <手机路径>...      # 手机 → 电脑
#   ./scripts/18-mobile-file.sh --find [关键词]           # 按文件名搜索，选择编号拉取
#   ./scripts/18-mobile-file.sh --ls [/sdcard/Download]  # 列目录
#   ./scripts/18-mobile-file.sh --to <路径> --push ...   # 覆盖目标位置
#   ./scripts/18-mobile-file.sh --status
#   ./scripts/18-mobile-file.sh --no-open --pull ...     # 拉完不自动打开目录
#   注：--pull / --find 成功后默认用 xdg-open 打开目标目录
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONF="$HOME/.config/linux-tune/mobile.conf"
DEST_REMOTE="/sdcard/Download"
# 拉取目录跟系统「下载」走：中文环境是 ~/下载，英文环境是 ~/Downloads。
# 不写死路径，否则会在 ~ 下多建一个没人看的 Downloads 目录。
DEST_LOCAL=""
if command -v xdg-user-dir >/dev/null 2>&1; then
  DEST_LOCAL="$(xdg-user-dir DOWNLOAD 2>/dev/null)"
fi
[ -n "${DEST_LOCAL:-}" ] && [ "$DEST_LOCAL" != "$HOME" ] || DEST_LOCAL="$HOME/Downloads"
LAST_ADDR=""
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# usage 必须先定义：参数解析里 -h/--help 会直接调用它
usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

ACTION=""
TARGET=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --push|--pull|--ls|--status|--find) ACTION="${1#--}" ;;
    --to) TARGET="${2:-}"; shift ;;
    --no-open) NO_OPEN=1 ;;
    -h|--help) usage; exit 0 ;;
    --*) die "未知参数: $1" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

[ -n "$ACTION" ] || { usage; exit 1; }

get_device() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 !~ /^emulator/ {print $1; exit}'
}

# 有设备直接用；没有就复用 mobile.conf 里记住的地址尝试一次。
# 结果写全局 DEV：命令替换里的 exit 不会退出主脚本，所以不在函数里 die。
ensure_device() {
  DEV="$(get_device)"
  if [ -z "$DEV" ] && [ -n "$LAST_ADDR" ]; then
    log "当前无设备，尝试复用已保存地址 $LAST_ADDR"
    timeout 10 adb connect "$LAST_ADDR" >/dev/null 2>&1
    sleep 1
    DEV="$(get_device)"
  fi
}

need_device() {
  ensure_device
  [ -n "$DEV" ] || die "没有已连接设备。先执行 ./scripts/mobile-connect.sh --status 诊断（多为无线调试已关闭）"
}

# 拉完打开目标目录：启动器场景下用户不用再去文件管理器找。
# 失败不报错（无 GUI、无 xdg-open 都属正常），也不阻塞脚本退出。
open_dir() {
  local d="$1"
  [ "${NO_OPEN:-0}" = "1" ] && return 0
  [ -d "$d" ] || return 0
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$d" >/dev/null 2>&1 &
    log "已打开目录: $d"
  else
    warn "无 xdg-open，文件在: $d"
  fi
}

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  adb devices -l
  echo "已保存地址  : ${LAST_ADDR:-无}"
  echo "默认推送目标: $DEST_REMOTE"
  echo "默认拉取目录: $DEST_LOCAL"
  if [ -d "$DEST_LOCAL" ]; then
    echo "本地目录    : 存在"
  else
    echo "本地目录    : 不存在（拉取时自动创建）"
  fi
  exit 0
fi

# ---- ls --------------------------------------------------------------------
if [ "$ACTION" = ls ]; then
  need_device
  REMOTE="${TARGET:-${ARGS[0]:-$DEST_REMOTE}}"
  echo "== $REMOTE =="
  adb -s "$DEV" shell ls -la "$REMOTE" 2>&1 | sed 's/\r$//' | head -60
  exit 0
fi

# ---- push ------------------------------------------------------------------
if [ "$ACTION" = push ]; then
  [ ${#ARGS[@]} -gt 0 ] || die "用法: --push <文件或目录>..."
  need_device
  REMOTE="${TARGET:-$DEST_REMOTE}"
  adb -s "$DEV" shell mkdir -p "$REMOTE" >/dev/null 2>&1
  ok_n=0; bad_n=0
  for f in "${ARGS[@]}"; do
    if [ ! -e "$f" ]; then
      warn "跳过（不存在）: $f"
      bad_n=$((bad_n + 1))
      continue
    fi
    name="$(basename "$f")"
    log "推送 $name → $REMOTE/"
    if adb -s "$DEV" push "$f" "$REMOTE/" 2>&1 | sed 's/\r$//' | tail -1; then
      ok_n=$((ok_n + 1))
    else
      warn "失败: $f"
      bad_n=$((bad_n + 1))
    fi
  done
  echo
  if [ "$bad_n" -eq 0 ]; then
    ok "已推送 $ok_n 项到 $REMOTE/"
  else
    warn "成功 $ok_n 项，失败 $bad_n 项"
  fi
  exit 0
fi

# ---- pull ------------------------------------------------------------------
if [ "$ACTION" = pull ]; then
  [ ${#ARGS[@]} -gt 0 ] || die "用法: --pull <手机路径>..."
  need_device
  LOCAL="${TARGET:-$DEST_LOCAL}"
  mkdir -p "$LOCAL"
  ok_n=0; bad_n=0
  for p in "${ARGS[@]}"; do
    log "拉取 $p → $LOCAL/"
    if adb -s "$DEV" pull "$p" "$LOCAL/" 2>&1 | sed 's/\r$//' | tail -1; then
      ok_n=$((ok_n + 1))
    else
      warn "失败: $p"
      bad_n=$((bad_n + 1))
    fi
  done
  echo
  if [ "$bad_n" -eq 0 ]; then
    ok "已拉取 $ok_n 项到 $LOCAL/"
    open_dir "$LOCAL"
  else
    warn "成功 $ok_n 项，失败 $bad_n 项"
  fi
  exit 0
fi

# ---- find（按文件名搜索并拉取）--------------------------------------------
# 启动器入口：不需要记路径，输个名字就能把文件捞出来。
if [ "$ACTION" = find ]; then
  need_device
  LOCAL="${TARGET:-$DEST_LOCAL}"

  KW="${ARGS[0]:-}"
  if [ -z "$KW" ]; then
    cat <<'HINT'

  输入文件名关键词（部分匹配即可）：
    IMG_2024    文件名含 IMG_2024
    *.pdf       按后缀
    报告         中文名
HINT
    printf '  关键词: '
    read -r KW || true
  fi
  [ "$KW" = "q" ] && { log '已取消'; exit 0; }
  [ -n "$KW" ] || die '未输入关键词'

  # 没写通配符时自动前后包 *
  case "$KW" in
    *\**|*\?*) PAT="$KW" ;;
    *)         PAT="*${KW}*" ;;
  esac

  log "搜索手机文件: $PAT"
  # </dev/null 必须加：adb shell 会继承并吞掉 stdin，导致后面的 read 读到 EOF，
  # 表现成「明明选了编号却按全部拉取」。
  HITS="$(adb -s "$DEV" shell \
    "find /sdcard/DCIM /sdcard/Download /sdcard/Pictures /sdcard/Movies /sdcard/Documents -type f -iname '$PAT' 2>/dev/null" \
    </dev/null | tr -d '\r' | grep -v '^$' | head -50)"

  [ -n "$HITS" ] || die "未找到匹配「$KW」的文件（换个更短的关键词，或先 --ls 看目录）"

  N=0
  printf '\n  匹配结果：\n'
  while IFS= read -r f; do
    N=$((N + 1))
    printf '  %2d) %s\n' "$N" "$f"
  done <<<"$HITS"

  printf '\n  选择编号（回车 = 全部 %d 项，q = 取消）: ' "$N"
  read -r PICK || true
  [ "$PICK" = "q" ] && { log '已取消'; exit 0; }

  mkdir -p "$LOCAL"
  if [ -z "$PICK" ]; then
    while IFS= read -r f; do
      adb -s "$DEV" pull "$f" "$LOCAL/" 2>&1 | sed 's/\r$//' | tail -1
    done <<<"$HITS"
    ok "已拉取全部 $N 项 → $LOCAL/"
  else
    [[ "$PICK" =~ ^[0-9]+$ ]] || die "编号应为数字: $PICK"
    { [ "$PICK" -ge 1 ] && [ "$PICK" -le "$N" ]; } || die "编号超范围 1~$N"
    SEL="$(sed -n "${PICK}p" <<<"$HITS")"
    log "拉取 $SEL"
    adb -s "$DEV" pull "$SEL" "$LOCAL/" 2>&1 | sed 's/\r$//' | tail -1
    ok "已拉取 1 项 → $LOCAL/"
  fi
  open_dir "$LOCAL"
  exit 0
fi
