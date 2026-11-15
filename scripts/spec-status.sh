#!/usr/bin/env bash
# spec-status.sh — 汇总 spec 看板状态（只读）
set -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$ROOT/spec/04-tasks.md"
[ -f "$T" ] || { echo "缺少 $T"; exit 1; }

# ---- --facts：数字的单一来源 ------------------------------------------------
# 文档里不许再手写「62 项 / 30 个脚本」这类数字，一律引用本命令输出。
if [ "${1:-}" = "--facts" ]; then
  TSV=0
  [ "${2:-}" = "--tsv" ] && TSV=1

  VOUT="$(bash "$ROOT/scripts/99-verify.sh" 2>/dev/null | tail -3)"
  V_PASS="$(printf '%s' "$VOUT" | sed -n 's/.*通过 [^0-9]*\([0-9]*\).*/\1/p' | tail -1)"
  V_FAIL="$(printf '%s' "$VOUT" | sed -n 's/.*失败 [^0-9]*\([0-9]*\).*/\1/p' | tail -1)"
  V_TOTAL=$(( ${V_PASS:-0} + ${V_FAIL:-0} ))

  POUT="$(bash "$ROOT/scripts/preboot-check.sh" 2>/dev/null | grep -E '通过 [0-9]+' | tail -1)"
  P_PASS="$(printf '%s' "$POUT" | sed -n 's/.*通过 [^0-9]*\([0-9]*\).*/\1/p')"
  P_WARN="$(printf '%s' "$POUT" | sed -n 's/.*警告 [^0-9]*\([0-9]*\).*/\1/p')"
  P_FAIL="$(printf '%s' "$POUT" | sed -n 's/.*失败 [^0-9]*\([0-9]*\).*/\1/p')"

  S_SCRIPTS="$(find "$ROOT/scripts" -maxdepth 1 -name '*.sh' | wc -l)"
  S_DOCS="$(find "$ROOT/docs" -maxdepth 1 -name '*.md' | wc -l)"
  S_TASKS="$(grep -cE '^\| TASK-' "$T" 2>/dev/null || echo 0)"
  S_TASK_DONE="$(grep -c '| done |' "$T" 2>/dev/null || echo 0)"
  S_STEP="$(ls -dt "$ROOT"/logs/step-verify-* 2>/dev/null | head -1)"

  if [ "$TSV" -eq 1 ]; then
    printf 'verify_total\t%s\n' "${V_TOTAL:-0}"
    printf 'verify_pass\t%s\n' "${V_PASS:-0}"
    printf 'verify_fail\t%s\n' "${V_FAIL:-0}"
    printf 'preboot_pass\t%s\n' "${P_PASS:-0}"
    printf 'preboot_warn\t%s\n' "${P_WARN:-0}"
    printf 'preboot_fail\t%s\n' "${P_FAIL:-0}"
    printf 'scripts\t%s\n' "$S_SCRIPTS"
    printf 'docs\t%s\n' "$S_DOCS"
    printf 'tasks\t%s\n' "$S_TASKS"
    printf 'tasks_done\t%s\n' "$S_TASK_DONE"
    exit 0
  fi

  echo "===== 事实数字（$(date '+%F %T')）====="
  printf '  体检         : %s 项（通过 %s / 失败 %s）\n' "${V_TOTAL:-?}" "${V_PASS:-?}" "${V_FAIL:-?}"
  printf '  重启前体检   : 通过 %s / 警告 %s / 失败 %s\n' "${P_PASS:-?}" "${P_WARN:-?}" "${P_FAIL:-?}"
  printf '  脚本         : %s 个（scripts/*.sh）\n' "$S_SCRIPTS"
  printf '  文档         : %s 篇（docs/*.md）\n' "$S_DOCS"
  printf '  任务         : %s 条（done %s）\n' "$S_TASKS" "$S_TASK_DONE"
  printf '  最近 8 步    : %s\n' "${S_STEP:-无记录}"
  echo
  echo "  文档引用方式: \`./scripts/spec-status.sh --facts\`（不要手写数字）"
  exit 0
fi

echo "===== Spec 状态汇总 ($(date '+%F %T')) ====="
echo; echo '-- 任务状态 --'
for s in done in_progress planned blocked reverted cancelled deferred; do
  n=$(grep -c "| $s |" "$T" 2>/dev/null || true)
  : "${n:=0}"
  printf '  %-14s %s\n' "$s" "$n"
done
echo; echo '-- 进行中 / 阻塞 --'
grep -E '\| (in_progress|blocked) \|' "$T" | sed 's/^/  /'
echo; echo '-- 里程碑 --'
grep -E '^\| M[0-9]' "$ROOT/spec/03-plan.md" | sed 's/^/  /'
echo; echo '-- 未关闭问题 --'
grep -E '\| (open|investigating|in_progress) \|' "$ROOT/spec/06-issues.md" | sed 's/^/  /'
echo; echo '-- 产品级里程碑（SuonaOS 立项计划） --'
P="$ROOT/spec/suonaos/03-plan.md"
if [ -f "$P" ]; then
  grep -E '^\| SM-[0-9]' "$P" | sed 's/^/  /'
else
  echo '  (未建立)'
fi

echo; echo '-- 产品级待裁决项 --'
D="$ROOT/spec/suonaos/03-plan.md"
[ -f "$D" ] && grep -E '^\| \*\*SDEC-' "$D" | sed 's/^/  /'

echo; echo '-- 文件完整性 --'
for f in README 00-upstream 01-charter 02-requirements 03-plan 04-tasks 05-progress 06-issues 07-decisions; do
  [ -f "$ROOT/spec/$f.md" ] && printf '  OK  %s\n' "$f.md" || printf '  --  %s.md 缺失\n' "$f"
done
for f in README 01-product-spec 02-technical-spec 03-plan 04-tasks 05-acceptance-risks 06-milestone-audit; do
  [ -f "$ROOT/spec/suonaos/$f.md" ] && printf '  OK  suonaos/%s\n' "$f.md" || printf '  --  suonaos/%s.md 缺失\n' "$f"
done

echo; echo '-- 已填写的核验副本 --'
AUDITS=$(ls -1 "$ROOT"/spec/suonaos/06-milestone-audit-20*.md 2>/dev/null)
if [ -n "$AUDITS" ]; then
  echo "$AUDITS" | sed 's/^/  /'
else
  echo '  （尚无，S-10 / S-11 待核验）'
fi
