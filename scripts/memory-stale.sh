#!/usr/bin/env bash
# 记忆衰减候选（可逆归档，永不删除）
# 判据（诚实版，我们还没有"访问计数"，所以用代理指标）：
#   status:active  +  updated 超过 --days 天  +  confidence 非 high  +  没有任何其它文件引用它的 id
# 用法: bash memory-stale.sh <vault> [--days 60] [--apply]
set -u
V="${1:-}"; shift 1 2>/dev/null || true
DAYS=60; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2;;
    --apply) APPLY=1; shift;;
    *) shift;;
  esac
done
[ -n "$V" ] || { echo "用法: memory-stale.sh <vault> [--days 60] [--apply]"; exit 2; }
MEM="$V/memory"; ARC="$MEM/_archive"
[ -d "$MEM" ] || { echo "STALE=FAIL reason=no-memory-dir"; exit 2; }

today=$(date +%s); cand=0
for f in "$MEM"/mem-*.md; do
  [ -e "$f" ] || continue
  st=$(grep -m1 '^status:' "$f" | sed 's/^status: *//')
  [ "$st" = "active" ] || continue
  cf=$(grep -m1 '^confidence:' "$f" | sed 's/^confidence: *//')
  [ "$cf" = "high" ] && continue
  up=$(grep -m1 '^updated:' "$f" | sed -E 's/^updated: *//' | cut -c1-10)
  [ -n "$up" ] || continue
  up_s=$(date -d "$up" +%s 2>/dev/null) || continue
  age=$(( (today - up_s) / 86400 ))
  [ "$age" -ge "$DAYS" ] || continue
  id=$(grep -m1 '^id:' "$f" | sed 's/^id: *//')
  base=$(basename "$f" .md)
  # 引用计数：别的文件里提到这个 id 的次数（排除自己与 INDEX）
  refs=$(grep -rl --include='*.md' -- "$id" "$V" 2>/dev/null | grep -v "/.git/" | grep -v "$f" | grep -v "/INDEX.md" | wc -l)
  [ "$refs" -gt 0 ] && continue
  printf "  %-12s age=%4dd conf=%-6s refs=0  %s\n" "$base" "$age" "$cf" "$(grep -m1 -A2 '^## 内容' "$f" | tail -1 | tr -s ' ' | cut -c1-70)"
  cand=$((cand+1))
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$ARC"; mv "$f" "$ARC/$base.md" && echo "      → 已归档到 memory/_archive/$base.md（可逆，未删除）"
  fi
done
if [ "$APPLY" = 1 ]; then
  echo "STALE=OK candidates=$cand archived=$cand （可逆：文件在 memory/_archive/，随时可移回）"
else
  echo "STALE=REVIEW candidates=$cand  （确认后加 --apply 归档）"
fi
