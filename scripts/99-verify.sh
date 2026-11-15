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
  RENDER="$HOME/.config/fontconfig/conf.d/99-suona-render.conf"
  if [ -f "$RENDER" ]; then
    chk "字体渲染覆盖层已安装（REQ-35）" "grep -q 'hintstyle' '$RENDER'"
    chk "未改动字体族（只调渲染）" "[ ! -f $HOME/.config/fontconfig/fonts.conf ]"
    val "字体状态：系统默认字体 + Suona 渲染覆盖 $CUR_FONT"
  else
    chk "fontconfig 已按回退清理" "[ ! -f $HOME/.config/fontconfig/fonts.conf ]"
    val "字体状态：回退态（REQ-06 = reverted / ADR-07）$CUR_FONT"
  fi
fi
chk "中文字体可用" "[ $(fc-list :lang=zh 2>/dev/null | wc -l) -gt 20 ]"

echo
echo "════════ 输入法 ════════"
chk "会话环境变量指向 fcitx5" "grep -q 'GTK_IM_MODULE=fcitx' $HOME/.config/environment.d/99-input-method.conf"
chk "fcitx5 用户服务已启用" "systemctl --user is-enabled --quiet fcitx5.service"
chk "fcitx5 服务运行中" "systemctl --user is-active --quiet fcitx5.service"
chk "fcitx5 进程运行中" "pgrep -x fcitx5"
chk "旧 autostart 已清理" "[ ! -f $HOME/.config/autostart/fcitx5.desktop ]"
# 候选框风格必须跟明暗一致（REQ-41）：浅色桌面配深色候选框会显得割裂。
FCONF="$HOME/.config/fcitx5/conf/classicui.conf"
if [ -f "$FCONF" ]; then
  FTHEME=$(sed -n 's/^Theme=//p' "$FCONF" | head -1)
  CS=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
  case "$FTHEME" in
    Catppuccin-latte-*|Catppuccin-mocha-*)
      case "$CS" in
        *dark*) EXPECT="Catppuccin-mocha" ;;
        *)      EXPECT="Catppuccin-latte" ;;
      esac
      chk "候选框主题跟随明暗（期望 $EXPECT）" "echo '$FTHEME' | grep -q '$EXPECT'"
      val "候选框: $FTHEME（color-scheme=$CS）"
      ;;
    *)
      val "候选框: $FTHEME（非 Catppuccin 系列，跳过明暗一致性断言）"
      ;;
  esac
fi
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
# 「充满提示」timer 由用户决定是否启用（2026-11-15 起默认关闭），此处不断言
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
echo "════════ 视觉令牌（ADR-36）════════"
# 只断言「没有苹果化残留」与「令牌一致」，不断言审美
BTN_LAYOUT=$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null | tr -d "'")
case "$BTN_LAYOUT" in
  close,*)
    chk "窗口按钮不在左侧（无 macOS 红绿灯布局）" "false"
    val "按钮布局: $BTN_LAYOUT（WhiteSur 遗留，跑 22-suona-identity.sh --install）"
    ;;
  *)
    chk "窗口按钮在右侧" "[ -n '$BTN_LAYOUT' ]"
    val "按钮布局: $BTN_LAYOUT"
    ;;
esac

CUR_CURSOR=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
chk "光标未使用 WhiteSur" "[ '${CUR_CURSOR}' != 'WhiteSur-cursors' ]"
chk "无 WhiteSur 光标目录残留" "[ ! -d $HOME/.local/share/icons/WhiteSur-cursors ]"
val "光标: $CUR_CURSOR"

if gsettings list-keys org.gnome.desktop.interface 2>/dev/null | grep -qx accent-color; then
  ACC=$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null | tr -d "'")
  if [ -f "$HOME/.config/linux-tune/identity.conf" ]; then
    WANT=$(bash -c '. "$1"; echo "${ACCENT:-}"' _ "$HOME/.config/linux-tune/identity.conf" 2>/dev/null)
    if [ -n "$WANT" ]; then
      chk "强调色与 token 记录一致（$WANT）" "[ '$ACC' = '$WANT' ]"
    else
      val "强调色: $ACC（token 文件无 ACCENT 字段）"
    fi
  else
    val "强调色: $ACC（未建立 token 文件）"
  fi
else
  val "强调色: 本机 GNOME 不支持 accent-color（跳过）"
fi

