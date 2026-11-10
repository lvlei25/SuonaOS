#!/usr/bin/env bash
# ============================================================================
# 99-verify.sh - 全阶段状态校验（只读）
# 用法: ./scripts/99-verify.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
export PATH="$HOME/.local/bin:$PATH"

PASS=0; FAIL=0
chk() { # chk <描述> <命令...>
  local desc="$1"; shift
  if eval "$@" >/dev/null 2>&1; then
    printf '  %s✓%s %s\n' "$C_OK" "$C_RESET" "$desc"; PASS=$((PASS+1))
  else
    printf '  %s✗%s %s\n' "$C_ERR" "$C_RESET" "$desc"; FAIL=$((FAIL+1))
  fi
}
val() { printf '      %s\n' "$1"; }

echo
echo "════════ 环境部署校验 ════════"
for c in git curl vim tmux zsh node npm starship fastfetch uv rg fzf jq btop; do
  chk "命令 $c" "command -v $c"
done

echo
echo "════════ 网络加速 ════════"
chk "apt 使用 TUNA 镜像" "grep -q mirrors.tuna /etc/apt/sources.list.d/ubuntu.sources"
chk "pip 使用 TUNA 镜像" "grep -q mirrors.tuna $HOME/.config/pip/pip.conf"
chk "npm 使用 npmmirror" "npm config get registry | grep -q npmmirror"
val "npm registry: $(npm config get registry 2>/dev/null)"
chk "GitHub 走 ghfast 加速" "git config --global --get url.https://ghfast.top/https://github.com/.insteadOf"

echo
echo "════════ 性能优化 ════════"
chk "swap 包含 zram0" "swapon --show | grep -q zram0"
val "$(swapon --show --noheadings | tr -s ' ' | tr '\n' ' ')"
chk "swappiness <= 20" "[ $(cat /proc/sys/vm/swappiness) -le 20 ]"
chk "BBR 拥塞控制" "[ '$(sysctl -n net.ipv4.tcp_congestion_control)' = bbr ]"
chk "NetworkManager-wait-online 已禁用" "[ '$(systemctl is-enabled NetworkManager-wait-online.service 2>/dev/null)' = disabled ]"
chk "cloud-init 已禁用" "[ '$(systemctl is-enabled cloud-init-main.service 2>/dev/null)' = disabled ]"
chk "apport 已禁用" "[ '$(systemctl is-enabled apport.service 2>/dev/null)' = disabled ]"
# GRUB 超时按双系统状态分支（ADR-03）：有 Windows 就需 >=3s 才选得到菜单，
# 单系统才追求 1s。避免把「回退/决策变更」误报成失败。
GRUB_TO=$(grep '^GRUB_TIMEOUT=' /etc/default/grub 2>/dev/null | cut -d= -f2)
if sudo grep -q 'Windows Boot Manager' /boot/grub/grub.cfg 2>/dev/null; then
  chk "GRUB 超时适配双系统（>=3s）" "[ -n '$GRUB_TO' ] && [ '$GRUB_TO' -ge 3 ]"
  val "双系统：GRUB 超时 ${GRUB_TO}s（ADR-03，保留 Windows / recovery 入口）"
else
  chk "GRUB 超时 1s" "[ '$GRUB_TO' = 1 ]"
  val "单系统：GRUB 超时 ${GRUB_TO}s"
fi
chk "crashkernel=0 已写入 grub.cfg" "sudo grep -q 'quiet splash crashkernel=0' /boot/grub/grub.cfg"
chk "journald 限制 200M" "grep -rq 'SystemMaxUse=200M' /etc/systemd/journald.conf.d/"
val "开机: $(systemd-analyze 2>/dev/null | head -1 | sed 's/Startup finished in //')"

echo
echo "════════ 开发环境 ════════"
chk "默认 shell 为 zsh" "[ '$(getent passwd $USER | cut -d: -f7)' = /usr/bin/zsh ]"
for f in ~/.zshrc ~/.tmux.conf ~/.vimrc ~/.config/starship.toml; do
  chk "${f/#$HOME/\~} 已链接" "[ -L $f ]"
done
chk "zsh 可无错误加载" "zsh -i -c exit"

