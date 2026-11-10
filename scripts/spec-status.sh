#!/usr/bin/env bash
# spec-status.sh — 汇总 spec 看板状态（只读）
set -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$ROOT/spec/04-tasks.md"
[ -f "$T" ] || { echo "缺少 $T"; exit 1; }

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
