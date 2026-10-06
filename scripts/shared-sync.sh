#!/usr/bin/env bash
# myainet 共享层·多镜像同步（手机/主控版）
# 任一镜像机故障时自动换用其它镜像。用法: bash shared-sync.sh [仓库路径]
#
# ★ 2026-10-07 两处修正：
#   1) 本机自己那份 bare 若就在本地盘上，直接用本地路径推 —— 不走 ssh 回环（FM-29；
#      原先 ssh 不上自己 → 恒失败，而 .ps1 版早有 $LOCAL_BARES 处理，.sh 版漏了）
#   2) 退出码必须反映状态 —— 否则计划任务 LastTaskResult 恒为 0，故障静默（FM-22）
#      背景：2026-10-07 本脚本连续输出 state=DIVERGED pushed_remote=0/3 却 exit 0，
#      控制台看起来一切健康，两条分叉线一直没被发现。
set -u
REPO="${1:-$HOME/.dsh/_shared}"
MIRRORS=(
  "Administrator@100.71.88.47:E:/myainet-shared-git.git"
  "Administrator@100.105.238.46:F:/myainet-shared-git.git"
  "Administrator@100.75.216.97:D:/myainet-shared-git.git"
)

# "user@host:path" → 该 path 在本地存在就用本地路径（本机自己的镜像），否则保留远端写法
resolve_mirror() {
  local m="$1" p="${1#*:}"
  if [ -d "$p" ]; then printf '%s' "$p"; else printf '%s' "$m"; fi
}
TARGETS=()
for m in "${MIRRORS[@]}"; do TARGETS+=("$(resolve_mirror "$m")"); done

cd "$REPO" 2>/dev/null || { echo "SYNC=FAIL reason=repo-missing path=$REPO"; exit 2; }
[ -d .git ] || { echo "SYNC=FAIL reason=not-a-repo path=$REPO"; exit 2; }

# ★ 自检 origin：origin 指错仓时 fetch/push 都可能"成功"，只有这条能提前暴露（FM-01）
ORIGIN_BAD=0
origin=$(git remote get-url origin 2>/dev/null || echo "")
case "$origin" in
  ""|*myainet-shared-git.git) : ;;
  *) echo "SYNC=WARN reason=origin-points-at-non-fleet-repo origin=$origin hint='bash verify-live.sh --fix-origin'"
     ORIGIN_BAD=1 ;;
esac

fetched=""
for m in "${TARGETS[@]}"; do
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
for m in "${TARGETS[@]}"; do
  if timeout 120 git push --quiet "$m" master 2>/dev/null; then ok=$((ok+1)); else bad="$bad ${m#Administrator@}"; fi
done
echo "SYNC=OK repo=$REPO fetch=${fetched#Administrator@} state=$state pushed_remote=$ok/${#TARGETS[@]} head=$(git rev-parse --short master)${bad:+ failed=$bad}"

# ★ 退出码（FM-22）：分叉 / ff 被挡 / 一台都没推成 / origin 指错 → 非零，让计划任务能报出来
rc=0
case "$state" in DIVERGED|ff-BLOCKED) rc=1 ;; esac
if [ "$ok" -eq 0 ]; then rc=2
elif [ "$ok" -lt "${#TARGETS[@]}" ]; then rc=1
fi
[ "$ORIGIN_BAD" = 1 ] && rc=1
if [ "$rc" -ne 0 ]; then
  echo "SYNC=WARN state=$state pushed=$ok/${#TARGETS[@]}${bad:+ failed:$bad} origin_bad=$ORIGIN_BAD"
fi
exit $rc
