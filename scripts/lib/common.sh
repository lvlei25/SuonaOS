#!/usr/bin/env bash
# ============================================================================
# common.sh - 公共函数库（日志 / 断言 / 备份 / 变更登记）
# 所有脚本通过 `source scripts/lib/common.sh` 引入
# ============================================================================

set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
BACKUP_DIR="$PROJECT_ROOT/backup"
MANIFEST="$PROJECT_ROOT/logs/changes.tsv"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/${RUN_ID}-$(basename "${0%.sh}").log"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'
  C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''
fi

# 输出同时写入日志文件
_emit() {
  local color="$1"; shift
  local msg
  msg="$(printf '%s[%s]%s %s' "$color" "$(date +%H:%M:%S)" "$C_RESET" "$*")"
  printf '%s\n' "$msg"
  printf '%s\n' "$(printf '[%s] %s' "$(date +%Y-%m-%d\ %H:%M:%S)" "$*")" >>"$LOG_FILE"
}

log()  { _emit "$C_INFO" "$*"; }
ok()   { _emit "$C_OK"   "$*"; }
warn() { _emit "$C_WARN" "$*"; }
die()  { _emit "$C_ERR"  "$*" >&2; exit 1; }
step() { _emit "$C_INFO" ""; _emit "$C_INFO" "==> $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---- sudo 相关 -------------------------------------------------------------
require_sudo() {
  if sudo -n true 2>/dev/null; then
    ok "sudo 免密可用"
  else
    die "sudo 需要密码。请先执行： sudo tee /etc/sudoers.d/99-codebuddy-nopasswd >/dev/null <<< 'suonaos ALL=(ALL) NOPASSWD: ALL' && sudo chmod 0440 /etc/sudoers.d/99-codebuddy-nopasswd"
  fi
}

# ---- 备份 ------------------------------------------------------------------
# 备份单个文件（保留绝对路径层级），并登记到 changes.tsv
# 用法: backup_file /etc/sysctl.d/99-tune.conf
backup_file() {
  local src="$1"
  [ -e "$src" ] || { warn "备份跳过，不存在: $src"; return 0; }
  local dst="$BACKUP_DIR/$RUN_ID/files${src}"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst" && ok "已备份 $src -> ${dst#$PROJECT_ROOT/}"
  printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$src" "${dst#$BACKUP_DIR/}" >>"$MANIFEST"
}

# 备份整个目录
backup_dir() {
  local src="$1"
  [ -d "$src" ] || { warn "备份跳过，目录不存在: $src"; return 0; }
  local dst="$BACKUP_DIR/$RUN_ID/dirs${src}"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst" && ok "已备份目录 $src"
  printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$src" "${dst#$BACKUP_DIR/}" >>"$MANIFEST"
}

# ---- 包管理 ----------------------------------------------------------------
apt_install() {
  local pkgs=("$@")
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "已安装，跳过: ${pkgs[*]}"
    return 0
  fi
  log "安装: ${missing[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" \
    || die "安装失败: ${missing[*]}"
  ok "安装完成: ${missing[*]}"
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

# ---- dconf 备份 -------------------------------------------------------------
# gsettings 的数组键（如 custom-keybindings、enabled-extensions）无法用 backup_file
# 备份，必须整段 dump；恢复时按路径用 dconf load 回灌。
# 用法: dump_dconf /org/gnome/settings-daemon/plugins/media-keys/
dump_dconf() {
  local path="$1" label="${2:-$(printf '%s' "$1" | tr '/' '_')}"
  local dst="$BACKUP_DIR/$RUN_ID/dconf/$label.dump"
  have dconf || { warn "缺少 dconf，跳过备份 $path"; return 0; }
  mkdir -p "$(dirname "$dst")"
  if dconf dump "$path" >"$dst" 2>/dev/null; then
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" "dconf:$path" "$RUN_ID/dconf/$label.dump" >>"$MANIFEST"
    ok "已备份 dconf $path -> ${dst#$PROJECT_ROOT/}"
  else
    warn "dconf dump 失败: $path"
  fi
}

# ---- 隐私掩码 ---------------------------------------------------------------
# 报告类输出统一过一层，避免 IP / MAC / 主机名外泄（沿用 docs/11 的做法）
mask_pii() {
  sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g; s/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/<mac>/g'
}

# ---- 采样工具 ---------------------------------------------------------------
# 单次采样 CPU 时间片（/proc/<pid>/stat 的 utime+stime）
proc_cpu_ticks() {
  local pid="$1"
  [ -r "/proc/$pid/stat" ] || { echo 0; return; }
  awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null || echo 0
}

clock_ticks() { getconf CLK_TCK 2>/dev/null || echo 100; }
