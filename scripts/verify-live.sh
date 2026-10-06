#!/usr/bin/env bash
# myainet 共享层·活副本校验（治「能推不能拉」的隐形态断裂）
# 作用：逐节点查 _shared 的 HEAD 与 origin，与镜像 tip 对比，不一致就报警并非零退出。
# 用法：bash verify-live.sh                只校验
#       bash verify-live.sh --fix-origin   顺带把错过旧仓的 origin 改指新镜像
#
# ★ FM-29（自检盲区）：本机必须【本地直查】，绝不能走 ssh 回环。
#   原先本机也走 ssh → 一旦"自己 ssh 不上自己"（本机 ~/.ssh 里没有对方认的钥匙），
#   本机就被判 UNREACH 静默跳过 —— 而"唯一配置错误的那台"往往正是本机，
#   脚本还会打出 old_origin=0 的【假绿】。2026-10-07 在 yuzhangyuan 上真实踩到。
set -u

# 可用环境变量 SHARED_MIRRORS（空格分隔）或 ~/.shared-layer-mirrors（每行一个）覆盖
# shellcheck disable=SC2034
MIRRORS=(
  "Administrator@100.71.88.47:E:/myainet-shared-git.git"
  "Administrator@100.105.238.46:F:/myainet-shared-git.git"
  "Administrator@100.75.216.97:D:/myainet-shared-git.git"
)
if [ -n "${SHARED_MIRRORS:-}" ]; then read -r -a MIRRORS <<< "$SHARED_MIRRORS"; fi
if [ -f "$HOME/.shared-layer-mirrors" ]; then mapfile -t MIRRORS < <(grep -v "^#" "$HOME/.shared-layer-mirrors" | grep -v "^$"); fi

# 主机|名称|活副本路径|该机应指向的镜像
NODES=(
  "100.105.238.46|景德|G:/DSH/_shared|F:/myainet-shared-git.git"
  "100.71.88.47|sunyijia|C:/Users/Administrator/_shared|E:/myainet-shared-git.git"
  "100.124.113.89|cunchu|C:/Users/Administrator/_shared|Administrator@100.105.238.46:F:/myainet-shared-git.git"
  "100.75.216.97|yuzhangyuan|C:/Users/Administrator/.dsh/_shared|D:/myainet-shared-git.git"
)
K="${SSH_KEY:-$HOME/.ssh/id_dsh_mobile}"
SO="-i $K -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=12"
FIX=0; [ "${1:-}" = "--fix-origin" ] && FIX=1

# ★ python3 不一定在 PATH 上（Windows/Git-bash 常只有 `python`）——
#   原先写死 python3，缺了就会给每台远端都伪造出 UNREACH，看起来像"全网离线"。
PY=""
for _c in python3 python; do
  command -v "$_c" >/dev/null 2>&1 && { PY="$_c"; break; }
done
[ -z "$PY" ] && { echo "VERIFY=FAIL reason=no-python (base64 for -EncodedCommand)"; exit 3; }

TIP=""
for m in "${MIRRORS[@]}"; do
  TIP=$(timeout 60 git ls-remote "$m" refs/heads/master 2>/dev/null | cut -c1-7)
  [ -n "$TIP" ] && { TIPMIRROR="$m"; break; }
done
[ -z "$TIP" ] && { echo "VERIFY=FAIL reason=no-reachable-mirror"; exit 3; }
echo "MIRROR_TIP=$TIP  (from $TIPMIRROR)"
echo "本机 $(cd "$(dirname "$0")/../.." && git rev-parse --short HEAD 2>/dev/null)"

