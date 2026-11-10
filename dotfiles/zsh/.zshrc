# ============================================================================
# ~/.zshrc - 由 linux-tune 管理（源文件: dotfiles/zsh/.zshrc）
# 修改请改源文件后重新执行 scripts/04-devtools.sh
# ============================================================================

# ---- 基础 --------------------------------------------------------------
export LANG=zh_CN.UTF-8
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R -F -X'
export MANPAGER='less -R'

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS HIST_VERIFY SHARE_HISTORY \
       EXTENDED_HISTORY INC_APPEND_HISTORY

setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS

# ---- 补全与高亮 --------------------------------------------------------
autoload -Uz compinit && compinit -i -d ~/.zcompdump
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh/compcache

[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# 方向键历史搜索
bindkey '^[[A' history-search-backward 2>/dev/null
bindkey '^[[B' history-search-forward 2>/dev/null

# ---- 提示符 ------------------------------------------------------------
if command -v starship >/dev/null 2>&1; then
  export STARSHIP_CONFIG="$HOME/.config/starship.toml"
  eval "$(starship init zsh)"
else
  PROMPT='%F{green}%n%f@%F{cyan}%m%f:%F{blue}%~%f %# '
fi

# ---- 别名 --------------------------------------------------------------
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lh'
alias la='ls -lah'
alias lt='ls -lh --sort=time'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias v='vim'
alias cat='bat --paging=never'   # Ubuntu 下由 ~/.local/bin/bat 软链到 batcat
alias df='df -h'
alias du='du -sh'
alias ports='ss -tulpn'
alias meminfo='free -h && ps -eo rss,comm --sort=-rss | head -15'
alias sys='systemd-analyze; systemd-analyze blame | head -15'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -15'

# fzf
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && \
  source /usr/share/doc/fzf/examples/key-bindings.zsh

# ---- 环境变量 ----------------------------------------------------------
# 输入法（fcitx5 on Wayland）
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
export SDL_IM_MODULE=fcitx
export GLFW_IM_MODULE=ibus

# npm 全局包目录（避免 sudo）
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
path=($HOME/.local/bin $HOME/.npm-global/bin $path)

# 镜像
export GOPROXY=https://goproxy.cn,direct
export RUSTUP_DIST_SERVER=https://rsproxy.cn
export RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup

# ---- 启动 --------------------------------------------------------------
# 仅真实终端（非管道/非脚本）打印系统概览
if [[ -o interactive ]] && [ -t 1 ] && command -v fastfetch >/dev/null 2>&1; then
  fastfetch --config none 2>/dev/null || true
fi

# 手机一键投屏
alias mc="$HOME/CodeBuddy/work/linux-tune_SuonaOS/scripts/mobile-connect.sh"
