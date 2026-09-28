#!/usr/bin/env bash
# 中心化晋升：唯一的 promoter 把 inbox 里的条目分配正式编号并落库
# 用法: bash promote-inbox.sh /path/to/vault --review | --apply [--keep-inbox]
set -u
V="${1:-}"; MODE="${2:-}"; KEEP="${3:-}"
[ -n "$V" ] || { echo "用法: promote-inbox.sh <vault> --review|--apply"; exit 2; }
IN="$V/memory/inbox"; MEM="$V/memory"; IDX="$MEM/INDEX.md"
[ -d "$IN" ] || { echo "PROMOTE=OK nothing-to-do (no inbox)"; exit 0; }
n=$(ls "$IN"/*.md 2>/dev/null | wc -l)
[ "$n" -gt 0 ] || { echo "PROMOTE=OK nothing-to-do (empty inbox)"; exit 0; }

if [ "$MODE" = "--review" ]; then
  echo "== 待晋升 $n 条 =="
  for f in "$IN"/*.md; do
    head -1 "$f" >/dev/null 2>&1
    t=$(grep -m1 '^## 内容' -A1 "$f" | tail -1 | cut -c1-80)
    o=$(grep -m1 '^owner:' "$f" | sed 's/^owner:[[:space:]]*//')
    s=$(grep -m1 '^scope:' "$f" | sed 's/^scope:[[:space:]]*//')
    printf "  %-40s owner=%-14s scope=%s\n     %s\n" "$(basename "$f")" "$o" "$s" "$t"
  done
  echo "PROMOTE=REVIEW n=$n  （确认后跑 --apply）"
  exit 0
fi

[ "$MODE" = "--apply" ] || { echo "用法: promote-inbox.sh <vault> --review|--apply"; exit 2; }

# 下一个空闲编号：跨所有可达镜像 + 本地
HERE="$(cd "$(dirname "$0")" && pwd)"
NEXT=$(bash "$HERE/next-mem-id.sh" "$V" 2>/dev/null | grep -oE 'mem-[0-9]{4}' | tail -1)
[ -n "$NEXT" ] || { echo "PROMOTE=FAIL reason=cannot-allocate-id"; exit 3; }
num=$((10#${NEXT#mem-}))
mkdir -p "$MEM"
applied=0
for f in "$IN"/*.md; do
  [ -e "$f" ] || continue
  id=$(printf 'mem-%04d' "$num")
  dst="$MEM/$id.md"
  owner=$(grep -m1 '^owner:' "$f" | sed 's/^owner:[[:space:]]*//')
  scope=$(grep -m1 '^scope:' "$f" | sed 's/^scope:[[:space:]]*//')
  kind=$(grep -m1 '^kind:' "$f" | sed 's/^kind:[[:space:]]*//')
  tags=$(grep -m1 '^tags:' "$f" | sed 's/^tags:[[:space:]]*//')
  conf=$(grep -m1 '^confidence:' "$f" | sed 's/^confidence:[[:space:]]*//')
  body=$(awk '/^## 内容/{flag=1;next} flag' "$f")
  {
    echo "---"
    echo "id: $id"
    echo "created: $(date +%Y-%m-%d)"
    echo "updated: $(date +%Y-%m-%dT%H:%M:%S%z)"
    echo "kind: ${kind:-finding}"
    echo "owner: ${owner:-unknown}"
    echo "scope: ${scope:-全局}"
    echo "tags: ${tags:-[]}"
    echo "status: active"
    echo "confidence: ${conf:-medium}"
    echo "supersedes: []"
    echo "superseded_by:"
    echo "---"
    echo "## 内容"
    echo "$body"
  } > "$dst"
  # INDEX 追加一行
  if [ -f "$IDX" ]; then
    short=$(echo "$body" | tr '\n' ' ' | cut -c1-160)
    printf '| %s | %s | %s | active | %s | %s |\n' "$id" "${kind:-finding}" "${scope:-全局}" "$(date +%Y-%m-%d)" "$short" >> "$IDX"
  fi
  [ "$KEEP" = "--keep-inbox" ] || rm -f "$f"
  echo "  PROMOTED $id  <- $(basename "$f")"
  num=$((num+1)); applied=$((applied+1))
done
echo "PROMOTE=OK applied=$applied next=$(printf 'mem-%04d' "$num")"