echo
echo "════════ 中文与字体 ════════"
# 状态感知（REQ-06）：定制态按 Inter/JetBrains 校验，回退态按系统默认校验。
# 两条路径都能零失败，将来恢复任一方案都不需要再改脚本。
CUR_FONT=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
if echo "$CUR_FONT" | grep -q Inter; then
  chk "界面字体 Inter" "gsettings get org.gnome.desktop.interface font-name | grep -q Inter"
  chk "等宽字体 JetBrains Mono" "gsettings get org.gnome.desktop.interface monospace-font-name | grep -q JetBrains"
  chk "fontconfig 用户配置存在" "[ -f $HOME/.config/fontconfig/fonts.conf ]"
  val "字体状态：定制态（REQ-06 生效）$CUR_FONT"
else
  chk "界面字体为系统默认" "[ -n '$CUR_FONT' ] && echo '$CUR_FONT' | grep -qv Inter"
  chk "等宽字体为系统默认" "gsettings get org.gnome.desktop.interface monospace-font-name | grep -qv JetBrains"
  chk "fontconfig 已按回退清理" "[ ! -f $HOME/.config/fontconfig/fonts.conf ]"
  val "字体状态：回退态（REQ-06 = reverted / ADR-07）$CUR_FONT"
fi
chk "中文字体可用" "[ $(fc-list :lang=zh 2>/dev/null | wc -l) -gt 20 ]"

echo
echo "════════ 输入法 ════════"
chk "会话环境变量指向 fcitx5" "grep -q 'GTK_IM_MODULE=fcitx' $HOME/.config/environment.d/99-input-method.conf"
chk "fcitx5 用户服务已启用" "systemctl --user is-enabled --quiet fcitx5.service"
chk "fcitx5 服务运行中" "systemctl --user is-active --quiet fcitx5.service"
chk "fcitx5 进程运行中" "pgrep -x fcitx5"
chk "旧 autostart 已清理" "[ ! -f $HOME/.config/autostart/fcitx5.desktop ]"
val "当前 XMODIFIERS: ${XMODIFIERS:-未设置}（重新登录后变为 @im=fcitx）"

echo
echo "════════ 主题美化 ════════"
CUR_GTK=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
if echo "$CUR_GTK" | grep -q WhiteSur; then
  chk "GTK 主题 WhiteSur" "gsettings get org.gnome.desktop.interface gtk-theme | grep -q WhiteSur"
  chk "图标主题 WhiteSur" "gsettings get org.gnome.desktop.interface icon-theme | grep -qi WhiteSur"
  chk "光标 WhiteSur-cursors" "gsettings get org.gnome.desktop.interface cursor-theme | grep -q WhiteSur"
  chk "深色模式" "gsettings get org.gnome.desktop.interface color-scheme | grep -q prefer-dark"
  chk "窗口按钮在左侧" "gsettings get org.gnome.desktop.wm.preferences button-layout | grep -q \"close,minimize,maximize:\""
  chk "Dock 在底部" "[ '$(gsettings get org.gnome.shell.extensions.dash-to-dock dock-position)' = BOTTOM ]"
  chk "User Themes 已启用" "gsettings get org.gnome.shell enabled-extensions | grep -q user-theme"
  chk "Shell 主题 WhiteSur" "gsettings get org.gnome.shell.extensions.user-theme name | grep -q WhiteSur"
else
  # 回退态同样做正向断言，而不是简单跳过（REQ-07/08 cancelled / ADR-07）
  SHELL_THEME=$(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null | tr -d "'")
  chk "GTK 主题为系统默认" "[ -n '$CUR_GTK' ] && echo '$CUR_GTK' | grep -qv WhiteSur"
  chk "图标主题为系统默认" "gsettings get org.gnome.desktop.interface icon-theme | grep -qv WhiteSur"
  # 状态感知（ADR-21 / ADR-32）：无 shell 主题 / 本项目圆角覆盖 / 其他自定义，三种各自断言
  if [ -z "$SHELL_THEME" ]; then
    chk "未启用自定义 Shell 主题" "true"
    val "主题状态：回退态（REQ-07/08 = cancelled / ADR-07）$CUR_GTK"
  elif echo "$SHELL_THEME" | grep -q '^Suona-'; then
    chk "Shell 主题仅含圆角覆盖（$SHELL_THEME）" \
      "grep -q 'border-radius' '$HOME/.themes/$SHELL_THEME/gnome-shell/gnome-shell.css'"
    val "主题状态：回退态 + 圆角覆盖（$SHELL_THEME，ADR-07 / ADR-32）"
  else
    chk "Shell 主题为自定义（非本项目）" "[ -n '$SHELL_THEME' ]"
    val "主题状态：自定义 Shell 主题 $SHELL_THEME"
  fi
