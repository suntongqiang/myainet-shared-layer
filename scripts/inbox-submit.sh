#!/usr/bin/env bash
# 无冲突写入通道：每个 agent 只写自己的 <agent>-<时间戳>.md
# 用法: bash inbox-submit.sh /path/to/vault "内容" --agent my-machine [--kind finding] [--scope 项目:X] [--tags a,b] [--confidence high]
set -u
V="${1:-}"; TEXT="${2:-}"; shift 2 2>/dev/null || true
AGENT="unknown"; KIND="finding"; SCOPE="全局"; TAGS=""; CONF="medium"
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2;;
    --kind) KIND="$2"; shift 2;;
    --scope) SCOPE="$2"; shift 2;;
    --tags) TAGS="$2"; shift 2;;
    --confidence) CONF="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$V" ] && [ -n "$TEXT" ] || { echo "用法: inbox-submit.sh <vault> \"内容\" --agent <名> [--kind K] [--scope S] [--tags a,b]"; exit 2; }
[ -d "$V" ] || { echo "INBOX=FAIL reason=vault-missing"; exit 2; }
IN="$V/memory/inbox"; mkdir -p "$IN"
TS=$(date +%Y%m%d-%H%M%S)
SAFE=$(printf '%s' "$AGENT" | tr -c 'A-Za-z0-9._-' '-')
F="$IN/${SAFE}-${TS}.md"
{
  echo "---"
  echo "kind: $KIND"
  echo "owner: $AGENT"
  echo "scope: $SCOPE"
  echo "tags: [${TAGS}]"
  echo "confidence: $CONF"
  echo "created: $(date +%Y-%m-%dT%H:%M:%S%z)"
  echo "status: inbox"
  echo "---"
  echo "## 内容"
  echo "$TEXT"
} > "$F"
echo "INBOX=OK file=$F"
