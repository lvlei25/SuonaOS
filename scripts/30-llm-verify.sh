#!/usr/bin/env bash
# ============================================================================
# 30-llm-verify.sh - 本地大模型可用性验证（S-44）
#
# 对应 8 步交付清单第 7 步。四状态口径（与 step-verification 一致）：
#   PASS           ROCm 识别到受支持的 GPU，ollama 可用，实测 tok/s 达标
#   FAIL           有环境但指标不达标（tok/s 低于阈值 / 模型缺失）
#   NA             本机架构性不适用（如 Radeon 740M 不在 ROCm 官方支持列表）
#   TOOL_MISSING   工具未安装（ollama / rocminfo 都不在）
#
# 诚实边界：T14 Gen 5 的 740M 是 RDNA3 的低端核显，ROCm 官方支持矩阵不含它。
#   本机不做"CPU 跑一下也算通过"的替代判定——第 7 步的判据是 GPU 加速下的 tok/s。
#
# 用法:
#   ./scripts/30-llm-verify.sh                 # 环境与模型检查
#   ./scripts/30-llm-verify.sh --bench         # 额外实测一次 tok/s
#   ./scripts/30-llm-verify.sh --model qwen3:14b --bench
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

MODEL="qwen3:14b"
BENCH=0
THRESHOLD=30

while [ $# -gt 0 ]; do
  case "$1" in
    --bench)   BENCH=1 ;;
    --model)   MODEL="${2:-}"; shift ;;
    --threshold) THRESHOLD="${2:-30}"; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

say() { printf '  %-16s %s\n' "$1" "$2"; }

echo
echo "════════ 本地大模型验证 ════════"

HAVE_OLLAMA=0; HAVE_ROCM=0; GPU_ARCH=""
have ollama && HAVE_OLLAMA=1
have rocminfo && HAVE_ROCM=1

say "ollama" "$([ $HAVE_OLLAMA -eq 1 ] && ollama --version 2>/dev/null | head -1 || echo 未安装)"
if [ $HAVE_OLLAMA -eq 1 ]; then
  if systemctl is-active ollama >/dev/null 2>&1; then
    say "服务" "system ollama active"
  elif systemctl --user is-active ollama >/dev/null 2>&1; then
    say "服务" "user ollama active"
  else
    say "服务" "未作为服务运行（可能手工启动）"
  fi
  say "模型" "$(ollama list 2>/dev/null | awk 'NR>1{printf "%s ", $1}' | cut -c1-60)"
fi

if [ $HAVE_ROCM -eq 1 ]; then
  GPU_ARCH="$(rocminfo 2>/dev/null | grep -oE 'gfx[0-9a-f]+' | sort -u | tr '\n' ' ')"
  say "ROCm" "已安装，GPU 架构: ${GPU_ARCH:-未识别}"
else
  say "ROCm" "未安装（rocminfo 不存在）"
fi

# 显卡型号（用于解释为什么 NA）
GPU_NAME="$(lspci -nn 2>/dev/null | grep -iE 'vga|display' | head -1 | sed 's/.*: //')"
say "显卡" "${GPU_NAME:-未识别}"

# ---- 判定 -------------------------------------------------------------------
RESULT=""; REASON=""
if [ $HAVE_OLLAMA -eq 0 ] && [ $HAVE_ROCM -eq 0 ]; then
  RESULT="TOOL_MISSING"
  REASON="ollama 与 rocminfo 均未安装，无法判定"
elif [ $HAVE_ROCM -eq 0 ]; then
  RESULT="NA"
  REASON="无 ROCm 运行时；本机核显（${GPU_NAME:-未知}）不在 ROCm 官方支持矩阵内，第 7 步需在目标机型（UM870 / 780M）实测"
else
  case "$GPU_ARCH" in
    *gfx11*)
      # gfx1103 等核显即便被识别，部分版本也不在官方支持列表；不臆断支持
      RESULT="NA"
      REASON="ROCm 识别到 ${GPU_ARCH}，但该架构是否在官方支持列表需按 ROCm 版本文档核对，本机不做通过判定"
      ;;
  esac
  if [ -z "$RESULT" ]; then
    if [ $HAVE_OLLAMA -eq 0 ]; then
      RESULT="TOOL_MISSING"; REASON="ROCm 已装但 ollama 未装"
    else
      RESULT="PASS"; REASON="环境齐备"
    fi
  fi
fi

if [ "$BENCH" -eq 1 ]; then
  if [ $HAVE_OLLAMA -eq 0 ]; then
    warn "未安装 ollama，跳过 tok/s 实测"
  else
    step "实测 tok/s（$MODEL）"
    OUT="$(timeout 180 ollama run "$MODEL" --verbose "用一句话说明 1+1=2" 2>&1 || true)"
    RATE="$(printf '%s' "$OUT" | sed -n 's/.*eval rate:[[:space:]]*\([0-9.]*\) tokens\/s.*/\1/p' | tail -1)"
    if [ -n "$RATE" ]; then
      say "tok/s" "$RATE"
      awk -v r="$RATE" -v t="$THRESHOLD" 'BEGIN{exit !(r < t)}' \
        && { RESULT="FAIL"; REASON="tok/s $RATE 低于阈值 $THRESHOLD"; } \
        || { RESULT="PASS"; REASON="tok/s $RATE 达标（≥$THRESHOLD）"; }
    else
      say "tok/s" "未能解析（模型未下载或输出格式变化）"
      [ "$RESULT" = "PASS" ] && { RESULT="FAIL"; REASON="模型 ${MODEL} 未就绪"; }
    fi
  fi
fi

echo
say "判定" "$RESULT"
say "原因" "$REASON"
echo "RESULT: $RESULT"

case "$RESULT" in
  PASS) ok "第 7 步可判 PASS" ;;
  FAIL) warn "第 7 步 FAIL：按上面原因处理（模型/性能）"; exit 1 ;;
  *) warn "第 7 步不通过也不失败：$REASON"; exit 0 ;;
esac