echo
echo "════════ 键位与手势 ════════"
KB=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)
KB_N=$(printf '%s' "$KB" | grep -oE 'custom-keybindings/[a-z]+/' | wc -l)
if [ "$KB_N" -gt 0 ]; then
  chk "Suona 键位已注册（$KB_N 条）" "[ '$KB_N' -ge 1 ]"
  for id in terminal files calculator clipboard; do
    P="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/$id/"
    if printf '%s' "$KB" | grep -q "$P"; then
      B=$(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$P" binding 2>/dev/null | tr -d "'")
      chk "键位 $id 有绑定" "[ -n '$B' ]"
    fi
  done
else
  val "键位: 未安装 Suona 键位表（24-keys-gestures.sh）"
fi
if gsettings list-keys org.gnome.desktop.interface 2>/dev/null | grep -qx enable-hot-corners; then
  chk "热角已开启" "gsettings get org.gnome.desktop.interface enable-hot-corners | grep -q true"
fi
val "触摸板: 点按 $(gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click 2>/dev/null) / 自然滚动 $(gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll 2>/dev/null)"

# 窗口/工作区（REQ-43）：只断言"必须有"的那几条，其余沿用系统默认，不做全量锁死
WM_CLOSE=$(gsettings get org.gnome.desktop.wm.keybindings close 2>/dev/null)
case "$WM_CLOSE" in
  *"'<Super>Q'"*) chk "关闭窗口 Super+Q 已绑定" "true" ;;
  *)              chk "关闭窗口 Super+Q 已绑定" "false" ;;
esac
WM_SW=$(gsettings get org.gnome.desktop.wm.keybindings switch-windows 2>/dev/null)
# 注意别把数组值拼进 chk 的 eval 字符串：['<Super>grave'] 里的引号会把 eval 拆坏。
if [ -n "$WM_SW" ] && [ "$WM_SW" != "@as []" ]; then
  chk "同应用窗口切换已绑定" "true"
else
  chk "同应用窗口切换已绑定" "false"
fi
if gsettings list-keys org.gnome.shell.extensions.tiling-assistant >/dev/null 2>&1; then
  TL=$(gsettings get org.gnome.shell.extensions.tiling-assistant tile-left-half 2>/dev/null)
  TR=$(gsettings get org.gnome.shell.extensions.tiling-assistant tile-right-half 2>/dev/null)
  case "$TL$TR" in
    *"'<Super>Left'"*"'<Super>Right'"*) chk "半屏平铺键 Super+←/→ 就位" "true" ;;
    *)                                  chk "半屏平铺键 Super+←/→ 就位" "false" ;;
  esac
  val "平铺: 左 $TL / 右 $TR"
fi
val "关窗: $WM_CLOSE / 同应用: $WM_SW"

echo
echo "════════ 即时预览与剪贴板 ════════"
if pgrep -x sushi >/dev/null 2>&1 || pkg_installed gnome-sushi 2>/dev/null || command -v sushi >/dev/null 2>&1; then
  chk "glib 即时预览已安装（gnome-sushi）" "command -v sushi"
else
  val "即时预览: 未安装 gnome-sushi（空格预览不可用）"
fi
if [ -x "$HOME/.local/bin/suona-clip" ]; then
  chk "suona-clip 已安装" "[ -x $HOME/.local/bin/suona-clip ]"
  chk "剪贴板采集服务已启用" "systemctl --user is-enabled --quiet suona-clipboard.service"
  chk "剪贴板采集服务运行中" "systemctl --user is-active --quiet suona-clipboard.service"
  val "剪贴板历史: $([ -f $HOME/.local/state/suona/clipboard.tsv ] && wc -l <$HOME/.local/state/suona/clipboard.tsv || echo 0) 条"
else
  val "剪贴板历史: 未安装（25-quicklook-clipboard.sh）"
fi

