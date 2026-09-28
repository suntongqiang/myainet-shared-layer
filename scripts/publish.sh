#!/usr/bin/env bash
# 把共享层里的本技能同步成一个独立仓库（用于推送 GitHub）
# 用法: bash publish.sh <技能源目录> <目标仓库目录>
set -eu
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
DST="${2:-}"
[ -n "$DST" ] || { echo "用法: publish.sh <技能源目录> <目标仓库目录>"; exit 2; }
[ -f "$SRC/SKILL.md" ] || { echo "PUBLISH=FAIL reason=source-missing path=$SRC"; exit 2; }
mkdir -p "$DST"
# 只同步受版本控制的那些文件（排除 .git）
for f in README.md LICENSE SKILL.md docs scripts hooks; do
  [ -e "$SRC/$f" ] || continue
  if [ -d "$SRC/$f" ]; then
    mkdir -p "$DST/$f"; cp -Rf "$SRC/$f/." "$DST/$f/"
  else
    cp -f "$SRC/$f" "$DST/$f"
  fi
done
chmod +x "$DST"/scripts/*.sh "$DST"/hooks/pre-commit 2>/dev/null || true
echo "PUBLISH=COPIED src=$SRC dst=$DST files=$(find "$DST" -type f -not -path '*/.git/*' | wc -l)"
if [ -d "$DST/.git" ]; then
  git -C "$DST" add -A
  if git -C "$DST" diff --cached --quiet; then echo "PUBLISH=NOCHANGE"; else
    git -C "$DST" commit -q -m "sync from shared layer $(date +%Y-%m-%d)" && echo "PUBLISH=COMMITTED $(git -C "$DST" rev-parse --short HEAD)"
  fi
fi
