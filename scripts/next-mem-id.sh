#!/usr/bin/env bash
# myainet 共享层·记忆编号分配器（治多机并发撞号）
# 取「所有可达镜像 + 本地」里出现过的最大 mem-NNNN，输出下一个空闲编号。
# ★建新条目之前必须先跑这个（见 memory/PROTOCOL.md §分配纪律）。
set -u
REPO="${1:-$HOME/.dsh/_shared}"
# 可用环境变量 SHARED_MIRRORS（空格分隔）或 ~/.shared-layer-mirrors（每行一个）覆盖
# shellcheck disable=SC2034
MIRRORS=(
  "Administrator@100.71.88.47:E:/myainet-shared-git.git"
  "Administrator@100.105.238.46:F:/myainet-shared-git.git"
  "Administrator@100.75.216.97:D:/myainet-shared-git.git"
)
cd "$REPO" 2>/dev/null || { echo "NEXT=FAIL reason=repo-missing"; exit 2; }
max=0
scan() {  # $1 = git ref
  git ls-tree -r --name-only "$1" memory/ 2>/dev/null \
    | grep -oE 'mem-[0-9]{4}\.md' | grep -oE '[0-9]{4}' | sort -n | tail -1
}
# 本地
l=$(git ls-tree -r --name-only HEAD memory/ 2>/dev/null | grep -oE 'mem-[0-9]{4}\.md' | grep -oE '[0-9]{4}' | sort -n | tail -1)
[ -n "$l" ] && lv=$((10#$l)) && [ "$lv" -gt "$max" ] && max=$lv
echo "  本地 HEAD 最大: ${l:-none}"
# 各镜像（fetch 到临时 ref）
i=0
for m in "${MIRRORS[@]}"; do
  i=$((i+1))
  if timeout 90 git fetch --quiet "$m" master:refs/probe/$i 2>/dev/null; then
    v=$(scan "refs/probe/$i")
    printf "  镜像%d %s 最大: %s\n" "$i" "${m##*@}" "${v:-none}"
    [ -n "$v" ] && vv=$((10#$v)) && [ "$vv" -gt "$max" ] && max=$vv
    git update-ref -d "refs/probe/$i" 2>/dev/null
  else
    printf "  镜像%d %s 不可达\n" "$i" "${m##*@}"
  fi
done
printf "NEXT=mem-%04d\n" $((max + 1))