bad=0; off=0; nself=0
for spec in "${NODES[@]}"; do
  H="${spec%%|*}"; r="${spec#*|}"; NAME="${r%%|*}"; r="${r#*|}"
  DIR="${r%%|*}"; WANT="${r##*|}"

  if [ -d "$DIR/.git" ]; then
    # ── ★ 本机：本地直查（FM-29）。这里绝不允许出现 ssh。 ──
    nself=$((nself+1))
    hh=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)
    oo=$(git -C "$DIR" remote get-url origin 2>/dev/null)
    VIA="local"
  else
    PS="[Console]::OutputEncoding=[Text.Encoding]::UTF8
Set-Location '$DIR'
\$g = if (Get-Command git -ErrorAction SilentlyContinue) { 'git' } else { 'C:\\Program Files\\Git\\cmd\\git.exe' }
Write-Output ('H ' + ((& \$g rev-parse --short HEAD) -join ''))
Write-Output ('O ' + ((& \$g remote get-url origin) -join ''))"
    ENC=$(printf '%s' "$PS" | $PY -c "import sys,base64;print(base64.b64encode(sys.stdin.read().encode('utf-16-le')).decode())")
    out=$(timeout 90 ssh $SO Administrator@$H "powershell -NoProfile -NonInteractive -EncodedCommand $ENC" 2>/dev/null | tr -d '\000\r' | grep -aE "^[HO] ")
    hh=$(echo "$out" | grep -a '^H ' | awk '{print $2}')
    oo=$(echo "$out" | grep -a '^O ' | awk '{print $2}')
    VIA="ssh"
  fi

  if [ -z "$hh" ]; then
    printf "  %-11s %-10s %s\n" "$NAME" "UNREACH" "(离线或 ssh 失败)"; bad=$((bad+1)); continue
  fi
  st="OK"
  [ "$hh" != "$TIP" ] && { st="STALE"; bad=$((bad+1)); }
  case "$oo" in
    *myainet-shared-git.git) : ;;                                    # 新镜像 → OK
    *shared-git.git) st="$st+OLD-ORIGIN"; off=$((off+1)) ;;           # 旧单源仓 → 报警
  esac
  printf "  %-11s %-10s head=%s origin=%s [%s]\n" "$NAME" "$st" "$hh" "$oo" "$VIA"

  if [ "$FIX" = 1 ] && [ "$st" != "OK" ]; then
    if [ -d "$DIR/.git" ]; then
      git -C "$DIR" remote set-url origin "$WANT" 2>/dev/null
      git -C "$DIR" stash push -u -m "autofix-$(date +%Y%m%d-%H%M%S)" >/dev/null 2>&1
      git -C "$DIR" fetch origin --quiet >/dev/null 2>&1
      git -C "$DIR" pull --ff-only origin master 2>&1 | tail -1 | sed 's/^/      fix P /'
      echo "      fix H2 $(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)"
    else
      PS2="[Console]::OutputEncoding=[Text.Encoding]::UTF8
Set-Location '$DIR'
\$g = if (Get-Command git -ErrorAction SilentlyContinue) { 'git' } else { 'C:\\Program Files\\Git\\cmd\\git.exe' }
& \$g remote set-url origin '$WANT'
& \$g stash push -u -m ('autofix-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) 2>&1 | Out-Null
& \$g fetch origin --quiet 2>&1 | Out-Null
& \$g pull --ff-only origin master 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Output ('P ' + \$_) }
Write-Output ('H2 ' + ((& \$g rev-parse --short HEAD) -join ''))"
      ENC2=$(printf '%s' "$PS2" | $PY -c "import sys,base64;print(base64.b64encode(sys.stdin.read().encode('utf-16-le')).decode())")
      timeout 180 ssh $SO Administrator@$H "powershell -NoProfile -NonInteractive -EncodedCommand $ENC2" 2>/dev/null | tr -d '\000' | grep -aE "^H2 " | sed 's/^/      fix /'
    fi
  fi
done
echo "VERIFY=done stale_or_unreachable=$bad old_origin=$off self_checked_locally=$nself"
[ $bad -eq 0 ] && echo "ALL_LIVE_OK" || exit 1
