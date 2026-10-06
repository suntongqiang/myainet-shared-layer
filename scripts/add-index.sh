#!/usr/bin/env bash
# add-index.sh —— 安全地给 memory/INDEX.md 追加一行索引。
#
# ★为什么必须有这个脚本（FM-25 实例 B）：
#   用 `echo "... `反引号` ..." >> INDEX.md` 追加索引行时，**双引号里的反引号会被 shell
#   当命令替换执行**，把那段结论吃掉，而且【不报错、退出码 0】。
#   2026-09-30 记完 FM-25 之后 20 分钟内又犯了一次 —— 说明"写进纪律"没用，
#   必须让这条路走不通：索引行由本脚本**从文件内容生成**，shell 全程不解释正文。
#
# 用法：
#   add-index.sh mem-0251              # 生成并追加
#   add-index.sh mem-0251 --dry-run    # 只打印，不写
#   add-index.sh --check               # 只做第 8 项启发式体检
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
IDX="$ROOT/memory/INDEX.md"
MEMDIR="$ROOT/memory"

if [ "${1:-}" = "--check" ]; then
  n=0
  while IFS= read -r ln; do
    case "$ln" in
      "| mem-"*) if printf '%s' "$ln" | grep -q '  '; then
                   echo "可疑: $(printf '%s' "$ln" | cut -c1-90)"; n=$((n+1)); fi ;;
    esac
  done < "$IDX"
  echo "可疑行数=$n"; [ "$n" -eq 0 ]
  exit $?
fi

MID="${1:?用法: add-index.sh mem-0251 [--dry-run]}"
DRY="${2:-}"
MEM="$MEMDIR/$MID.md"
[ -f "$MEM" ] || { echo "找不到 $MEM" >&2; exit 2; }

LINE="$(python3 - "$MEM" "$MID" <<'PY'
import io, re, sys
path, mid = sys.argv[1], sys.argv[2]
txt = io.open(path, encoding="utf-8").read()

def fm(key):
    m = re.search(r'^%s:\s*(.+)$' % re.escape(key), txt, re.M)
    return (m.group(1).strip() if m else "")

kind = fm("kind") or "fact"
scope = fm("scope") or "全局"
upd = fm("updated") or fm("created")
date = (upd or "")[:10] or "-"

# 摘要在正文里：先看有没有带 ★ 的加粗句，否则取「## 内容」后的第一段非空正文
body = txt.split("---", 2)[-1]
summary = ""
for line in body.splitlines():
    s = line.strip()
    if not s or s.startswith("#") or s.startswith("|") or s.startswith("-"):
        continue
    summary = s
    break
if not summary:
    summary = "(无摘要)"
summary = re.sub(r'\s+', ' ', summary).replace("|", "/")[:220]
# 去掉行内 markdown 反引号/星号，避免索引行出现 nbsp 之类的怪异空白
summary = summary.replace("`", "").replace("**", "")
print("| %s | %s | %s | active | %s | %s |" % (mid, kind, scope, date, summary))
PY
)"

if [ "$DRY" = "--dry-run" ]; then echo "$LINE"; exit 0; fi
printf '%s\n' "$LINE" >> "$IDX"
echo "已追加："
echo "$LINE" | cut -c1-140