fi

echo
echo "════════ 美化（GRUB / Dock / 顶栏）════════"
# 状态感知（ADR-21）：配置了就检查，没配置就说明，不把「没做」判成失败
GT_THEME=$(grep '^GRUB_THEME=' /etc/default/grub 2>/dev/null | cut -d'"' -f2)
if [ -n "$GT_THEME" ]; then
  chk "GRUB 主题文件存在" "[ -f '$GT_THEME' ]"
  val "GRUB 主题: $GT_THEME"
else
  val "GRUB 未配置主题（使用文本菜单）"
fi

DOCK_TM=$(gsettings get org.gnome.shell.extensions.dash-to-dock transparency-mode 2>/dev/null | tr -d "'")
if [ "$DOCK_TM" != "DEFAULT" ] && [ -n "$DOCK_TM" ]; then
  chk "Dock 透明度已启用" "[ '$DOCK_TM' = FIXED ] || [ '$DOCK_TM' = DYNAMIC ]"
  val "Dock: $DOCK_TM / opacity $(gsettings get org.gnome.shell.extensions.dash-to-dock background-opacity 2>/dev/null)"
else
  val "Dock 使用主题默认透明度"
fi

BLUR_EXT="$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx"
if [ -d "$BLUR_EXT" ]; then
  chk "顶栏模糊扩展已启用" "gsettings get org.gnome.shell enabled-extensions | grep -q blur-my-shell"
else
  val "未安装顶栏模糊扩展"
fi

BG_URI=$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null | tr -d "'")
BG_PATH=${BG_URI#file://}
case "$BG_URI" in
  *water-cycle.xml*)
    chk "水系壁纸轮换配置有效" "[ -s '$BG_PATH' ]"
    val "壁纸: $(basename "$BG_PATH")（每 30 分钟轮换）"
    ;;
  *)
    val "壁纸: $(basename "$BG_PATH")（未启用轮换）"
    ;;
esac

