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
# 本脚本做五项校验：
#   (a) 代码仓一致 —— 各机量化仓 HEAD == 镜像尖端，且工作区干净、origin 指向本地镜像
#   (b) 调度拓扑唯一 —— 同名交易任务不能在两台以上同时「启用」（否则重复告警/重复下单）
#   (c) 缓存末日一致 —— 各机行情缓存的最后数据日一致（否则同一问题两台两个答案）
#   (d) 计划任务健康 —— 各机启用中的交易任务**最近一次到底跑成功了没有**（返回码 + 最近运行时间）
#       ★2026-09-30 新增：此前只查"任务在不在、有没有重复启用"，不问"它跑成功了吗"，
#         结果 aquant_gate 带着 rc=0x80000003 静默失败了两天无人知晓。
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

# ── (d) 计划任务健康（返回码 + 最近运行时间）──────────────────────────────────
# ★这条本该早就存在。2026-09-30 发现：aquant_gate 连续两天 LastTaskResult=0x80000003
#   （py_mini_racer/内嵌 V8 在多线程下 abort 整个进程），**任务日志里只有崩溃栈、
#   没有任何正常输出，也没有人收到任何提示**。(b) 只问"任务在不在、有没有重复启用"，
#   不问"它跑成功了吗" —— 这正是 FM-23「校验器的覆盖面，就是故障的藏身处」。
echo
echo "(d) 计划任务健康（返回码 / 最近运行时间）"
# ★「正在运行」不等于健康：2026-09-30 实测 aquant_gate 挂死 3.5 小时（CPU 冻结在 3614s），
#   而 (d) 会把它显示成「⏳ 正在运行」放行 —— 又一个"看起来健康"的盲区。
#   阈值可用 VERIFY_RUNNING_MAX_MIN 覆盖（自测用；默认 90 分钟，本项目最长正常任务约 30 分钟）。
RUNNING_MAX_MIN="${VERIFY_RUNNING_MAX_MIN:-90}"
TASKLIST=$(echo "$SINGLE_HOST_TASKS" | tr ' ' ',')
NOW=$(date +%s)
for spec in "${HNODES[@]}"; do
  H="${spec%%|*}"; NAME="${spec#*|}"
  OUT=$(runps "$H" "[Console]::OutputEncoding=[Text.Encoding]::UTF8
foreach(\$n in @('$TASKLIST'.Split(','))){
  \$t = Get-ScheduledTask -TaskName \$n -ErrorAction SilentlyContinue
  if(\$t -and \$t.State -ne 'Disabled'){
    \$i = Get-ScheduledTaskInfo -TaskName \$n
    Write-Output ('J ' + \$n + ' rc=' + \$i.LastTaskResult + ' last=' + \$i.LastRunTime.ToString('yyyy-MM-ddTHH:mm') + ' state=' + \$t.State)
  }
}" | grep -a '^J ')
  if [ -z "$OUT" ]; then echo "  $NAME   （无启用中的交易任务）"; continue; fi
  while read -r _ tn rest; do
    [ -z "${tn:-}" ] && continue
    rc=$(printf '%s' "$rest" | grep -o 'rc=[0-9-]*' | cut -d= -f2)
    last=$(printf '%s' "$rest" | grep -o 'last=[0-9T:-]*' | cut -d= -f2)
    stt=$(printf '%s' "$rest" | grep -o 'state=[A-Za-z]*' | cut -d= -f2)
    # 0=成功  267009=0x41301 正在运行  267011=0x41303 从未运行
    case "$rc" in
      0)         printf "  %-8s %-26s \xe2\x9c\x85 rc=0 %s (%s)\n" "$NAME" "$tn" "$stt" "$last" ;;
      267009)    _rt=$(date -d "${last}:00" +%s 2>/dev/null || echo "")
                 _mins=""
                 [ -n "$_rt" ] && _mins=$(( (NOW - _rt) / 60 ))
                 if [ -n "$_mins" ] && [ "$_mins" -gt "$RUNNING_MAX_MIN" ]; then
                   printf "  %-8s %-26s \xe2\x9d\x8c \u5df2\u8fd0\u884c %s \u5206\u949f\u4ecd\u672a\u7ed3\u675f\uff08\u7591\u4f3c\u6302\u6b7b\uff09\n" "$NAME" "$tn" "$_mins"
                   bad=$((bad+1))
                 else
                   printf "  %-8s %-26s \xe2\x8f\xb3 \u6b63\u5728\u8fd0\u884c (%s)\n" "$NAME" "$tn" "$last"
                 fi ;;
      267011)    printf "  %-8s %-26s \xe2\x9a\xa0\xef\xb8\x8f  从未运行 (%s)\n" "$NAME" "$tn" "$last"; warned=$((warned+1)) ;;
      *)         hex=$(printf '0x%X' "$rc" 2>/dev/null || echo '?')
                 printf "  %-8s %-26s \xe2\x9d\x8c rc=%s (%s) 最近=%s state=%s\n" "$NAME" "$tn" "$rc" "$hex" "$last" "$stt"
                 bad=$((bad+1)) ;;
    esac
    if [ -n "$last" ]; then
      lt=$(date -d "${last}:00" +%s 2>/dev/null || echo "")
      if [ -n "$lt" ]; then
        age=$(( (NOW - lt) / 86400 ))
        if [ "$age" -gt 5 ]; then
          printf "  %-8s %-26s \xe2\x9a\xa0\xef\xb8\x8f  最近一次运行距今 %d 天（静默停滞？）\n" "$NAME" "$tn" "$age"
          warned=$((warned+1))
        fi
      fi
    fi
  done <<< "$OUT"
done

echo
echo
echo "(e) 因子守门器清单存活（景德 aquant/forbidden-regions.yaml）"
GOUT=$(runps "100.105.238.46" "[Console]::OutputEncoding=[Text.Encoding]::UTF8
\$py='C:\Users\Administrator\AppData\Local\Programs\Python\Python311\python.exe'
Push-Location 'C:\Users\Administrator\金刚'
\$o = & \$py -X utf8 -m aquant.qa_forbidden --list 2>&1
Write-Output ('GRC ' + \$LASTEXITCODE)
Write-Output ('GENT ' + ((\$o | Select-String -Pattern '^  [a-z]').Count))" 2>/dev/null | tr -d "\r")
grc=$(printf "%s\n" "$GOUT" | grep -a "^GRC " | head -1 | awk '{print $2}')
gent=$(printf "%s\n" "$GOUT" | grep -a "^GENT " | head -1 | awk '{print $2}')
if [ "${grc:-}" = "0" ] && [ -n "${gent:-}" ] && [ "${gent:-0}" -ge 5 ]; then
  echo "  ✅ 守门器可用：禁止区域 ${gent} 条"
else
  echo "  ❌ 守门器异常（rc=${grc:-?} 条目=${gent:-?}）—— 闸门可能正在静默放行所有候选"
  bad=$((bad+1))
fi

echo "VERIFY_FLEET=done problems=$bad warnings=$warned"
[ $bad -eq 0 ] && echo "FLEET_OK" || exit 1
