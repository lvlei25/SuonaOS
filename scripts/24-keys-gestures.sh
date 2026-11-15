#!/usr/bin/env bash
# ============================================================================
# 24-keys-gestures.sh - SuonaOS 键位表与指针手势（用户级，可回滚）
#
# 关键点：custom-keybindings 是**数组键**，单键 gsettings set 会覆盖其它工具的绑定。
# 本脚本的做法：
#   1) 动手前 dconf dump 整段备份
#   2) 读出当前数组 → 只追加自己的 /suona-<id>/ 路径 → 整体写回
#   3) --restore 只摘掉自己的条目，不 reset-recursively（不误伤用户绑定）
#
# 键位声明在 dotfiles/desktop/suona-keys.conf.template，脚本不硬编码快捷键。
#
# 手势现状（诚实说明）：GNOME 50 Wayland 的三指/四指手势由 Shell 内部实现，
#   没有对外 gsettings 开关；能做的是指针与触摸板的**行为**参数（点按、自然滚动、
#   打字防误触、热角），做不到自定义手势方向。要自定义手势必须装扩展，
#   与 ADR-24「少用扩展」冲突，本脚本不引入。
#
# 用法:
#   ./scripts/24-keys-gestures.sh --install
#   ./scripts/24-keys-gestures.sh --status
#   ./scripts/24-keys-gestures.sh --restore
#   ./scripts/24-keys-gestures.sh --install --dry-run
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

TPL="$PROJECT_ROOT/dotfiles/desktop/suona-keys.conf.template"
CB_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
CB_KEY="custom-keybindings"
CB_ROOT="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
ACTION=""
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install) ACTION=install ;;
    --status)  ACTION=status ;;
    --restore) ACTION=restore ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=install

[ -f "$TPL" ] || die "缺少键位模板: $TPL"

# 终端不写死：Ubuntu 25.10 起默认终端从 gnome-terminal 换成 ptyxis，
# 硬编码会导致「按键没反应」，所以安装时解析一次（ADR-19：读不到不猜）。
TERM_BIN=""
for c in ptyxis gnome-terminal kgx alacritty xterm; do
  have "$c" && { TERM_BIN="$c"; break; }
done
[ -n "$TERM_BIN" ] || warn "未找到可用终端，@terminal@ 无法解析（该条会被跳过）"

# 读当前数组（gsettings 输出形如 ['a', 'b'] 或 @as []）
read_array() {
  gsettings get "$CB_SCHEMA" "$CB_KEY" 2>/dev/null \
    | sed -E "s/^@as //; s/^\[//; s/\]$//" \
    | tr ',' '\n' \
    | sed -E "s/^ *'//; s/' *$//" \
    | grep -v '^[[:space:]]*$' || true
}

build_array() {
  local out="" p
  for p in "$@"; do
    [ -n "$p" ] || continue
    out="$out${out:+, }'$p'"
  done
  printf '[%s]' "$out"
}

have_path() { read_array | grep -qx "$1"; }

# 冲突检测：只看四个常用 schema，命中即提示（不阻断，避免误判）
check_conflict() {
  local binding="$1" hit=""
  for s in org.gnome.desktop.wm.keybindings org.gnome.shell.keybindings \
           org.gnome.settings-daemon.plugins.media-keys org.gnome.mutter.keybindings; do
    hit=$(gsettings list-recursively "$s" 2>/dev/null | grep -F "'$binding'" | head -1)
    [ -n "$hit" ] && { printf '%s' "$hit"; return 0; }
  done
  return 1
}

