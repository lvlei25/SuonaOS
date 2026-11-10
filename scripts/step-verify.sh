#!/usr/bin/env bash
# ============================================================================
# step-verify.sh - 8 步交付验证清单驱动（S-12）
#   定义见 spec/suonaos/08-step-verification.md
#   第 1~5、8 步可自动执行；第 6/7 步工具未交付，标 TOOL_MISSING 而非通过
# 特性: 只读，不修改系统配置；每步原始输出留存到 logs/step-verify-<RUN_ID>/
# 用法: ./scripts/step-verify.sh
# ============================================================================
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

OUT_DIR="$LOG_DIR/step-verify-$RUN_ID"
mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.txt"
: >"$SUMMARY"

P_PASS=0; P_FAIL=0; P_NA=0; P_MISS=0
RESULTS=()

record() { # record <步号> <名称> <状态> <说明>
  local no="$1" name="$2" st="$3" note="$4"
  RESULTS+=("$no|$name|$st|$note")
  case "$st" in
    PASS) P_PASS=$((P_PASS+1)) ;;
    FAIL) P_FAIL=$((P_FAIL+1)) ;;
    NA) P_NA=$((P_NA+1)) ;;
    TOOL_MISSING) P_MISS=$((P_MISS+1)) ;;
  esac
  printf '[%s] 第 %s 步 %-22s %s\n' "$st" "$no" "$name" "$note" | tee -a "$SUMMARY"
}

fail_note() { printf '详见 %s' "${1#$PROJECT_ROOT/}"; }

