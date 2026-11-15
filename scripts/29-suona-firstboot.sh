#!/usr/bin/env bash
# ============================================================================
# 29-suona-firstboot.sh - 首次开机自检：国产软件「开箱可达」（S-31）
#
# 定位（重要）：本脚本只做**检测与报告**，默认不安装任何软件。
#   SDEC-02「预装 vs 开箱可达」尚未裁决，自动下载 .deb 有合规风险；
#   因此这里的产出是「哪几款可达、哪几款缺、缺的官方源在哪」，
#   供产品决定用什么话术（不是「已预装」）。
#
# 对应 8 步交付清单第 6 步；状态口径：
#   全部可达 → PASS；部分缺失 → FAIL；一款都没装（原型机）→ NA
#
# 用法:
#   ./scripts/29-suona-firstboot.sh --report          # 文本报告
#   ./scripts/29-suona-firstboot.sh --report --json   # 机器可读
#   ./scripts/29-suona-firstboot.sh --list            # 只列清单
#   ./scripts/29-suona-firstboot.sh --install         # 打印逐款安装指引（不执行）
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

LIST="$PROJECT_ROOT/autoinstall/software-list.tsv"
ACTION="report"
JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --report)  ACTION=report ;;
    --list)    ACTION=list ;;
    --install) ACTION=install ;;
    --json)    JSON=1 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

[ -f "$LIST" ] || die "缺少清单: $LIST"

# 读取清单（跳过注释与空行）
read_list() {
  awk -F'\t' '/^[[:space:]]*#/ {next} NF>=3 {print}' "$LIST"
}

# 单款检测：命令存在 或 同名 .desktop 存在，即视为可达
detect_one() {
  local cmd="$1" bin
  bin="${cmd%% *}"
  if command -v "$bin" >/dev/null 2>&1; then
    printf 'INSTALLED'; return 0
  fi
  if ls "$HOME/.local/share/applications/$bin.desktop" \
        "/usr/share/applications/$bin.desktop" 2>/dev/null | grep -q .; then
    printf 'INSTALLED'; return 0
  fi
  printf 'MISSING'
}

if [ "$ACTION" = list ]; then
  printf '  %-16s %-24s %s\n' 名称 检测命令 来源
  read_list | while IFS=$'\t' read -r name cmd src note; do
    printf '  %-16s %-24s %s\n' "$name" "$cmd" "$src"
  done
  exit 0
fi

if [ "$ACTION" = install ]; then
  cat <<'EOF'
本脚本不自动安装。按 SDEC-02 未裁决，逐款走官方渠道，命令示意：

  1) 打开官方下载页，取 .deb
  2) sudo apt install ./<包名>.deb     （不要用 dpkg -i，缺依赖）
  3) 装完执行 ./scripts/29-suona-firstboot.sh --report 复核

注意：
  - 搜狗输入法会与 fcitx5 争输入框架，默认不装（ADR-05）
  - 百度网盘 / 微信等 Electron 应用若点不开，先查 chrome-sandbox 是否 4755（ISSUE-32）
  - Wayland 下会议类软件屏幕共享依赖 xdg-desktop-portal，失败时用 X11 会话兜底
EOF
  exit 0
fi

# ---- report ----------------------------------------------------------------
TOTAL=0; OK=0
ROWS=""
while IFS=$'\t' read -r name cmd src note; do
  TOTAL=$((TOTAL + 1))
  st="$(detect_one "$cmd")"
  [ "$st" = "INSTALLED" ] && OK=$((OK + 1))
  ROWS="${ROWS}${name}|${st}|${src}|${note}"$'\n'
done < <(read_list)

if [ "$JSON" -eq 1 ]; then
  printf '{"total":%d,"installed":%d,"items":[' "$TOTAL" "$OK"
  first=1
  while IFS='|' read -r name st src note; do
    [ -n "$name" ] || continue
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"name":"%s","status":"%s","source":"%s"}' "$name" "$st" "$src"
  done <<<"$ROWS"
  printf ']}\n'
else
  printf '  %-16s %-10s %s\n' 名称 状态 来源
  while IFS='|' read -r name st src note; do
    [ -n "$name" ] || continue
    printf '  %-16s %-10s %s\n' "$name" "$st" "$src"
  done <<<"$ROWS"
fi

printf 'SUMMARY: installed=%d total=%d\n' "$OK" "$TOTAL"
if [ "$OK" -eq 0 ]; then
  log "判定: NA（本机未安装这批软件，检测工具已交付；需在目标机型实测）"
elif [ "$OK" -lt "$TOTAL" ]; then
  log "判定: FAIL（$((TOTAL - OK)) 款不可达，交付前必须补齐）"
  exit 1
else
  ok "判定: PASS（$TOTAL 款全部可达）"
fi
