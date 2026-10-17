# check-armed.ps1 -- 检查共享层协议是否"带电"（armed）
#
# 为什么要它（FM-31）：
#   2026-10-17 排查双线分叉时发现，config 文档里写着的三道机械防线，一个都没装：
#   memory/inbox 不存在、.git/hooks/pre-commit 未安装、200 笔提交 0 次走 inbox。
#   "写了脚本"和"脚本在跑"之间隔着一整次安装，而没人检查它装没装。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File check-armed.ps1 [-RepoPath <共享层根>]
#   退出码：0 = ARMED=OK；4 = ARMED=FAIL（缺件见输出）
#
# 建议接进开机/每日任务，ARMED=FAIL 即视为告警条件。

param([string]$RepoPath = "")

$ErrorActionPreference = 'Continue'
$missing = @()
$lines = @()

# ---- 0) 找共享层根 ----
if (-not $RepoPath) {
    $cands = @("G:\DSH\_shared", "D:\DSH\_shared", "E:\DSH\_shared")
    $cands += (Join-Path $env:USERPROFILE ".dsh\_shared")
    $cands += (Join-Path $env:USERPROFILE "_shared")
    foreach ($c in $cands) {
        if (Test-Path ($c + "\.git") -ErrorAction SilentlyContinue) { $RepoPath = $c; break }
    }
}
if (-not $RepoPath -or -not (Test-Path ($RepoPath + "\.git"))) {
    Write-Output "ARMED=FAIL reason=shared-root-not-found"
    exit 4
}
$lines += "repo=$RepoPath"

# ---- 1) pre-commit 守卫 ----
$hookDir = (& git -C $RepoPath rev-parse --git-path hooks 2>$null)
if ($hookDir -and $hookDir -notmatch '^([A-Za-z]:)?/') { $hookDir = Join-Path $RepoPath $hookDir }
if (-not $hookDir) { $hookDir = Join-Path $RepoPath ".git\hooks" }
$hook = Join-Path $hookDir "pre-commit"
if (Test-Path $hook) {
    $sz = (Get-Item $hook).Length
    $lines += "hook=OK size=${sz}B"
    # 守卫本体是否是最新版（含冲突标记检查的标记串）
    $body = [System.IO.File]::ReadAllText($hook)
    if ($body -notmatch '重复的记忆编号') { $lines += "hook=WARN body-may-be-stale"; }
} else {
    $missing += "pre-commit-hook"
    $lines += "hook=MISSING"
}

# ---- 2) inbox 唯一写入通道 ----
$inbox = Join-Path $RepoPath "memory\inbox"
if (Test-Path $inbox) {
    $n = (Get-ChildItem $inbox -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'README.md' } | Measure-Object).Count
    $lines += "inbox=OK pending=$n"
} else {
    $missing += "inbox"
    $lines += "inbox=MISSING"
}

# ---- 3) 同步任务已接且未禁用 ----
$taskNames = @('DSH-SharedSync', 'myainet-SharedSync-Mirror')
$found = @()
foreach ($t in $taskNames) {
    $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if ($task) {
        $state = "$($task.State)"
        $lines += ("task:" + $t + "=" + $state)
        if ($state -ne 'Disabled') { $found += $t }
    }
}
if ($found.Count -eq 0) {
    $missing += "sync-task"
    $lines += "sync-task=MISSING-or-disabled"
} else {
    $lines += "sync-task=OK (" + ($found -join ",") + ")"
}

# ---- 4) 汇总 ----
$lines | ForEach-Object { Write-Output $_ }
if ($missing.Count -gt 0) {
    Write-Output ("ARMED=FAIL missing=" + ($missing -join ","))
    exit 4
}
Write-Output "ARMED=OK"
exit 0