step "1/8 硬件与固件基线（00-preflight.sh）"
if [ -f "$PROJECT_ROOT/scripts/00-preflight.sh" ]; then
  if timeout 240 bash "$PROJECT_ROOT/scripts/00-preflight.sh" >"$OUT_DIR/01-preflight.log" 2>&1; then
    BASE_DIR=$(ls -dt "$PROJECT_ROOT"/baseline/*/ 2>/dev/null | head -1)
    N=$(ls -1 "$BASE_DIR" 2>/dev/null | wc -l)
    if [ "$N" -ge 20 ]; then
      record 1 "硬件与固件基线" PASS "baseline 快照 $N 个文件"
    else
      record 1 "硬件与固件基线" FAIL "快照仅 $N 个文件（判据 ≥20）"
    fi
  else
    record 1 "硬件与固件基线" FAIL "采集脚本报错，$(fail_note "$OUT_DIR/01-preflight.log")"
  fi
else
  record 1 "硬件与固件基线" FAIL "缺少 scripts/00-preflight.sh"
fi

step "2/8 启动链完整性（preboot-check.sh）"
if [ -f "$PROJECT_ROOT/scripts/preboot-check.sh" ]; then
  timeout 180 bash "$PROJECT_ROOT/scripts/preboot-check.sh" >"$OUT_DIR/02-preboot.log" 2>&1
  LINE=$(grep -E '通过 [0-9]+' "$OUT_DIR/02-preboot.log" | tail -1)
  F=$(printf '%s' "$LINE" | sed -n 's/.*失败 \([0-9]*\).*/\1/p')
  W=$(printf '%s' "$LINE" | sed -n 's/.*警告 \([0-9]*\).*/\1/p')
  if [ "${F:-1}" -eq 0 ] && [ "${W:-1}" -eq 0 ]; then
    record 2 "启动链完整性" PASS "${LINE:-全部通过}"
  else
    record 2 "启动链完整性" FAIL "失败 ${F:-?} 警告 ${W:-?}，禁止重启"
  fi
else
  record 2 "启动链完整性" FAIL "缺少 scripts/preboot-check.sh"
fi

step "3/8 性能基准（bench.sh，含量化阈值）"
if [ -f "$PROJECT_ROOT/scripts/bench.sh" ]; then
  timeout 240 bash "$PROJECT_ROOT/scripts/bench.sh" >"$OUT_DIR/03-bench.log" 2>&1
  PY=$(sed -n 's/^python 求和 1e7[[:space:]]*\([0-9.]*\).*/\1/p' "$OUT_DIR/03-bench.log" | head -1)
  SHA=$(sed -n 's/^sha256[[:space:]]*\([0-9]*\) MB\/s.*/\1/p' "$OUT_DIR/03-bench.log" | head -1)
  DISK=$(sed -n 's/^磁盘写[[:space:]]*\([0-9]*\) MB\/s.*/\1/p' "$OUT_DIR/03-bench.log" | head -1)
  FREQ=$(sed -n 's/^当前频率均值[[:space:]]*\([0-9]*\) MHz (上限 \([0-9]*\).*/\1 \2/p' "$OUT_DIR/03-bench.log" | head -1)
  FQ=${FREQ% *}; MX=${FREQ#* }
  BAD=""
  awk -v v="${PY:-99}" 'BEGIN{exit !(v>0.60)}' && BAD="$BAD python>0.60s"
  [ -n "$SHA" ] && [ "$SHA" -lt 800 ] && BAD="$BAD sha256<800"
  [ -n "$DISK" ] && [ "$DISK" -lt 500 ] && BAD="$BAD disk<500"
  if [ -n "$MX" ] && [ "$MX" -gt 0 ] && [ $((FQ * 2)) -lt "$MX" ]; then
    BAD="$BAD freq<50%"
  fi
  if [ -z "$BAD" ]; then
    record 3 "性能基准" PASS "py ${PY:-?}s / sha ${SHA:-?}MB/s / disk ${DISK:-?}MB/s / ${FQ:-?}MHz"
  else
    record 3 "性能基准" FAIL "未达阈值:$BAD（先排除 EC/SMU 锁频）"
  fi
else
  record 3 "性能基准" FAIL "缺少 scripts/bench.sh"
fi

step "4/8 系统配置（99-verify.sh）"
if [ -f "$PROJECT_ROOT/scripts/99-verify.sh" ]; then
  timeout 180 bash "$PROJECT_ROOT/scripts/99-verify.sh" >"$OUT_DIR/04-verify.log" 2>&1
  VF=$(grep -oE '失败 [0-9]+' "$OUT_DIR/04-verify.log" | tail -1 | grep -oE '[0-9]+')
  if [ "${VF:-1}" -eq 0 ]; then
    record 4 "系统配置" PASS "$(grep -E '通过 [0-9]+' "$OUT_DIR/04-verify.log" | tail -1)"
  else
    record 4 "系统配置" FAIL "体检失败 ${VF:-?} 项"
  fi
else
  record 4 "系统配置" FAIL "缺少 scripts/99-verify.sh"
fi

step "5/8 输入法（服务 + 变量 + 方案）"
{
  echo "is-enabled: $(systemctl --user is-enabled fcitx5.service 2>&1)"
  echo "is-active : $(systemctl --user is-active fcitx5.service 2>&1)"
  echo "IM_MODULE : $(grep -h '^GTK_IM_MODULE' "$HOME/.config/environment.d/"*.conf 2>/dev/null | head -1)"
  echo "IM_NAME   : $(fcitx5-remote -n 2>&1)"
} >"$OUT_DIR/05-ime.log" 2>&1
IME_EN=$(sed -n 's/^is-enabled: //p' "$OUT_DIR/05-ime.log")
IME_ACT=$(sed -n 's/^is-active : //p' "$OUT_DIR/05-ime.log")
IME_NAME=$(sed -n 's/^IM_NAME   : //p' "$OUT_DIR/05-ime.log")
if [ "$IME_EN" = enabled ] && [ "$IME_ACT" = active ] && [ -n "$IME_NAME" ] \
   && grep -q 'fcitx' "$OUT_DIR/05-ime.log"; then
  record 5 "输入法" PASS "服务 active，当前方案 $IME_NAME（候选框需人工目视）"
else
  record 5 "输入法" FAIL "enabled=${IME_EN:-?} active=${IME_ACT:-?} 方案=${IME_NAME:-空}"
fi

step "6/8 国产软件 11 款 + 屏幕共享"
if [ -x "$PROJECT_ROOT/scripts/suona-firstboot.sh" ] || [ -f "$PROJECT_ROOT/scripts/firstboot-check.sh" ]; then
  record 6 "国产软件兼容" TOOL_MISSING "自检脚本存在但尚未纳入本清单（S-31 未完成）"
else
  record 6 "国产软件兼容" TOOL_MISSING "自检工具未交付（S-31），本机未装这批软件"
fi

step "7/8 本地 LLM / tok/s"
if [ -f "$PROJECT_ROOT/scripts/llm-verify.sh" ]; then
  record 7 "本地 LLM" TOOL_MISSING "llm-verify.sh 存在但未纳入（S-44 未完成）"
else
  record 7 "本地 LLM" TOOL_MISSING "llm-verify.sh 未交付（S-44），本机无 ollama/ROCm 环境"
fi

step "8/8 回滚与安全"
RB=""; RESCUE_OK=0; UFW_ST=""
if [ -f "$PROJECT_ROOT/scripts/rollback.sh" ]; then
  timeout 60 bash "$PROJECT_ROOT/scripts/rollback.sh" --list >"$OUT_DIR/08-rollback.log" 2>&1
  RB=$(grep -cE '^[[:space:]]+[0-9]{8}-[0-9]{6}|^[[:space:]]+[A-Za-z0-9_-]+[[:space:]]+文件' "$OUT_DIR/08-rollback.log")
fi
if [ -f "$PROJECT_ROOT/scripts/rescue.sh" ]; then
  timeout 90 bash "$PROJECT_ROOT/scripts/rescue.sh" --dry-run >>"$OUT_DIR/08-rollback.log" 2>&1 \
    && RESCUE_OK=1
fi
UFW_ST=$(sudo -n ufw status 2>/dev/null | head -1)
FS=$(findmnt -no FSTYPE / 2>/dev/null)
{
  echo "备份批次数: ${RB:-0}"
  echo "rescue --dry-run: $([ $RESCUE_OK -eq 1 ] && echo OK || echo FAIL)"
  echo "ufw: ${UFW_ST:-不可读}"
  echo "root fs: ${FS:-未知}（btrfs/LUKS 不适用则为 NA）"
} >>"$OUT_DIR/08-rollback.log"
if [ "${RB:-0}" -ge 1 ] && [ $RESCUE_OK -eq 1 ] && [ -n "$UFW_ST" ]; then
  NOTE="批次 ${RB}；ufw ${UFW_ST}；${FS} 无 Btrfs/LUKS(NA)"
  record 8 "回滚与安全" PASS "$NOTE"
else
  record 8 "回滚与安全" FAIL "批次=${RB:-0} rescue=$RESCUE_OK ufw=${UFW_ST:-?}"
fi

echo >&2
echo "════════ 汇总（口径：PASS/8）════════" | tee -a "$SUMMARY"
printf '  PASS %d | FAIL %d | NA %d | TOOL_MISSING %d\n' \
  "$P_PASS" "$P_FAIL" "$P_NA" "$P_MISS" | tee -a "$SUMMARY"
printf '  通过率 %d/8' "$P_PASS" | tee -a "$SUMMARY"
[ "$P_MISS" -gt 0 ] && printf '（另有 %d 步工具未交付，不得计入通过）' "$P_MISS" | tee -a "$SUMMARY"
printf '\n' | tee -a "$SUMMARY"

echo | tee -a "$SUMMARY"
printf '  %-4s %-20s %-14s %s\n' 步 检查项 状态 说明 | tee -a "$SUMMARY"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r no name st note <<<"$r"
  printf '  %-4s %-20s %-14s %s\n' "$no" "$name" "$st" "$note" | tee -a "$SUMMARY"
done

echo | tee -a "$SUMMARY"
log "原始输出: ${OUT_DIR#$PROJECT_ROOT/}/"
log "该目录即交付证据，请勿删除（归档时随 backup/ 一并保留）"

if [ $P_FAIL -gt 0 ]; then
  warn "有 $P_FAIL 步失败，禁止交付"
  exit 1
fi
if [ $P_MISS -gt 0 ]; then
  warn "无失败，但 $P_MISS 步因工具未交付无法判定；不可宣称 8 步全过"
  exit 0
fi
ok "8 步全部通过"
