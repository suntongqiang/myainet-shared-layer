#!/usr/bin/env bash
# 凭据泄露扫描：共享层/技能库里不许有明文凭据。
# ★ 事故来源：2026-09-28 在 skills/e-card-namecard/editor.html 里发现一枚明文 GitHub Token
#   （repo 全权），随共享层同步到 5 台机器，并且在 git 历史里躺了 19 天。
# 用法: bash check-credentials.sh <目录> [--quiet]
# 退出码: 0=干净  1=发现凭据
set -u
ROOT="${1:-$HOME/.dsh/_shared}"
QUIET="${2:-}"
[ -d "$ROOT" ] || { echo "CRED=FAIL reason=path-missing path=$ROOT"; exit 2; }

# 可忽略清单：每行一个 glob（相对 ROOT），# 开头是注释
IGN="$ROOT/.credignore"
declare -a IGN_PAT=()
[ -f "$IGN" ] && while IFS= read -r l; do
  case "$l" in ''|\#*) ;; *) IGN_PAT+=("$l");; esac
done < "$IGN"

# ★ 默认忽略本脚本自身与文档中"描述模式"的位置（否则自己扫自己）
IGN_PAT+=("scripts/check-credentials.sh" "*/check-credentials.sh" "docs/FAILURE-MODES.md")

# 模式：只放"几乎不可能是正常文本"的形态
PATTERNS=(
  'gh[pousr]_[A-Za-z0-9]{30,}'
  'github_pat_[A-Za-z0-9_]{30,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'sk-[A-Za-z0-9]{32,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '[Aa][Pp][Ii][_-]?[Kk][Ee][Yy][^A-Za-z0-9]{1,4}[A-Za-z0-9/+_-]{24,}'
)

skip() {  # $1 = 绝对路径
  local rel="${1#$ROOT/}"
  for p in "${IGN_PAT[@]}"; do
    case "$rel" in $p) return 0;; esac
  done
  return 1
}

hits=0
for pat in "${PATTERNS[@]}"; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    f="${line%%:*}"; rest="${line#*:}"; n="${rest%%:*}"
    skip "$f" && continue
    val="${rest#*:}"
    red=$(printf '%s' "$val" | sed -E 's/([A-Za-z0-9_+\/-]{6})[A-Za-z0-9_+\/=-]{10,}/\1***REDACTED***/g' | cut -c1-110)
    printf "  🔴 %s:%s\n     %s\n" "${f#$ROOT/}" "$n" "$red"
    hits=$((hits+1))
  done < <(grep -rInaE --exclude-dir=.git --exclude-dir=node_modules "$pat" "$ROOT" 2>/dev/null || true)
done

if [ "$hits" -gt 0 ]; then
  echo "CRED=FAIL hits=$hits  ← 明文凭据；请立即轮换(revoke)该凭据，不要只删文件（git 历史里仍有）"
  [ "$QUIET" = "--quiet" ] || echo "     处置：① 去服务商后台轮换/吊销  ② 从文件里改成占位符  ③ 需要的话把该路径加进 .credignore"
  exit 1
fi
echo "CRED=OK 无明文凭据"
exit 0
