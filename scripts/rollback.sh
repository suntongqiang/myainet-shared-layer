#!/usr/bin/env bash
# 回滚到某个快照。
# ★ 设计取舍：**默认 revert 型回滚**（前向提交，内容回到快照，但历史只增不减）
#   —— 因为多机共享层里 reset --hard 会让其他机器分叉，是最容易造成二次事故的做法。
#   --hard 仅在"历史本身坏了"时才用，且会明确警告。
# 用法:
#   bash rollback.sh <vault> --list
#   bash rollback.sh <vault> --check <name>
#   bash rollback.sh <vault> --apply <name> [--yes]
#   bash rollback.sh <vault> --hard  <name> --yes      # 危险：reset --hard
set -u
V="${1:-}"; shift 1 2>/dev/null || true
MODE=""; NAME=""; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) MODE=list; shift;;
    --check) MODE=check; NAME="$2"; shift 2;;
    --apply) MODE=apply; NAME="$2"; shift 2;;
    --hard)  MODE=hard;  NAME="$2"; shift 2;;
    --yes)   YES=1; shift;;
    *) shift;;
  esac
done
[ -n "$V" ] || { echo "用法: rollback.sh <vault> --list|--check N|--apply N|--hard N [--yes]"; exit 2; }
[ -d "$V/.git" ] || { echo "ROLLBACK=FAIL reason=not-a-git-repo"; exit 2; }
cd "$V" || exit 2
SNAPDIR="$V/memory/_snapshots"

if [ "$MODE" = list ]; then
  echo "== 快照清单 =="
  if [ -d "$SNAPDIR" ]; then
    for f in "$SNAPDIR"/*.json; do
      [ -e "$f" ] || continue
      nm=$(basename "$f" .json)
      hd=$(grep -m1 '"head"' "$f" | sed 's/.*: *"//;s/".*//')
      cr=$(grep -m1 '"created"' "$f" | sed 's/.*: *"//;s/".*//')
      nf=$(grep -c '"' "$f")
      printf "  %-26s head=%-9s created=%s\n" "$nm" "$(echo "$hd" | cut -c1-7)" "$cr"
    done
  else echo "  (无快照)"; fi
  echo "  git tag: $(git tag | wc -l | tr -d ' ') 个"
  exit 0
fi

[ -n "$NAME" ] || { echo "ROLLBACK=FAIL reason=missing-snapshot-name"; exit 2; }
MAN="$SNAPDIR/$NAME.json"
[ -f "$MAN" ] || { echo "ROLLBACK=FAIL reason=no-such-snapshot name=$NAME"; exit 2; }
SNAP_HEAD=$(grep -m1 '"head"' "$MAN" | sed 's/.*: *"//;s/".*//')
echo "  快照 $NAME  head=$(echo "$SNAP_HEAD" | cut -c1-7)"

if [ "$MODE" = check ]; then
  echo "== 与当前状态的内容差异（逐文件 blob 哈希）=="
  PYF=$(mktemp)
  cat > "$PYF" <<'PYEOF'
import sys, json, subprocess, os
man = json.load(open(sys.argv[1], encoding="utf-8"))
files = man.get("files", {})
changed, missing, added = [], [], []
for p, h in files.items():
    if not os.path.exists(p):
        missing.append(p); continue
    cur = subprocess.run(["git", "hash-object", p], capture_output=True, text=True).stdout.strip()
    if cur != h:
        changed.append(p)
tracked = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split()
for p in tracked:
    if p not in files and not p.startswith("memory/_snapshots/"):
        added.append(p)
print("  改过:", len(changed))
for x in changed[:15]: print("    M", x)
print("  丢了:", len(missing))
for x in missing[:15]: print("    D", x)
print("  快照之后新增:", len(added))
for x in added[:15]: print("    A", x)
PYEOF
  ( cd "$V" && python3 "$PYF" "$MAN" 2>/dev/null ) || echo "  (内容比对需要 python3，已跳过)"
  rm -f "$PYF"
  echo "== 提交层面 =="
  echo "  快照之后共 $(git rev-list --count "$SNAP_HEAD"..HEAD 2>/dev/null) 个提交"
  git log --oneline "$SNAP_HEAD"..HEAD 2>/dev/null | head -8 | sed 's/^/    /'
  exit 0
fi

# ---------- apply / hard ----------
dirty=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$dirty" -gt 0 ] && [ "$YES" != 1 ]; then
  echo "  ⚠ 工作区有 $dirty 处未提交改动。先处理，或加 --yes 强制（会一并存入备份）"; exit 3
fi
if [ "$YES" != 1 ]; then
  echo "  即将回滚到 $NAME（head $(echo "$SNAP_HEAD" | cut -c1-7)）。加 --yes 确认执行。"; exit 0
fi

# ★ 回滚前先给"当前状态"也留一条后路
PRE="pre-rollback-$(date +%Y%m%d-%H%M%S)"
git tag -f "$PRE" HEAD >/dev/null 2>&1
BK="$V/.rollback-backup/$PRE"; mkdir -p "$BK"
# 未跟踪文件先备份（回滚会把它们清掉）
git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  mkdir -p "$BK/$(dirname "$f")"; cp -p "$f" "$BK/$f" 2>/dev/null || true
done
untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
echo "  已留后路: tag=$PRE  未跟踪文件备份=$untracked 个 → $BK"

if [ "$MODE" = hard ]; then
  echo "  🚨 --hard：将 reset --hard 到 $SNAP_HEAD —— 会改写本地历史！"
  echo "     多机环境下你随后必须 force push，否则各机会再次分叉（这是 FM-01 的另一种形态）。"
  git reset --hard "$SNAP_HEAD" 2>&1 | tail -1 | sed 's/^/    /'
else
  # 内容型回滚：工作区/index 恢复成快照内容，再前向提交一条
  git read-tree -m -u "$SNAP_HEAD" 2>/dev/null || { echo "    read-tree 失败，改用 checkout"; git checkout "$SNAP_HEAD" -- . 2>/dev/null; }
  git add -A 2>/dev/null
  git -c user.name="shared-layer" -c user.email="shared-layer@myainet" \
      commit -q -m "rollback: 回到快照 $NAME (head $(echo "$SNAP_HEAD" | cut -c1-7))" 2>/dev/null \
    && echo "    已生成前向回滚提交（历史只增不减，可 ff 同步到各机）"
fi

echo "  == 回滚后自检 =="
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -x "$HERE/check-integrity.sh" ] && bash "$HERE/check-integrity.sh" "$V" 2>&1 | tail -3 | sed 's/^/    /'
echo "ROLLBACK=OK to=$NAME  (如需撤销本次回滚: git tag 里有 $PRE，或直接对 $PRE 再跑一次 --apply)"
