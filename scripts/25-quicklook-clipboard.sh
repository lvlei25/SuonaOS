#!/usr/bin/env bash
# ============================================================================
# 25-quicklook-clipboard.sh - 即时预览 + 剪贴板历史（用户级，可回滚）
#
# 两块能力：
#   1) 即时预览：sushi —— 文件管理器里选中文件按空格直接看，不打开应用
#   2) 剪贴板历史：不装 GNOME 扩展（ADR-24），改用 wl-clipboard + fzf 的组合：
#        systemd user service 常驻 `wl-paste --watch`，把每次复制存进本地历史，
#        Super+Shift+V 调起 fzf 选择后 wl-copy 回剪贴板。
#
# 隐私：历史只存在 ~/.local/state/suona/clipboard.tsv（base64），上限 200 条，
#       不上传、不同步；--restore 时连历史一起移入 backup。
#
# 用法:
#   ./scripts/25-quicklook-clipboard.sh --install
#   ./scripts/25-quicklook-clipboard.sh --status
#   ./scripts/25-quicklook-clipboard.sh --restore
#   ./scripts/25-quicklook-clipboard.sh --install --no-apt   # 只装用户级部分
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ACTION=""
NO_APT=0
BIN_DIR="$HOME/.local/bin"
CLIP_BIN="$BIN_DIR/suona-clip"
STATE_DIR="$HOME/.local/state/suona"
HIST="$STATE_DIR/clipboard.tsv"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/suona-clipboard.service"
APP_DIR="$HOME/.local/share/applications"
DESKTOP="$APP_DIR/suona-clip.desktop"

while [ $# -gt 0 ]; do
  case "$1" in
    --install) ACTION=install ;;
    --status)  ACTION=status ;;
    --restore) ACTION=restore ;;
    --no-apt)  NO_APT=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done
[ -n "$ACTION" ] || ACTION=install

unit_state() { systemctl --user is-active suona-clipboard.service 2>/dev/null || echo inactive; }

# ---- status ----------------------------------------------------------------
if [ "$ACTION" = status ]; then
  echo
  echo "════════ 即时预览与剪贴板 ════════"
  if have sushi; then
    echo "  即时预览    : sushi 已安装（Nautilus 选中文件按空格）"
  else
    echo "  即时预览    : sushi 未安装（--install 会安装）"
  fi
  echo "  wl-clipboard: $(have wl-paste && have wl-copy && echo 已安装 || echo 缺失)"
  echo "  选择器      : $(have fzf && echo fzf || echo 缺失)"
  echo "  suona-clip  : $([ -x "$CLIP_BIN" ] && echo "$CLIP_BIN" || echo 未安装)"
  echo "  采集服务    : $(unit_state) / $(systemctl --user is-enabled suona-clipboard.service 2>/dev/null || echo disabled)"
  echo "  历史条数    : $([ -f "$HIST" ] && wc -l <"$HIST" || echo 0)（上限 200）"
  echo "  启动器      : $([ -f "$DESKTOP" ] && echo 已安装 || echo 未安装)"
  bp="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null | grep -o '/clipboard/' || true)"
  echo "  快捷键      : $([ -n "$bp" ] && echo '已绑定（Super+Shift+V 由 24-keys-gestures.sh 写入）' || echo 未绑定)"
  exit 0
fi

# ---- restore ---------------------------------------------------------------
if [ "$ACTION" = restore ]; then
  systemctl --user disable --now suona-clipboard.service 2>/dev/null && ok "采集服务已停止并禁用"
  rm -f "$UNIT" "$DESKTOP" "$CLIP_BIN"
  systemctl --user daemon-reload 2>/dev/null || true
  if [ -d "$STATE_DIR" ]; then
    DST="$BACKUP_DIR/$RUN_ID/dirs$HOME/.local/state"
    mkdir -p "$DST"
    mv "$STATE_DIR" "$DST/" && ok "剪贴板历史已移入 ${DST#$PROJECT_ROOT/}"
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$STATE_DIR" "$RUN_ID/dirs$HOME/.local/state/suona" >>"$MANIFEST"
  fi
  ok "即时预览（sushi 包）不自动卸载：sudo apt remove sushi 需你确认"
  exit 0
