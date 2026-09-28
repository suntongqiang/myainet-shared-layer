#!/usr/bin/env bash
# 给目标仓库装 pre-commit 守卫
# ★ 教训：装不上就必须报 FAIL —— 曾经这里 cp 失败却仍打印 HOOK=OK（假成功）。
set -u
V="${1:-$HOME/.dsh/_shared}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../hooks/pre-commit"

command -v git >/dev/null 2>&1 || { echo "HOOK=FAIL reason=git-not-found"; exit 2; }
[ -e "$V/.git" ] || { echo "HOOK=FAIL reason=not-a-git-repo path=$V"; exit 2; }
[ -f "$SRC" ]   || { echo "HOOK=FAIL reason=source-missing path=$SRC"; exit 2; }

# 尊重 core.hooksPath / worktree（用 git 自己算路径）
HOOKDIR="$(git -C "$V" rev-parse --git-path hooks 2>/dev/null || true)"
case "$HOOKDIR" in /*|?:/*) : ;; *) HOOKDIR="$V/$HOOKDIR" ;; esac
[ -n "$HOOKDIR" ] || HOOKDIR="$V/.git/hooks"

mkdir -p "$HOOKDIR" || { echo "HOOK=FAIL reason=mkdir-failed path=$HOOKDIR"; exit 3; }
cp -f "$SRC" "$HOOKDIR/pre-commit" || { echo "HOOK=FAIL reason=cp-failed path=$HOOKDIR"; exit 3; }
chmod +x "$HOOKDIR/pre-commit"    || { echo "HOOK=FAIL reason=chmod-failed"; exit 3; }

# ★ 装完必须验证，不能只信 cp 的退出码
if [ -x "$HOOKDIR/pre-commit" ]; then
  echo "HOOK=OK dir=$HOOKDIR size=$(wc -c < "$HOOKDIR/pre-commit")B"
else
  echo "HOOK=FAIL reason=verify-failed path=$HOOKDIR/pre-commit"; exit 4
fi