echo
echo "════════ 声音主题 ════════"
# 状态感知（ADR-21 / ADR-27）：定制态与默认态各自正向断言
SND_THEME=$(gsettings get org.gnome.desktop.sound theme-name 2>/dev/null | tr -d "'")
SND_DIR="$HOME/.local/share/sounds/Suona"
if [ "$SND_THEME" = "Suona" ]; then
  chk "声音主题已切换为 Suona" "[ '$SND_THEME' = Suona ]"
  chk "Suona 主题 index.theme 存在" "[ -f '$SND_DIR/index.theme' ]"
  SND_N=$(ls -1 "$SND_DIR/stereo"/*.oga 2>/dev/null | wc -l)
  chk "事件音数量 ≥ 30" "[ '$SND_N' -ge 30 ]"
  chk "事件音效总开关已开" "gsettings get org.gnome.desktop.sound event-sounds | grep -q true"
  # 音量匹配（ADR-28）：系统音效必须低于应用内容一档，否则会压过音乐/会议
  SND_PEAK=$(ffmpeg -hide_banner -i "$SND_DIR/stereo/bell.oga" -af volumedetect -f null /dev/null 2>&1 \
    | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p' | head -1)
  chk "系统音效峰值 ≤ -8 dBFS（不压过应用）" "awk -v p='${SND_PEAK:-0}' 'BEGIN{exit !(p<=-8)}'"
  val "声音: $SND_THEME（$SND_N 个事件音，峰值 ${SND_PEAK:-?} dBFS）"
else
  chk "声音主题为系统默认" "[ -n '$SND_THEME' ] && [ '$SND_THEME' != Suona ]"
  val "声音: $SND_THEME（未启用 Suona 主题）"
fi

echo
echo "════════ 电池提示 ════════"
# 只在关键节点提示（ADR-29）：20% / 10% / 充满，不随每 1% 变化
BAT_EV_N=$(ls -1 "$SND_DIR/stereo/" 2>/dev/null | grep -c '^battery-')
chk "电池事件音齐全（low/caution/full）" "[ '$BAT_EV_N' -eq 3 ]"
UP_LOW=$(grep -E '^PercentageLow=' /etc/UPower/UPower.conf 2>/dev/null | cut -d= -f2)
UP_CRIT=$(grep -E '^PercentageCritical=' /etc/UPower/UPower.conf 2>/dev/null | cut -d= -f2)
chk "upower 低电阈值 20% / 10%" "[ '${UP_LOW%.*}' = 20 ] && [ '${UP_CRIT%.*}' = 10 ]"
chk "充满提示 timer 已启用" "systemctl --user is-enabled --quiet suona-battery-alert.timer"
if [ -x /etc/systemd/system-sleep/50-suona-upower ]; then
  chk "挂起恢复自愈 hook 已安装" "[ -x /etc/systemd/system-sleep/50-suona-upower ]"
  val "电池: low=${UP_LOW%.*}% critical=${UP_CRIT%.*}% timer=$(systemctl --user is-active suona-battery-alert.timer 2>/dev/null) hook=on"
else
  val "电池: low=${UP_LOW%.*}% critical=${UP_CRIT%.*}% timer=$(systemctl --user is-active suona-battery-alert.timer 2>/dev/null) hook=off"
fi

echo
echo "════════ 日光与圆角 ════════"
# 状态感知（ADR-21）：装了才断言，未装只说明
if [ "$(systemctl --user is-enabled suona-auto-dark.timer 2>/dev/null)" = "enabled" ]; then
  chk "日落自动深色 timer 已启用" "systemctl --user is-enabled --quiet suona-auto-dark.timer"
  val "深色: timer=$(systemctl --user is-active suona-auto-dark.timer) scheme=$(gsettings get org.gnome.desktop.interface color-scheme)"
else
  val "深色: 未启用自动切换（color-scheme=$(gsettings get org.gnome.desktop.interface color-scheme)）"
fi

R4="$HOME/.config/gtk-4.0/gtk.css"
if [ -f "$R4" ] && grep -q 'SuonaOS' "$R4" 2>/dev/null; then
  chk "GTK4 圆角覆盖层已生效" "grep -q 'border-radius' '$R4'"
  chk "GTK4 未硬链 dark 主题（保证跟随明暗）" "[ ! -L '$R4' ]"
  val "圆角: $(grep -oE 'border-radius: [0-9]+px' "$R4" | head -1)"
else
  val "圆角: 未启用覆盖层（使用主题默认）"
fi

echo
echo "════════ Electron 沙箱 ════════"
# ISSUE-32：chrome-sandbox 必须 root:root 4755，否则 Electron 应用直接 abort
SB_N=0; SB_BAD=0; SB_LIST=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  SB_N=$((SB_N + 1))
  perm="$(stat -c '%a' "$f" 2>/dev/null)"
  if [ "$perm" != "4755" ]; then
    SB_BAD=$((SB_BAD + 1)); SB_LIST="$SB_LIST $(basename "$(dirname "$f")"):$perm"
  fi
done < <(sudo -n find /opt -maxdepth 2 -name chrome-sandbox 2>/dev/null || find /opt -maxdepth 2 -name chrome-sandbox 2>/dev/null)
if [ "$SB_N" -gt 0 ]; then
  chk "Electron chrome-sandbox 均为 4755" "[ '$SB_BAD' -eq 0 ]"
  val "Electron 沙箱: $SB_N 个应用，异常 $SB_BAD$SB_LIST"
else
  val "Electron 沙箱: 未发现 /opt 下的 chrome-sandbox"
fi

echo
echo "════════ 汇总 ════════"
printf '  通过 %s%d%s  失败 %s%d%s\n' "$C_OK" "$PASS" "$C_RESET" "$C_ERR" "$FAIL" "$C_RESET"
[ $FAIL -eq 0 ] && ok "全部检查项通过" || warn "有 $FAIL 项未通过，见上方 ✗ 标记"
