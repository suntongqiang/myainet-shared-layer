# myainet 共享层·多镜像同步 v5
# 任一台镜像机故障时自动换用其它镜像；本机自己的 bare 走本地文件路径
#
# ★ 2026-10-07 修正（三个真事故，见 docs/FAILURE-MODES.md）：
#   ① 自检 origin（FM-01）—— origin 指错仓时 fetch/push 都可能"成功"，只有这条能提前暴露
#   ② 退出码必须反映状态（FM-22）—— 原先恒为 0 → 计划任务 LastTaskResult=0，故障静默
#   ③ 本机自己的镜像不再走 ssh 回环，去重后只本地推（FM-29）
param([string]$RepoPath = "")
$ErrorActionPreference = 'Continue'
# git 可能在 PATH 之外（cunchu 实测）→ 先解析出绝对路径
$GIT = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $GIT) {
  foreach ($p in @("C:\Program Files\Git\cmd\git.exe", "C:\Program Files\Git\bin\git.exe", "C:\Program Files (x86)\Git\cmd\git.exe")) {
    if (Test-Path $p) { $GIT = $p; break }
  }
}
if (-not $GIT) { Write-Output "SYNC=FAIL reason=git-not-found"; exit 2 }
$MIRRORS = @(
  "Administrator@100.71.88.47:E:/myainet-shared-git.git",
  "Administrator@100.105.238.46:F:/myainet-shared-git.git",
  "Administrator@100.75.216.97:D:/myainet-shared-git.git"
)
$LOCAL_BARES = @("E:\myainet-shared-git.git", "F:\myainet-shared-git.git", "D:\myainet-shared-git.git", "G:\myainet-shared-git.git")
if (-not $RepoPath) {
  $cands = @("G:\DSH\_shared", "D:\DSH\_shared", "E:\DSH\_shared")
  $cands += (Join-Path $env:USERPROFILE ".dsh\_shared")
  $cands += (Join-Path $env:USERPROFILE "_shared")
  # ★ 用字符串拼接而不是 Join-Path：本机不存在的盘符会让 Join-Path 直接抛 DriveNotFound（噪声）
  foreach ($c in $cands) { if (Test-Path ($c + "\.git") -ErrorAction SilentlyContinue) { $RepoPath = $c; break } }
}
if (-not $RepoPath -or -not (Test-Path (Join-Path $RepoPath ".git"))) {
  Write-Output "SYNC=FAIL reason=repo-missing"; exit 2
}

# ★ 本机自己的 bare：本地直推，并从"远端镜像"列表里剔除（避免 ssh 回环必失败，FM-29）
$LocalBares = @()
foreach ($lb in $LOCAL_BARES) { if (Test-Path ($lb + "\HEAD") -ErrorAction SilentlyContinue) { $LocalBares += $lb } }
$RemoteMirrors = @($MIRRORS | Where-Object {
  $p = ($_ -replace '^[^:]*:', '') -replace '/', '\'
  -not ($LocalBares -contains $p)
})

$log = @("repo=" + $RepoPath)
$rc = 0

# 0) ★ 自检 origin（FM-01）：指错仓时 fetch/push 都可能"成功"，只有这条能提前暴露
$origin = (& $GIT -C $RepoPath remote get-url origin 2>$null)
if ($origin) { $origin = $origin.Trim() }
if ($origin -and ($origin -notmatch 'myainet-shared-git\.git')) {
  Write-Output ("SYNC=WARN reason=origin-points-at-non-fleet-repo origin=" + $origin + " hint='bash verify-live.sh --fix-origin'")
  $rc = 1
}

# 1) 按优先级找第一个可达镜像 fetch
$fetched = ""
foreach ($m in $RemoteMirrors) {
  & $GIT -C $RepoPath fetch --quiet $m master 2>$null
  if ($LASTEXITCODE -eq 0) { $fetched = $m; break }
}
if (-not $fetched) { Write-Output ("SYNC=FAIL reason=no-reachable-mirror | " + ($log -join " | ")); exit 3 }
$log += "fetch=" + ($fetched -replace 'Administrator@', '')
# 2) 保守对齐：只做 fast-forward
$local  = (& $GIT -C $RepoPath rev-parse master 2>$null).Trim()
$remote = (& $GIT -C $RepoPath rev-parse FETCH_HEAD 2>$null).Trim()
if ($local -eq $remote) { $log += "state=in-sync" }
else {
  $base = (& $GIT -C $RepoPath merge-base master FETCH_HEAD 2>$null).Trim()
  if ($base -eq $local) {
    & $GIT -C $RepoPath merge --ff-only FETCH_HEAD 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $log += "action=ff-ok" } else { $log += "action=ff-BLOCKED" }
  }
  elseif ($base -eq $remote) { $log += "state=local-ahead" }
  else { $log += "state=DIVERGED" }
}
# 3) 推给所有远端镜像 + 本机自己的 bare
$ok = 0; $bad = @()
foreach ($m in $RemoteMirrors) {
  & $GIT -C $RepoPath push --quiet $m master 2>$null
  if ($LASTEXITCODE -eq 0) { $ok++ } else { $bad += ($m -replace 'Administrator@', '') }
}
$lok = 0
foreach ($lb in $LocalBares) {
  & $GIT -C $RepoPath push --quiet $lb master 2>$null
  if ($LASTEXITCODE -eq 0) { $lok++ } else { $bad += ("local:" + $lb) }
}
$log += "pushed_remote=$ok/$($RemoteMirrors.Count)"
if ($lok -gt 0) { $log += "pushed_local=$lok" }
$log += "head=" + (& $GIT -C $RepoPath rev-parse --short master 2>$null).Trim()
if ($bad.Count -gt 0) { $log += "failed=" + ($bad -join ',') }
$line = "SYNC=OK " + ($log -join " | ")

# ★ 退出码（FM-22）：分叉 / ff 被挡 / 一台都没推成 / origin 指错 → 非零
if ($log -match 'state=DIVERGED|action=ff-BLOCKED') { $rc = 1 }
if ($RemoteMirrors.Count -gt 0) {
  if ($ok -eq 0) { $rc = 2 } elseif ($ok -lt $RemoteMirrors.Count) { $rc = 1 }
}
Write-Output $line
if ($rc -ne 0) { Write-Output ("SYNC=WARN rc=$rc " + ($log -join " | ")) }
exit $rc