fi

# ---- install ---------------------------------------------------------------
step "1/5 即时预览（sushi）"
# 包名是 gnome-sushi（不是 sushi）；apt_install 失败会 die，这里自己包一层降级。
if have sushi || pkg_installed gnome-sushi; then
  ok "gnome-sushi 已安装"
elif [ "$NO_APT" -eq 1 ]; then
  warn "--no-apt：跳过安装（预览功能不可用）"
else
  if apt-cache show gnome-sushi >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-sushi >/dev/null 2>&1 \
      && ok "gnome-sushi 安装完成" || warn "gnome-sushi 安装失败：预览不可用，其余功能不受影响"
  else
    warn "源里没有 gnome-sushi：预览不可用（其他发行版包名可能不同）"
  fi
fi

step "2/5 检查剪贴板依赖"
for b in wl-paste wl-copy fzf base64; do
  have "$b" || die "缺少依赖 $b（wl-clipboard / fzf），先安装后重跑"
done
# xclip 用来避开 wl-paste 的逐次调用副作用（见下方 daemon 注释与 ISSUE-39）
if ! have xclip && [ "$NO_APT" -eq 0 ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xclip >/dev/null 2>&1 \
    && ok "xclip 已安装（走 XWayland 读取，避免每秒一条 Mutter 断言）" \
    || warn "xclip 安装失败：将回退 wl-paste 轮询（会有日志噪声）"
fi
ok "wl-clipboard + fzf 就绪"

step "3/5 安装 suona-clip"
mkdir -p "$BIN_DIR" "$STATE_DIR"
if [ -f "$CLIP_BIN" ] && ! grep -q 'SuonaOS' "$CLIP_BIN" 2>/dev/null; then
  backup_file "$CLIP_BIN"
fi
cat >"$CLIP_BIN" <<'CLIP_EOF'
#!/usr/bin/env bash
# suona-clip - SuonaOS 剪贴板历史（由 scripts/25-quicklook-clipboard.sh 生成）
#   suona-clip            选择一条历史并复制回剪贴板
#   suona-clip --store    从 stdin 读取一次复制并入库（供 wl-paste --watch 调用）
#   suona-clip --list     打印条数
#   suona-clip --clear    清空历史
set -o pipefail
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/suona"
HIST="$STATE/clipboard.tsv"
LIMIT=200
mkdir -p "$STATE"

store() {
  local data h last
  data="$(cat)"
  [ -n "$data" ] || exit 0
  h="$(printf '%s' "$data" | sha256sum | cut -c1-16)"
  last="$(tail -1 "$HIST" 2>/dev/null | cut -f1)"
  [ "$h" = "$last" ] && exit 0
  # 同内容去重：先删旧同名，再追加（保证最近一次在最前）
  if [ -f "$HIST" ]; then
    awk -F'\t' -v h="$h" '$1!=h' "$HIST" >"$HIST.tmp" && mv "$HIST.tmp" "$HIST"
  fi
  printf '%s\t%s\n' "$h" "$(printf '%s' "$data" | base64 -w0)" >>"$HIST"
  tail -n "$LIMIT" "$HIST" >"$HIST.tmp" && mv "$HIST.tmp" "$HIST"
}

# 为什么轮询而不是 wl-paste --watch：
#   watch 模式依赖 wlroots 的 data-control 协议，GNOME/Mutter 不实现，
#   实测直接报 "Watch mode requires a compositor that supports the wlroots
#   data-control protocol" 并退出。改为 1s 轮询：本机实测无焦点进程也能读取
#   selection，成本约 2MB 内存 + 每秒一次短进程。
# 读取选择：优先 XWayland 的 xclip。
# 原因（ISSUE-39）：每调用一次 wl-paste，Mutter 就打一条
#   meta_window_set_stack_position_no_sync assertion 'window->stack_position >= 0'
# 实测 10 次调用 = 10 条，等于每次轮询都触发一次窗口重排；xclip 走 XWayland
#   桥接，10 次调用 = 0 条，且能正确读到 Wayland 应用复制的内容（实测跟随变化）。
read_clip() {
  if [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
    xclip -o -selection clipboard 2>/dev/null
  else
    wl-paste --no-newline --type text 2>/dev/null
  fi
}

daemon() {
  local last="" cur h
  while :; do
    cur="$(read_clip)" || cur=""
    if [ -n "$cur" ]; then
      h="$(printf '%s' "$cur" | sha256sum | cut -c1-16)"
      if [ "$h" != "$last" ]; then
        if [ -f "$STATE/ignore" ] && grep -qx "$h" "$STATE/ignore"; then
          # 自己刚写回剪贴板的内容，不重复入库
          grep -vx "$h" "$STATE/ignore" >"$STATE/ignore.tmp" 2>/dev/null && mv "$STATE/ignore.tmp" "$STATE/ignore"
        else
          printf '%s' "$cur" | store
        fi
        last="$h"
      fi
    else
      last=""
    fi
    sleep 1
  done
}

case "${1:-}" in
  --daemon) daemon ;;
  --store)  store; exit 0 ;;
  --list)   [ -f "$HIST" ] && wc -l <"$HIST" || echo 0; exit 0 ;;
  --clear)  rm -f "$HIST" "$STATE/ignore"; echo "已清空"; exit 0 ;;
