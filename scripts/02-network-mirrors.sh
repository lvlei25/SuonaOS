#!/usr/bin/env bash
# ============================================================================
# 02-network-mirrors.sh - 阶段 1：网络加速（apt / pip / npm / GitHub）
# 用法: ./scripts/02-network-mirrors.sh [--apt] [--pip] [--npm] [--github] [--all]
#       默认 --all
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
DO_APT=0; DO_PIP=0; DO_NPM=0; DO_GH=0
[ $# -eq 0 ] && set -- --all
for a in "$@"; do
  case "$a" in
    --apt) DO_APT=1 ;;
    --pip) DO_PIP=1 ;;
    --npm) DO_NPM=1 ;;
    --github) DO_GH=1 ;;
    --all) DO_APT=1; DO_PIP=1; DO_NPM=1; DO_GH=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) die "未知参数: $a" ;;
  esac
done

# ---- apt -------------------------------------------------------------------
if [ $DO_APT -eq 1 ]; then
  step "1/4 切换 apt 源到 TUNA"
  require_sudo
  SRC=/etc/apt/sources.list.d/ubuntu.sources
  if grep -q 'mirrors.tuna' "$SRC" 2>/dev/null; then
    ok "已经是 TUNA 源，跳过"
  else
    backup_file "$SRC"
    # Ubuntu 24.04+ 使用 deb822 格式，直接替换 URI 主机
    sudo sed -i \
      -e "s|http://cn.archive.ubuntu.com/ubuntu/|${MIRROR_TUNA}/ubuntu/|g" \
      -e "s|http://archive.ubuntu.com/ubuntu/|${MIRROR_TUNA}/ubuntu/|g" \
      -e "s|http://security.ubuntu.com/ubuntu/|${MIRROR_TUNA}/ubuntu/|g" \
      "$SRC"
    ok "已替换为 ${MIRROR_TUNA}/ubuntu/"
    sudo apt-get update -qq && ok "apt update 通过" || warn "apt update 失败，可执行 rollback.sh 还原"
  fi
  log "当前源："
  grep -E '^URIs' "$SRC" | sed 's/^/  /'
fi

# ---- pip -------------------------------------------------------------------
if [ $DO_PIP -eq 1 ]; then
  step "2/4 配置 pip 镜像"
  PIP_CONF="$HOME/.config/pip/pip.conf"
  mkdir -p "$(dirname "$PIP_CONF")"
  [ -f "$PIP_CONF" ] && backup_file "$PIP_CONF"
  cat >"$PIP_CONF" <<EOF
[global]
index-url = ${MIRROR_TUNA}/pypi/web/simple
trusted-host = mirrors.tuna.tsinghua.edu.cn
timeout = 30

[install]
upgrade-strategy = only-if-needed
EOF
  ok "已写入 $PIP_CONF"
fi

# ---- npm -------------------------------------------------------------------
if [ $DO_NPM -eq 1 ]; then
  step "3/4 配置 npm 镜像"
  if have npm; then
    npm config set registry https://registry.npmmirror.com --global 2>/dev/null \
      || npm config set registry https://registry.npmmirror.com
    ok "npm registry -> $(npm config get registry)"
  else
    warn "npm 未安装，跳过（将在阶段 3 安装 Node 后重跑本项）"
  fi
fi

# ---- GitHub ----------------------------------------------------------------
if [ $DO_GH -eq 1 ]; then
  step "4/4 配置 GitHub 加速"
  # 不默认改写 git 全局 url，避免影响 SSH 认证；改为提供 gitc 别名
  if have git; then
    git config --global url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/" 2>/dev/null
    ok "已配置 https 克隆走 ghfast.top 加速"
    warn "如遇私有仓库认证失败，执行: git config --global --unset url.https://ghfast.top/https://github.com/.insteadOf"
  else
    warn "git 未安装，跳过"
  fi
fi

step "完成"
log "日志: ${LOG_FILE#$PROJECT_ROOT/}"
