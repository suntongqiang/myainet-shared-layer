#!/usr/bin/env bash
# myainet 机群校验 verify-fleet.sh —— 治「同一份东西在不同机器上悄悄不一样」
#
# 由来（2026-09-29 一口气踩出来的四个坑，全都属于同一个母题：
#   **没有任何机制在比对「不同机器上的同一份东西」**）：
#     1) INDEX 编号撞号（mem-0132/0133/0134 被同号覆盖 9 天）
#     2) cunchu .ssh/config 少了 Host 行 → 局部规则变全局规则
#     3) P1.1 的 ×1.07 只落在 sunyijia，景德（跑告警那台）仍是 ×1.06
#     4) aquant 在两台各自演化：22 个文件只在一台、4 个只在另一台、11 个同名不同内容
#   四个都是静默的：两边都"正常运行"，只是跑的不是同一份东西。
#
# 本脚本做三项校验：
#   (a) 代码仓一致 —— 各机量化仓 HEAD == 镜像尖端，且工作区干净、origin 指向本地镜像
#   (b) 调度拓扑唯一 —— 同名交易任务不能在两台以上同时「启用」（否则重复告警/重复下单）
#   (c) 缓存末日一致 —— 各机行情缓存的最后数据日一致（否则同一问题两台两个答案）
#
# ★重要：一律比对 **commit**，不比文件字节。
#   三台 Windows 的 core.autocrlf=true（检出 LF→CRLF），比字节必然误报。
#   2026-09-29 实测：git checkout 后 README.md 的 MD5 从 5246... 变成 3206... —— 比字节会得出错误结论。
#
# 用法： bash verify-fleet.sh
# 退出： 0=全绿   1=有问题   3=镜像不可达
set -u

MIRRORS=(
  "Administrator@100.71.88.47:E:/myainet-quant-git.git"
  "Administrator@100.105.238.46:F:/myainet-quant-git.git"
  "Administrator@100.124.113.89:F:/myainet-quant-git.git"
)
# 主机|名称|量化仓活副本路径|该机应指向的镜像
QNODES=(
  "100.105.238.46|景德|C:/Users/Administrator/金刚|F:/myainet-quant-git.git"
  "100.71.88.47|sunyijia|C:/Users/Administrator/金刚|E:/myainet-quant-git.git"
)
# 所有要参与「拓扑唯一性」扫描的机器（活副本机器 + 只读机器）
HNODES=(
  "100.105.238.46|景德"
  "100.71.88.47|sunyijia"
)
# 这些任务名是「同一套交易任务」，全局只能有一台启用
SINGLE_HOST_TASKS="aquant_monitor aquant_paper aquant_gate aquant_gate_live aquant_intraday_600487"
RUNTIME_NODE="景德"          # 唯一运行时（定时任务只在这台跑）——它的缓存陈旧才是硬故障
# 缓存末日参照标的（取持仓票，快且有意义）
REF_CODES="002078 603871 002746"

K="${SSH_KEY:-$HOME/.ssh/id_dsh_mobile}"
SO="-i $K -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=12"
[ -f "$K" ] || SO="-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=12"

b64ps() { printf '%s' "$1" | python3 -c "import sys,base64;print(base64.b64encode(sys.stdin.read().encode('utf-16-le')).decode())"; }
runps() { # host, powershell-source  -> stdout
  local h="$1" src="$2" enc
  enc=$(b64ps "$src")
  timeout 120 ssh $SO "Administrator@$h" "powershell -NoProfile -NonInteractive -EncodedCommand $enc" 2>/dev/null | tr -d '\000\r'
}
GITSHIM='$g = if (Get-Command git -ErrorAction SilentlyContinue) { "git" } else { "C:\Program Files\Git\cmd\git.exe" }'

bad=0; warned=0

# ★ 比 commit 不比字节：两边都取 8 位，避免 7 vs 8 误报
# ── (a) 代码仓一致 ──────────────────────────────────────────────────────────
TIP=""; TIPM=""
for m in "${MIRRORS[@]}"; do
  TIP=$(timeout 60 git ls-remote "$m" refs/heads/master 2>/dev/null | cut -c1-8)
  [ -n "$TIP" ] && { TIPM="$m"; break; }
