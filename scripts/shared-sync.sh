#!/usr/bin/env bash
# myainet 共享层·多镜像同步（手机/主控版）
# 任一镜像机故障时自动换用其它镜像。用法: bash shared-sync.sh [仓库路径]
REPO="${1:-$HOME/.dsh/_shared}"
MIRRORS=(
  "Administrator@100.71.88.47:E:/myainet-shared-git.git"
  "Administrator@100.105.238.46:F:/myainet-shared-git.git"
  "Administrator@100.75.216.97:D:/myainet-shared-git.git"
)
cd "$REPO" 2>/dev/null || { echo "SYNC=FAIL reason=repo-missing path=$REPO"; exit 2; }
[ -d .git ] || { echo "SYNC=FAIL reason=not-a-repo path=$REPO"; exit 2; }

fetched=""
for m in "${MIRRORS[@]}"; do
  if timeout 90 git fetch --quiet "$m" master 2>/dev/null; then fetched="$m"; break; fi
done
[ -z "$fetched" ] && { echo "SYNC=FAIL reason=no-reachable-mirror"; exit 3; }

local=$(git rev-parse master 2>/dev/null)
remote=$(git rev-parse FETCH_HEAD 2>/dev/null)
if [ "$local" = "$remote" ]; then state=in-sync
else
  base=$(git merge-base master FETCH_HEAD 2>/dev/null)
  if [ "$base" = "$local" ]; then
    if git merge --ff-only FETCH_HEAD >/dev/null 2>&1; then state=ff-ok; else state=ff-BLOCKED; fi
  elif [ "$base" = "$remote" ]; then state=local-ahead
  else state=DIVERGED; fi
fi

ok=0; bad=""
for m in "${MIRRORS[@]}"; do
  if timeout 120 git push --quiet "$m" master 2>/dev/null; then ok=$((ok+1)); else bad="$bad ${m#Administrator@}"; fi
done
echo "SYNC=OK repo=$REPO fetch=${fetched#Administrator@} state=$state pushed_remote=$ok/${#MIRRORS[@]} head=$(git rev-parse --short master)${bad:+ failed=$bad}"
