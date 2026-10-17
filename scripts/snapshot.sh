#!/usr/bin/env bash
# 打快照：给共享层一个"已知良好"的锚点，之后可回滚到它。
# 内容三重锚定：① git 轻量 tag  ② 逐文件 git blob 哈希清单  ③ 各机活副本 HEAD（尽力）
# 用法: bash snapshot.sh <vault> [--name NAME]
set -u
V="${1:-}"; shift 1 2>/dev/null || true
NAME=""
while [ $# -gt 0 ]; do case "$1" in --name) NAME="$2"; shift 2;; *) shift;; esac; done
[ -n "$V" ] || { echo "用法: snapshot.sh <vault> [--name NAME]"; exit 2; }
[ -d "$V/.git" ] || { echo "SNAP=FAIL reason=not-a-git-repo path=$V"; exit 2; }
[ -z "$NAME" ] && NAME="snap-$(date +%Y%m%d-%H%M%S)"
cd "$V" || exit 2
HERE="$(cd "$(dirname "$0")" && pwd)"

dirty=$(git status --porcelain | wc -l | tr -d ' ')
[ "$dirty" -gt 0 ] && echo "  ⚠ 工作区有 $dirty 处未提交改动 —— 快照只锚定已提交内容"

HEAD_SHA=$(git rev-parse HEAD)
SNAPDIR="$V/memory/_snapshots"; mkdir -p "$SNAPDIR"
MAN="$SNAPDIR/$NAME.json"

# 逐文件 blob 哈希（用 git hash-object —— 与 git 同源、无外部依赖）
{
  printf '{\n  "name": "%s",\n  "created": "%s",\n  "head": "%s",\n  "branch": "%s",\n  "files": {\n' \
    "$NAME" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$HEAD_SHA" "$(git rev-parse --abbrev-ref HEAD)"
  first=1
  git ls-files | grep -v '^memory/_snapshots/' | while IFS= read -r f; do
    [ -f "$f" ] || continue
    h=$(git hash-object "$f" 2>/dev/null) || continue
    if [ "$first" = 1 ]; then first=0; else printf ',\n'; fi
    printf '    "%s": "%s"' "$f" "$h"
  done
  printf '\n  }\n}\n'
} > "$MAN"

# 打 tag（轻量，作锚点）
git tag -f "$NAME" "$HEAD_SHA" >/dev/null 2>&1 && TAGGED=yes || TAGGED=no

n=$(git ls-files | grep -vc '^memory/_snapshots/')
echo "SNAP=OK name=$NAME head=$(echo "$HEAD_SHA" | cut -c1-7) tag=$TAGGED files=$n manifest=$MAN"
echo "  → 回滚: bash rollback.sh \"$V\" --check $NAME   /   --apply $NAME"

# 顺手记一下各机活副本 HEAD（尽力，失败不影响）
if [ -x "$HERE/verify-live.sh" ]; then
  out=$(timeout 90 bash "$HERE/verify-live.sh" 2>/dev/null | grep -E "^(  [^ ]|MIRROR_TIP)" | head -8)
  [ -n "$out" ] && { echo "  各机活副本:"; echo "$out" | sed 's/^/  /'; }
fi

# 把清单提交进去（这样快照本身也会被同步到各机）
git add "$MAN" 2>/dev/null
if ! git diff --cached --quiet 2>/dev/null; then
  git -c user.name="shared-layer" -c user.email="shared-layer@myainet" \
      commit -q -m "snapshot: $NAME (head $(echo "$HEAD_SHA" | cut -c1-7))" 2>/dev/null \
    && echo "  清单已提交（会随同步分发到各机）"
fi
