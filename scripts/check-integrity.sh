#!/usr/bin/env bash
# 共享层·完整性体检：重复 id / 文件名与 id 不一致 / 残留冲突标记 / INDEX 一致性
# 用法: bash check-integrity.sh /path/to/vault
set -u
V="${1:-$HOME/.dsh/_shared}"
[ -d "$V" ] || { echo "INTEGRITY=FAIL reason=vault-missing path=$V"; exit 2; }
MEM="$V/memory"; IDX="$MEM/INDEX.md"
bad=0

echo "== 1) 重复 id（按 frontmatter 的 id: 字段）=="
if [ -d "$MEM" ]; then
  dup=$(grep -h --include='mem-*.md' -E '^id:[[:space:]]*mem-[0-9]{4}' "$MEM" 2>/dev/null \
        | sed -E 's/^id:[[:space:]]*//' | sort | uniq -d)
  if [ -n "$dup" ]; then echo "$dup" | sed 's/^/  DUP /'; bad=$((bad+1)); echo "  → 重复 id 数: $(echo "$dup" | wc -l)"; else echo "  OK 无重复"; fi
else echo "  SKIP 无 memory/"; fi

echo "== 2) 文件名与 id 是否一致 =="
n=0
for f in "$MEM"/mem-*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)
  fid=$(grep -m1 -E '^id:' "$f" 2>/dev/null | sed -E 's/^id:[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$fid" ] && [ "$fid" != "$base" ] && { echo "  MISMATCH $base vs id=$fid"; n=$((n+1)); }
done
[ "$n" -eq 0 ] && echo "  OK 全部一致" || bad=$((bad+1))

echo "== 3) 残留 git 冲突标记 =="
cm=$(grep -rl --include='*.md' -E '^(<<<<<<<|>>>>>>>) ' "$V" 2>/dev/null | grep -v '/.git/' || true)
if [ -n "$cm" ]; then echo "$cm" | sed 's/^/  CONFLICT /'; bad=$((bad+1)); else echo "  OK 无残留"; fi

echo "== 4) INDEX 与 memory/ 是否对齐 =="
if [ -f "$IDX" ]; then
  # INDEX 用裸编号（mem-0112），目录用文件名（mem-0112.md）—— 统一收敛成裸编号再比
  a=$(grep -oE 'mem-[0-9]{4}' "$IDX" 2>/dev/null | sort -u)
  b=$(ls "$MEM" 2>/dev/null | grep -oE 'mem-[0-9]{4}' | sort -u)
  onlyidx=$(comm -23 <(echo "$a") <(echo "$b") | tr '\n' ' ')
  onlyfile=$(comm -13 <(echo "$a") <(echo "$b") | tr '\n' ' ')
  [ -n "$onlyidx" ] && { echo "  只在 INDEX 里: $onlyidx"; bad=$((bad+1)); }
  [ -n "$onlyfile" ] && { echo "  只在目录里: $onlyfile"; bad=$((bad+1)); }
  [ -n "$onlyidx$onlyfile" ] || echo "  OK 对齐（$(echo "$b" | grep -c .) 条）"
else echo "  SKIP 无 INDEX.md"; fi

echo "== 5) 编号空洞（仅提示）=="
mx=$(ls "$MEM" 2>/dev/null | grep -oE 'mem-[0-9]{4}' | grep -oE '[0-9]{4}' | sort -n | tail -1)
echo "  最大编号 mem-${mx:-none}"
echo "INTEGRITY=$( [ $bad -eq 0 ] && echo PASS || echo FAIL ) issues=$bad"
[ $bad -eq 0 ] || exit 1