esac

[ -f "$HIST" ] || { echo "还没有剪贴板历史：先复制一段文字"; exit 0; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
while IFS=$'\t' read -r h b64; do
  text="$(printf '%s' "$b64" | base64 -d 2>/dev/null)" || continue
  [ -n "$text" ] || continue
  disp="$(printf '%s' "$text" | tr '\n' ' ' | cut -c1-120)"
  printf '%s\t%s\n' "$h" "$disp" >>"$TMP"
done < <(tac "$HIST")

sel="$(fzf --delimiter='\t' --with-nth=2 --height=70% --reverse --prompt='剪贴板> ' <"$TMP")" || exit 0
h="${sel%%$'\t'*}"
b64="$(awk -F'\t' -v h="$h" '$1==h{print $2; exit}' "$HIST")"
[ -n "$b64" ] || { echo "选中的条目已失效"; exit 1; }
printf '%s\n' "$h" >>"$STATE/ignore"
printf '%s' "$b64" | base64 -d | wl-copy && echo "已复制到剪贴板"
CLIP_EOF
chmod +x "$CLIP_BIN"
ok "$CLIP_BIN"

step "4/5 安装采集服务与启动器"
mkdir -p "$UNIT_DIR"
cat >"$UNIT" <<EOF
[Unit]
Description=Suona 剪贴板历史采集
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=$CLIP_BIN --daemon
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
mkdir -p "$APP_DIR"
cat >"$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=剪贴板历史
Comment=SuonaOS 剪贴板历史（Super+Shift+V）
Exec=/bin/bash -lc "$CLIP_BIN"
Icon=edit-paste
Terminal=true
NoDisplay=true
Categories=Utility;
EOF
chmod +x "$DESKTOP"
command -v desktop-file-validate >/dev/null 2>&1 \
  && { desktop-file-validate "$DESKTOP" && ok "desktop 文件校验通过"; } || true
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now suona-clipboard.service 2>/dev/null \
  && ok "采集服务已启动" || warn "采集服务启动失败（检查 systemctl --user status suona-clipboard）"

step "5/5 自检"
printf '  服务状态: %s\n' "$(unit_state)"
printf '  历史文件: %s\n' "$([ -f "$HIST" ] && echo 存在 || echo 待首次复制后创建)"
printf '  预览      : %s\n' "$(have sushi && echo 'sushi 就绪' || echo 'sushi 缺失')"

echo
log "快捷键 Super+Shift+V 由 24-keys-gestures.sh 写入；未绑定则重跑该脚本"
log "隐私说明见 docs/24-即时预览与剪贴板.md（本地存储、上限 200、不同步）"
log "查看: $0 --status    回滚: $0 --restore"