done
if [ -z "$TIP" ]; then echo "VERIFY_FLEET=FAIL reason=no-reachable-mirror"; exit 3; fi
echo "QUANT_MIRROR_TIP=$TIP  (from $TIPM)"
echo
echo "(a) 代码仓一致"
for spec in "${QNODES[@]}"; do
  H="${spec%%|*}"; r="${spec#*|}"; NAME="${r%%|*}"; r="${r#*|}"
  DIR="${r%%|*}"; WANT="${r##*|}"
  OUT=$(runps "$H" "[Console]::OutputEncoding=[Text.Encoding]::UTF8
$GITSHIM
Set-Location '$DIR'
\$full = ((& \$g rev-parse HEAD) -join '')
Write-Output ('H ' + \$full.Substring(0,8))
Write-Output ('B ' + ((& \$g rev-parse --abbrev-ref HEAD) -join ''))
Write-Output ('O ' + ((& \$g remote get-url origin) -join ''))
\$d = (& \$g status --porcelain | Out-String).Trim()
Write-Output ('D ' + (@(\$d -split \"\`n\" | Where-Object { \$_ -ne '' }).Count))" | grep -aE "^[HBOD] ")
  hh=$(echo "$OUT" | awk '/^H /{print $2}')
  bb=$(echo "$OUT" | awk '/^B /{print $2}')
  oo=$(echo "$OUT" | awk '/^O /{print $2}')
  dd=$(echo "$OUT" | awk '/^D /{print $2}')
  if [ -z "$hh" ]; then printf "  %-10s UNREACH\n" "$NAME"; bad=$((bad+1)); continue; fi
  st="OK"
  [ "$hh" != "$TIP" ] && { st="STALE"; bad=$((bad+1)); }
  [ "${dd:-0}" != "0" ] && { st="$st+DIRTY($dd)"; bad=$((bad+1)); }
  case "$oo" in
    *myainet-quant-git.git) : ;;
    *) st="$st+WRONG-ORIGIN"; warned=$((warned+1)) ;;
  esac
  printf "  %-10s %-16s head=%s branch=%s origin=%s\n" "$NAME" "$st" "$hh" "$bb" "$oo"
done

# ── (b) 调度拓扑唯一性 ──────────────────────────────────────────────────────
echo
echo "(b) 调度拓扑唯一性（同名交易任务不能两台同时启用）"
declare -A ENABLED_ON
for spec in "${HNODES[@]}"; do
  H="${spec%%|*}"; NAME="${spec#*|}"
  TLIST=$(echo "$SINGLE_HOST_TASKS" | tr ' ' ',')
  OUT=$(runps "$H" "[Console]::OutputEncoding=[Text.Encoding]::UTF8
foreach(\$n in @('$TLIST'.Split(','))){
  \$t = Get-ScheduledTask -TaskName \$n -ErrorAction SilentlyContinue
  if(\$t){ Write-Output ('T ' + \$n + ' ' + \$t.State) }
}" | grep -a '^T ')
  while read -r _ tn st; do
    [ -z "${tn:-}" ] && continue
    if [ "$st" != "Disabled" ]; then
      ENABLED_ON["$tn"]="${ENABLED_ON[$tn]:-} $NAME"
    fi
  done <<< "$OUT"
done
if [ ${#ENABLED_ON[@]} -eq 0 ]; then
  echo "  (这些任务在扫描到的机器上一个都没启用)"
fi
for tn in "${!ENABLED_ON[@]}"; do
  hosts="${ENABLED_ON[$tn]}"
  cnt=$(echo $hosts | wc -w)
  if [ "$cnt" -gt 1 ]; then
    printf "  %-26s ❌ 在 %d 台启用:%s\n" "$tn" "$cnt" "$hosts"; bad=$((bad+1))
  else
    printf "  %-26s ✅ 仅 %s\n" "$tn" "$(echo $hosts)"
  fi
done

# ── (c) 缓存末日一致 ────────────────────────────────────────────────────────
echo
echo "(c) 行情缓存末日（参照 ${REF_CODES// /, }）——运行时陈旧=FAIL，非运行时陈旧=WARN"
declare -A CACHE_DAY
for spec in "${QNODES[@]}"; do
  H="${spec%%|*}"; r="${spec#*|}"; NAME="${r%%|*}"; r="${r#*|}"; DIR="${r%%|*}"
  OUT=$(runps "$H" "[Console]::OutputEncoding=[Text.Encoding]::UTF8
\$dd = Join-Path '$DIR' 'aquant\_cache\daily'
if(-not (Test-Path \$dd)){ Write-Output 'X nodir'; exit }
foreach(\$c in @($(echo $REF_CODES | sed 's/ /,/g' | sed "s/[0-9]\+/'&'/g"))){
  \$fs = Get-ChildItem \$dd -Filter (\$c + '_*.csv') -ErrorAction SilentlyContinue
  if(-not \$fs){ Write-Output ('C ' + \$c + ' none'); continue }
  \$pick = @(\$fs | Where-Object { \$_.Name -like '*_tx*' }) + @(\$fs | Where-Object { \$_.Name -notlike '*_tx*' })
  \$f = \$pick[0]
  \$last = Get-Content \$f.FullName -Tail 1
  \$dt = (\$last -split ',')[0]
  Write-Output ('C ' + \$c + ' ' + \$dt + ' ' + \$f.Name)
}" | grep -a '^C ')
  echo "$OUT" | while read -r _ c dt fn; do [ -n "${c:-}" ] && printf "  %-10s %-8s %s  (%s)\n" "$NAME" "$c" "$dt" "$fn"; done
  # 汇总每个 code 的末日用于跨机比较
  while read -r _ c dt fn; do
    [ -z "${c:-}" ] && continue
    CACHE_DAY["$c"]="${CACHE_DAY[$c]:-}|$NAME:$dt"
  done <<< "$OUT"
done
# 语义：先找出全局最新末日，再逐机判定
#   运行时落后于最新  -> FAIL（它算出来的指标是错的）
#   非运行时有出入    -> WARN（它已不是数据源；但仍提示"别在那台上本地算"）
for c in $REF_CODES; do
  v="${CACHE_DAY[$c]:-}"
  [ -z "$v" ] && continue
  maxday=$(echo "$v" | tr '|' '\n' | sed 's/.*://' | grep -v '^$' | sort -r | head -1)
  okmsg=""
  echo "$v" | tr '|' '\n' | grep -v '^$' | while IFS=: read -r nm dy; do
    [ -z "${nm:-}" ] && continue
    if [ "$dy" = "$maxday" ]; then
      printf "  ✅ %-8s %s  %s (最新)\n" "$nm" "$c" "$dy"
    elif [ "$nm" = "$RUNTIME_NODE" ]; then
      printf "  ❌ %-8s %s  %s  ← 运行时落后于最新 %s，指标会算错\n" "$nm" "$c" "$dy" "$maxday"
    else
      printf "  ⚠️  %-8s %s  %s  ← 落后 %s；该机已非数据源，勿在此本地做量化分析\n" "$nm" "$c" "$dy" "$maxday"
    fi
  done
  # 汇总判定
  for spec in "${QNODES[@]}"; do
    r="${spec#*|}"; NAME="${r%%|*}"
    dy=$(echo "$v" | tr '|' '\n' | grep "^$NAME:" | cut -d: -f2)
    [ "$dy" = "$maxday" ] && continue
    if [ "$NAME" = "$RUNTIME_NODE" ]; then bad=$((bad+1)); else warned=$((warned+1)); fi
  done
done

echo
echo "VERIFY_FLEET=done problems=$bad warnings=$warned"
[ $bad -eq 0 ] && echo "FLEET_OK" || exit 1
