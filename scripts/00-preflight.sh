#!/usr/bin/env bash
# ============================================================================
# 00-preflight.sh - 环境基线采集（只读，不修改系统）
# 用途: 采集优化前的完整状态快照，作为后续对比与回滚依据
# 用法: ./scripts/00-preflight.sh
# 输出: baseline/<时间戳>/ 下的一组文本文件 + SUMMARY.md
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

OUT="$PROJECT_ROOT/baseline/$RUN_ID"
mkdir -p "$OUT"
step "基线采集开始 -> ${OUT#$PROJECT_ROOT/}"

# 统一采集：文件名 -> 命令
collect() {
  local name="$1"; shift
  { eval "$@" ; } >"$OUT/$name.txt" 2>&1 || echo "(命令执行异常: $*)" >>"$OUT/$name.txt"
  printf '%s\n' "$name"
}

step "1/6 系统与硬件"
collect 01-os        'cat /etc/os-release; echo; uname -a; echo; hostnamectl 2>/dev/null'
collect 02-cpu       'lscpu | head -30'
collect 03-mem       'free -h; echo; cat /proc/pressure/memory'
collect 04-disk      'df -hT -x tmpfs -x devtmpfs; echo; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,ROTA,SCHED'
collect 05-gpu       'lspci | grep -Ei "vga|3d|display"; echo; ls /sys/class/drm/'
collect 06-battery   'ls /sys/class/power_supply/; for b in /sys/class/power_supply/BAT*; do [ -d "$b" ] && cat "$b"/{capacity,status,cycle_count} 2>/dev/null; done'

step "2/6 启动与性能"
collect 10-boot      'systemd-analyze; echo; systemd-analyze blame | head -25; echo; systemd-analyze critical-chain'
collect 11-services  'systemctl list-units --type=service --state=running --no-pager --no-legend | wc -l; echo "--- running ---"; systemctl list-units --type=service --state=running --no-pager --no-legend | awk "{print \$1}"'
collect 12-enabled   'systemctl list-unit-files --state=enabled --no-pager --no-legend | awk "{print \$1}"'
collect 13-sysctl    'sysctl -a 2>/dev/null | grep -E "^(vm|kernel|net.core|net.ipv4.tcp)" | sort'
collect 14-swap      'swapon --show; echo "---"; cat /proc/sys/vm/swappiness; echo "--- zram ---"; lsmod | grep -i zram || echo "zram 未加载"'
collect 15-io        'for d in /sys/block/nvme*; do echo "$d: $(cat $d/queue/scheduler)"; done; echo "--- 内核参数 ---"; cat /proc/cmdline'

step "3/6 桌面环境"
collect 20-desktop   'echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"; echo "SESSION=${XDG_SESSION_TYPE:-}"; echo "SHELL=${SHELL:-}"; gnome-shell --version; echo; echo "GDK_BACKEND=${GDK_BACKEND:-未设置}"; echo "QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-未设置}"'
collect 21-gsettings 'for k in gtk-theme icon-theme cursor-theme font-name document-font-name monospace-font-name color-scheme accent-color; do printf "%-22s %s\n" "$k" "$(gsettings get org.gnome.desktop.interface $k 2>/dev/null)"; done; echo "--- wm ---"; for k in button-layout theme; do printf "%-22s %s\n" "$k" "$(gsettings get org.gnome.desktop.wm.preferences $k 2>/dev/null)"; done'
collect 22-extensions 'gnome-extensions list --enabled 2>/dev/null; echo "--- all ---"; gnome-extensions list 2>/dev/null'
collect 23-themes    'ls /usr/share/themes/ 2>/dev/null; echo "--- icons ---"; ls /usr/share/icons/ 2>/dev/null'
collect 24-fonts     'fc-list :lang=zh family 2>/dev/null | sort -u | head -20; echo "--- total ---"; fc-list 2>/dev/null | wc -l'

step "4/6 网络"
collect 30-net       'ip -br addr; echo; ip route; echo "--- dns ---"; resolvectl status 2>/dev/null | head -20 || cat /etc/resolv.conf'
collect 31-mirrors   'grep -vE "^\s*#|^\s*$" /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null'
collect 32-proxy     'env | grep -i proxy || echo "无代理环境变量"; echo "--- npm ---"; npm config get registry 2>/dev/null || echo "npm 未安装"'

step "5/6 软件清单"
collect 40-packages  'dpkg-query -f="${binary:Package}\n" -W 2>/dev/null | wc -l; echo "--- 手动安装 ---"; apt-mark showmanual 2>/dev/null | wc -l'
collect 41-snap      'snap list 2>/dev/null'
collect 42-tools     'for c in git curl wget vim nano tmux zsh htop btop fastfetch node npm python3 pip3 uv rustc cargo docker; do printf "%-10s %s\n" "$c" "$(command -v $c || echo MISSING)"; done'

step "6/6 字体渲染与输入法"
collect 50-fontconf  'cat /etc/fonts/conf.d/ 2>/dev/null | head; echo "--- 用户字体配置 ---"; ls ~/.config/fontconfig/ 2>/dev/null || echo "无"'
collect 51-ime       'env | grep -E "^GTK_IM|^QT_IM|^XMODIFIERS|^INPUT_METHOD"; echo "--- fcitx5 ---"; fcitx5 --version 2>/dev/null; echo "--- 配置 ---"; ls ~/.config/fcitx5/ 2>/dev/null || echo "无用户配置"'

# ---- 汇总 ------------------------------------------------------------------
{
  echo "# 基线快照 $RUN_ID"
  echo
  echo "| 项目 | 值 |"
  echo "|---|---|"
  echo "| 系统 | $(. /etc/os-release; echo "$PRETTY_NAME") |"
  echo "| 内核 | $(uname -r) |"
  echo "| 桌面 | $(gnome-shell --version 2>/dev/null) / ${XDG_SESSION_TYPE:-unknown} |"
  echo "| 运行中服务 | $(systemctl list-units --type=service --state=running --no-legend --no-pager | wc -l) |"
  echo "| 已启用单元 | $(systemctl list-unit-files --state=enabled --no-legend --no-pager | wc -l) |"
  echo "| 开机耗时 | $(systemd-analyze 2>/dev/null | head -1 | sed 's/Startup finished in //') |"
  echo "| 内存 | $(free -h | awk '/^内存|^Mem/{print $2" 总 / "$3" 已用"}') |"
  echo "| 交换 | $(free -h | awk '/^交换|^Swap/{print $2" ("$3" 已用)"}') |"
  echo "| 根分区 | $(df -h / | awk 'NR==2{print $2" 总 / "$4" 可用"}') |"
  echo "| 安装包数 | $(dpkg-query -W -f='.\n' 2>/dev/null | wc -l) |"
  echo "| 中文字体数 | $(fc-list :lang=zh 2>/dev/null | wc -l) |"
} >"$OUT/SUMMARY.md"

ok "采集完成，共 $(ls -1 "$OUT" | wc -l) 个文件"
log "查看汇总: ${OUT#$PROJECT_ROOT/}/SUMMARY.md"
cat "$OUT/SUMMARY.md"