set_if_key() { # set_if_key <schema> <key> <value>
  gsettings list-keys "$1" 2>/dev/null | grep -qx "$2" || return 0
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] gsettings set $1 $2 $3"
  else
    gsettings set "$1" "$2" "$3" 2>/dev/null || warn "写入失败: $1 $2"
  fi
}

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  echo
  echo "════════ SuonaOS 键位 ════════"
  printf '  %-11s %-22s %s\n' 动作 快捷键 命令
  while IFS='|' read -r id name cmd binding; do
    id="$(echo "$id" | tr -d ' ')"; [ -n "$id" ] || continue
    case "$id" in \#*) continue ;; esac
    name="$(echo "$name" | sed 's/^ *//;s/ *$//')"
    cmd="$(echo "$cmd" | sed 's/^ *//;s/ *$//')"
    cmd="${cmd//@terminal@/$TERM_BIN}"
    binding="$(echo "$binding" | sed 's/^ *//;s/ *$//')"
    path="$CB_ROOT$id/"
    if have_path "$path"; then
      cur_b="$(gsettings get "$CB_SCHEMA.custom-keybinding:$path" binding 2>/dev/null | tr -d "'")"
      printf '  %-11s %-22s %s\n' "$name" "$cur_b" "$cmd"
    else
      printf '  %-11s %-22s %s\n' "$name" "（未安装）" "$cmd"
    fi
  done <"$TPL"
  echo
  echo "  热角        : $(gsettings get org.gnome.desktop.interface enable-hot-corners 2>/dev/null || echo '键不存在')"
  echo "  触摸板点按  : $(gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click 2>/dev/null)"
  echo "  自然滚动    : $(gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll 2>/dev/null)"
  echo "  打字防误触  : $(gsettings get org.gnome.desktop.peripherals.touchpad disable-while-typing 2>/dev/null)"
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  CUR=()
  while IFS= read -r p; do
    case "$p" in
      "$CB_ROOT"suona-*) ;;   # 自己的，丢弃
      '') ;;
      *) CUR+=("$p") ;;
    esac
  done < <(read_array)
  if [ "$DRY" -eq 1 ]; then
    log "[dry-run] custom-keybindings → $(build_array "${CUR[@]}")"
  else
    gsettings set "$CB_SCHEMA" "$CB_KEY" "$(build_array "${CUR[@]}")" && ok "已从数组移除 Suona 条目"
  fi
  while IFS='|' read -r id _ _ _; do
    id="$(echo "$id" | tr -d ' ')"; [ -n "$id" ] || continue
    case "$id" in \#*) continue ;; esac
    path="$CB_ROOT$id/"
    if [ "$DRY" -eq 1 ]; then
      log "[dry-run] dconf reset -f $path"
    else
      dconf reset -f "$path" 2>/dev/null || true
    fi
  done <"$TPL"
  ok "Suona 键位已移除（用户原有绑定未动）"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/3 备份 media-keys（数组键无法用 backup_file）"
if [ "$DRY" -eq 1 ]; then
  log "[dry-run] dconf dump /org/gnome/settings-daemon/plugins/media-keys/"
else
  dump_dconf "/org/gnome/settings-daemon/plugins/media-keys/" "media-keys-before-suona-keys"
fi

step "2/3 合并写入键位（只追加自己的路径）"
ADDED=0; SKIPPED=0
while IFS='|' read -r id name cmd binding; do
  id="$(echo "$id" | tr -d ' ')"
  [ -n "$id" ] || continue
  case "$id" in \#*) continue ;; esac
  name="$(echo "$name" | sed 's/^ *//;s/ *$//')"
  cmd="$(echo "$cmd" | sed 's/^ *//;s/ *$//')"
  cmd="${cmd//@terminal@/$TERM_BIN}"
  binding="$(echo "$binding" | sed 's/^ *//;s/ *$//')"

  bin="${cmd%% *}"
  if ! have "$bin"; then
    warn "跳过 $name：命令不存在（$bin）"; SKIPPED=$((SKIPPED + 1)); continue
  fi
  case "$id" in
    clipboard) have suona-clip || warn "$name：suona-clip 未安装，先跑 25-quicklook-clipboard.sh" ;;
  esac

  if CONFLICT="$(check_conflict "$binding")"; then
    warn "$name：$binding 可能与既有绑定冲突 → $CONFLICT"
  fi

  path="$CB_ROOT$id/"
  if ! have_path "$path"; then
    CUR=(); while IFS= read -r p; do [ -n "$p" ] && CUR+=("$p"); done < <(read_array)
    CUR+=("$path")
    if [ "$DRY" -eq 1 ]; then
      log "[dry-run] custom-keybindings += $path"
    else
      gsettings set "$CB_SCHEMA" "$CB_KEY" "$(build_array "${CUR[@]}")" || warn "数组写入失败"
    fi
  fi

  for kv in "name:$name" "command:$cmd" "binding:$binding"; do
    k="${kv%%:*}"; v="${kv#*:}"
    if [ "$DRY" -eq 1 ]; then
      log "[dry-run] $id.$k = $v"
    else
      gsettings set "$CB_SCHEMA.custom-keybinding:$path" "$k" "$v" || warn "写入失败 $id.$k"
    fi
  done
  ok "$name → $binding"
  ADDED=$((ADDED + 1))
done <"$TPL"

step "3/3 指针与边角行为"
set_if_key org.gnome.desktop.interface enable-hot-corners true
set_if_key org.gnome.desktop.peripherals.touchpad tap-to-click true
set_if_key org.gnome.desktop.peripherals.touchpad natural-scroll true
set_if_key org.gnome.desktop.peripherals.touchpad disable-while-typing true
set_if_key org.gnome.desktop.peripherals.mouse natural-scroll true

echo
log "已安装 $ADDED 条，跳过 $SKIPPED 条（命令缺失）"
log "自定义手势方向需装扩展，按 ADR-24 不引入；详见 docs/23-键位与手势.md"
log "查看: $0 --status    回滚: $0 --restore"
