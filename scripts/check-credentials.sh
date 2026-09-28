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

hits=0; warns=0
# 是否被 git 跟踪 —— 只有"会被复制/提交出去"的才算 FAIL，本地未跟踪的只算 WARN
tracked() {
  [ -e "$ROOT/.git" ] || return 1
  git -C "$ROOT" ls-files --error-unmatch "${1#$ROOT/}" >/dev/null 2>&1
}
for pat in "${PATTERNS[@]}"; do
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    f="${line%%:*}"; rest="${line#*:}"; n="${rest%%:*}"
    skip "$f" && continue
    val="${rest#*:}"
    red=$(printf '%s' "$val" | sed -E 's/([A-Za-z0-9_+\/-]{6})[A-Za-z0-9_+\/=-]{10,}/\1***REDACTED***/g' | cut -c1-110)
    if tracked "$f"; then
      printf "  🔴 %s:%s\n     %s\n" "${f#$ROOT/}" "$n" "$red"
      hits=$((hits+1))
    else
      printf "  🟡 %s:%s  [本地未跟踪，不会同步出去]\n     %s\n" "${f#$ROOT/}" "$n" "$red"
      warns=$((warns+1))
    fi
  done < <(grep -rInaE --exclude-dir=.git --exclude-dir=node_modules "$pat" "$ROOT" 2>/dev/null || true)
done

if [ "$hits" -gt 0 ]; then
  echo "CRED=FAIL tracked_hits=$hits warning=$warns  ← ★这些是【会被提交/同步出去】的明文凭据"
  [ "$QUIET" = "--quiet" ] || echo "     处置：① 去服务商后台轮换(revoke)  ② 文件里改成占位符或 gitignore 移出版本控制  ③ 轮换完才算修复"
  exit 1
fi

# ★ 即使文件里已清干净，历史里的凭据仍需轮换 —— 只要这份清单在，就持续提示
PEND="$(cd "$(dirname "$0")/.." && pwd)/SECURITY-PENDING.md"
if [ -f "$PEND" ] && grep -q "^- \[x\] 全部" "$PEND" 2>/dev/null; then
  :
elif [ -f "$PEND" ]; then
  pending=$(grep -c "^| [0-9]" "$PEND" 2>/dev/null)
  echo "CRED=OK 无「会被同步出去」的明文凭据（本地未跟踪的 ${warns:-0} 处已忽略）"
  echo "⚠ 但 SECURITY-PENDING.md 记着 ${pending:-?} 项【待轮换】凭据 —— 它们仍在 git 历史里。"
  echo "   → 只有去服务商后台吊销才算修复（另有 --quiet 时本行不显示）"
  [ "$QUIET" = "--quiet" ] && exit 0
  exit 0
else
  echo "CRED=OK 无「会被同步出去」的明文凭据（本地未跟踪的 ${warns:-0} 处已忽略）"
fi
exit 0
