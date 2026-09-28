# myainet 共享层·多镜像同步 v4
# 任一台镜像机故障时自动换用其它镜像；本机自己的 bare 走本地文件路径
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
  foreach ($c in $cands) { if (Test-Path (Join-Path $c ".git")) { $RepoPath = $c; break } }
}
if (-not $RepoPath -or -not (Test-Path (Join-Path $RepoPath ".git"))) {
  Write-Output "SYNC=FAIL reason=repo-missing"; exit 2
}
$log = @("repo=" + $RepoPath)
# 1) 按优先级找第一个可达镜像 fetch
$fetched = ""
foreach ($m in $MIRRORS) {
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
# 3) 推给所有镜像 + 本机自己的 bare
$ok = 0; $bad = @()
foreach ($m in $MIRRORS) {
  & $GIT -C $RepoPath push --quiet $m master 2>$null
  if ($LASTEXITCODE -eq 0) { $ok++ } else { $bad += ($m -replace 'Administrator@', '') }
}
$lok = 0
foreach ($lb in $LOCAL_BARES) {
  if (Test-Path (Join-Path $lb "HEAD")) {
    & $GIT -C $RepoPath push --quiet $lb master 2>$null
    if ($LASTEXITCODE -eq 0) { $lok++ } else { $bad += ("local:" + $lb) }
  }
}
$log += "pushed_remote=$ok/$($MIRRORS.Count)"
if ($lok -gt 0) { $log += "pushed_local=$lok" }
$log += "head=" + (& $GIT -C $RepoPath rev-parse --short master 2>$null).Trim()
if ($bad.Count -gt 0) { $log += "failed=" + ($bad -join ',') }
Write-Output ("SYNC=OK " + ($log -join " | "))