echo
echo "════════ 系统快照 ════════"
if command -v timeshift >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    TS_OUT=$(sudo -n timeshift --list 2>&1 || true)
    if printf '%s' "$TS_OUT" | grep -qE '^(Mode|Device)[[:space:]]*:'; then
      chk "Timeshift 配置可读" "true"
      TS_N=$(printf '%s' "$TS_OUT" | awk '/^[[:space:]]*[0-9]+[[:space:]]+>/{n++} END{print n+0}')
      if [ "${TS_N:-0}" -ge 1 ]; then
        chk "至少存在 1 个快照（可回退点）" "[ '$TS_N' -ge 1 ]"
      else
        val "快照: 0 个（跑 26-snapshot.sh --snapshot \"基线\"）"
      fi
      # 自动化与新鲜度：开了每日快照，且最近一份不超过 48 小时
      TS_SCHED=$(sed -n 's/.*"schedule_daily"[^"]*"\([a-z]*\)".*/\1/p' /etc/timeshift/timeshift.json 2>/dev/null)
      chk "每日快照已启用" "[ '${TS_SCHED}' = true ]"
      TS_NEW=$(printf '%s' "$TS_OUT" | awk '/^[[:space:]]*[0-9]+[[:space:]]+>/{print $3}' | tail -1)
      if [ -n "$TS_NEW" ]; then
        # 名字形如 2026-11-15_14-21-28；日期与时间分开转，别用 sed 改第 N 个减号
        TS_D="${TS_NEW%%_*}"; TS_T="${TS_NEW#*_}"; TS_T="${TS_T//-/:}"
        TS_TS=$(date -d "$TS_D $TS_T" +%s 2>/dev/null)
        if [ -n "$TS_TS" ]; then
          TS_AGE=$(( ($(date +%s) - TS_TS) / 60 ))
          chk "最近快照在 48 小时内" "[ '$TS_AGE' -le 2880 ]"
          val "最近快照: $TS_NEW（${TS_AGE} 分钟前）"
        fi
      fi
      val "快照: $TS_N 个（rsync / ext4；同盘快照不防盘损）"
    else
      chk "Timeshift 配置可读" "false"
      val "Timeshift 已装但未初始化（sudo timeshift --setup）"
    fi
  else
    val "快照: 已安装 timeshift，免密 sudo 不可用无法读取（不猜测）"
  fi
else
  val "快照: 未安装 timeshift"
fi

echo
echo "════════ 安全基线 ════════"
if command -v ufw >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  UFWH=$(sudo -n ufw status 2>/dev/null | head -1)
  if printf '%s' "$UFWH" | grep -qE 'active|激活'; then
    chk "ufw 已启用" "true"
  else
    chk "ufw 已启用" "false"
  fi
  val "ufw: ${UFWH:-不可读}"
else
  val "ufw: 未安装或免密 sudo 不可用（不猜测状态）"
fi
if pkg_installed unattended-upgrades 2>/dev/null; then
  chk "安全自动更新已启用" "[ '$(systemctl is-enabled unattended-upgrades.service 2>/dev/null)' = enabled ]"
  chk "自动更新策略文件存在" "[ -f /etc/apt/apt.conf.d/20auto-upgrades ]"
else
  val "自动更新: 未安装 unattended-upgrades"
fi

echo
echo "════════ 外设与电源 ════════"
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then
  chk "电池节点存在" "true"
  for b in /sys/class/power_supply/BAT*; do
    [ -d "$b" ] || continue
    if [ -e "$b/charge_control_end_threshold" ]; then
      CS=$(cat "$b/charge_control_start_threshold" 2>/dev/null)
      CE=$(cat "$b/charge_control_end_threshold" 2>/dev/null)
      chk "充电阈值 75/80 生效" "[ '$CS' = 75 ] && [ '$CE' = 80 ]"
      val "$(basename "$b"): $(cat "$b/capacity" 2>/dev/null)% / 阈值 ${CS}/${CE}"
    fi
  done
else
  val "电池: 当前无 BAT* 节点（可能为 ISSUE-33 抖动，跑 28 --battery 60）"
fi
TC_N=$(ls -d /sys/class/typec/port[0-9]* 2>/dev/null | wc -l)
val "USB-C 端口: $TC_N 个；显示输出: $(grep -l '^connected' /sys/class/drm/card*-*/status 2>/dev/null | wc -l) 个已连接"

echo
echo "════════ 产品骨架（S-31 / S-44）════════"
chk "首次开机自检脚本存在" "[ -x $PROJECT_ROOT/scripts/29-suona-firstboot.sh ]"
chk "大模型验证脚本存在" "[ -x $PROJECT_ROOT/scripts/30-llm-verify.sh ]"
chk "国产软件清单存在" "[ -s $PROJECT_ROOT/autoinstall/software-list.tsv ]"
chk "autoinstall 骨架存在" "[ -s $PROJECT_ROOT/autoinstall/user-data.yaml ]"
val "提示: 工具存在不等于通过；第 6/7 步按 step-verify 的四状态判定"

echo
echo "════════ 汇总 ════════"
printf '  通过 %s%d%s  失败 %s%d%s\n' "$C_OK" "$PASS" "$C_RESET" "$C_ERR" "$FAIL" "$C_RESET"
[ $FAIL -eq 0 ] && ok "全部检查项通过" || warn "有 $FAIL 项未通过，见上方 ✗ 标记"
