#!/usr/bin/env bash
# ============================================================================
# 01-install-base.sh - 阶段 0：基础工具链部署
# 说明: 安装后续所有阶段所依赖的命令行工具与构建依赖，幂等可重复执行
# 用法: ./scripts/01-install-base.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

step "阶段 0 - 基础工具链部署"
require_sudo

# ---- 1. 刷新软件源 ---------------------------------------------------------
step "1/4 刷新 apt 索引"
sudo apt-get update -qq && ok "apt update 完成" || warn "apt update 有警告，继续"

# ---- 2. 基础工具 -----------------------------------------------------------
step "2/4 安装基础工具"
BASE_PKGS=(
  # 版本控制与下载
  git curl ca-certificates gnupg
  # 编译工具链
  build-essential pkg-config
  # 终端常用
  vim tmux zsh htop tree jq unzip zip rsync
  # 现代化 CLI 替代品
  ripgrep fd-find bat fzf btop
  # Python 工具链基座
  python3-pip python3-venv pipx
  # 硬件监控
  lm-sensors
  # 主题编译依赖（WhiteSur 需要 sassc + glib-compile-resources）
  sassc libglib2.0-dev-bin dconf-cli
  # GNOME 调整
  gnome-tweaks gnome-shell-extension-manager gnome-shell-extension-prefs
)
apt_install "${BASE_PKGS[@]}"

# ---- 3. Ubuntu 特有命名修正 ------------------------------------------------
step "3/4 修正 Debian 化命名"
# Ubuntu 把 fd/bat 改名为 fdfind/batcat，建立短名软链以便统一使用
mkdir -p ~/.local/bin
[ -x /usr/bin/fdfind ] && ln -sf /usr/bin/fdfind ~/.local/bin/fd && ok "fd -> fdfind"
[ -x /usr/bin/batcat ] && ln -sf /usr/bin/batcat ~/.local/bin/bat && ok "bat -> batcat"

if ! grep -q 'HOME/.local/bin' ~/.profile 2>/dev/null; then
  printf '\n# 用户级可执行文件\ncase ":$PATH:" in\n  *":$HOME/.local/bin:"*) ;;\n  *) PATH="$HOME/.local/bin:$PATH" ;;\nesac\n' >>~/.profile
  ok "已把 ~/.local/bin 写入 ~/.profile"
fi

# ---- 4. 校验 ---------------------------------------------------------------
step "4/4 校验安装结果"
FAIL=0
for c in git curl vim tmux zsh htop btop rg fzf jq sassc sensors; do
  if have "$c"; then
    printf '  %s%-10s%s %s\n' "$C_OK" "$c" "$C_RESET" "$(command -v "$c")"
  else
    printf '  %s%-10s%s 缺失\n' "$C_ERR" "$c" "$C_RESET"; FAIL=1
  fi
done

echo
if [ $FAIL -eq 0 ]; then
  ok "基础工具链部署完成"
  log "git   $(git --version 2>/dev/null)"
  log "zsh   $(zsh --version 2>/dev/null)"
  log "vim   $(vim --version 2>/dev/null | head -1)"
  log "tmux  $(tmux -V 2>/dev/null)"
else
  warn "部分工具缺失，请检查上方输出"
fi
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
