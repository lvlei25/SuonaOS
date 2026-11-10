#!/usr/bin/env bash
# ============================================================================
# 04-devtools.sh - 阶段 3：开发环境
#   zsh + starship + 插件、tmux、vim、Node.js、uv
# 用法: ./scripts/04-devtools.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DOT="$PROJECT_ROOT/dotfiles"
step "阶段 3 - 开发环境"
require_sudo
# pipx 安装的工具落在 ~/.local/bin，当前非交互 shell 需要显式加入 PATH
export PATH="$HOME/.local/bin:$PATH"

# ---- 1. 装包 ---------------------------------------------------------------
step "1/5 安装开发工具"
apt_install nodejs npm \
  zsh-autosuggestions zsh-syntax-highlighting starship \
  fastfetch wl-clipboard
ok "Node.js $(node -v 2>/dev/null) / npm $(npm -v 2>/dev/null)"

# ---- 2. 软链 dotfiles ------------------------------------------------------
step "2/5 链接配置文件"
link_file() {
  local src="$1" dst="$2"
  [ -f "$src" ] || { warn "源文件不存在: $src"; return 1; }
  mkdir -p "$(dirname "$dst")"
  # 已是指向本项目的软链则跳过
  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
    log "已链接: ${dst/#$HOME/\~}"
    return 0
  fi
  # 已存在的实体文件先备份
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    backup_file "$dst"
  fi
  ln -sfn "$src" "$dst"
  ok "${dst/#$HOME/\~} -> ${src#$PROJECT_ROOT/}"
}

link_file "$DOT/zsh/.zshrc"        "$HOME/.zshrc"
link_file "$DOT/tmux/.tmux.conf"   "$HOME/.tmux.conf"
link_file "$DOT/vim/.vimrc"        "$HOME/.vimrc"
link_file "$DOT/starship.toml"     "$HOME/.config/starship.toml"
mkdir -p "$HOME/.vim/undo"

# ---- 3. npm / uv -----------------------------------------------------------
step "3/5 Node 与 Python 工具链"
npm config set registry https://registry.npmmirror.com >/dev/null 2>&1
ok "npm registry = $(npm config get registry)"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
mkdir -p "$HOME/.npm-global"

if have uv; then
  ok "uv 已安装: $(uv --version)"
else
  pipx install uv >/dev/null 2>&1 && ok "uv 已安装: $(uv --version)" || warn "uv 安装失败（可稍后手动 pipx install uv）"
fi
python3 -m pip config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple >/dev/null 2>&1 \
  && ok "pip 索引已指向 TUNA"

# ---- 4. 默认 shell ---------------------------------------------------------
step "4/5 设置默认 shell"
CUR_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$CUR_SHELL" = "/usr/bin/zsh" ] || [ "$CUR_SHELL" = "/bin/zsh" ]; then
  ok "默认 shell 已是 zsh"
else
  sudo chsh -s /usr/bin/zsh "$USER" && ok "默认 shell: $CUR_SHELL -> /usr/bin/zsh（下次登录生效）"
fi

# ---- 5. 校验 ---------------------------------------------------------------
step "5/5 校验"
FAIL=0
for c in zsh tmux vim node npm starship fastfetch uv wl-copy; do
  if have "$c"; then
    printf '  %s%-10s%s %s\n' "$C_OK" "$c" "$C_RESET" "$(command -v "$c")"
  else
    printf '  %s%-10s%s 缺失\n' "$C_ERR" "$c" "$C_RESET"; FAIL=1
  fi
done
echo
for f in ~/.zshrc ~/.tmux.conf ~/.vimrc ~/.config/starship.toml; do
  if [ -L "$f" ]; then
    printf '  %s%s%s -> %s\n' "$C_OK" "${f/#$HOME/\~}" "$C_RESET" "$(readlink "$f")"
  else
    printf '  %s%s%s 非软链\n' "$C_WARN" "${f/#$HOME/\~}" "$C_RESET"
  fi
done
echo
[ $FAIL -eq 0 ] && ok "开发环境部署完成，重新打开终端即可生效" || warn "部分组件缺失"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
