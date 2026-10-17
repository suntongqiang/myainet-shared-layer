# publish-gh-api.ps1 -- 用 GitHub Git Data API 发布本技能（绕开可能不通的 github.com）
#
# 为什么需要它（2026-10-18 实测）：
#   本机 github.com:443 **不通**（TCP 超时），但 api.github.com:443 通。
#   `git push` 走 github.com 必然失败 → 只能用 REST Git Data API 覆盖发布。
#   参见 mem-0305：这不是偶发，是这台机器的常态路径。
#
# 用法：
#   # 令牌：优先用 $env:GH_TOKEN；没有就从 DPAPI 取（本机本用户）
#   powershell -NoProfile -ExecutionPolicy Bypass -File publish-gh-api.ps1 `
#       [-Source <技能目录>] [-Owner suntongqiang] [-Repo myainet-shared-layer] [-Branch main] [-DryRun]
#
# 原子性：先建 blob / tree / commit，**最后一步才 PATCH ref**；前置任何失败都不改动远端。
# 注意：新 tree 不设 base_tree = 完整覆盖（远端多余文件会被移除）。

# ★ param() 必须是第一条可执行语句（放在 $ErrorActionPreference 之后会报"赋值表达式无效"）
param(
    [string]$Source = (Split-Path $PSScriptRoot -Parent),
    [string]$Owner  = 'suntongqiang',
    [string]$Repo   = 'myainet-shared-layer',
    [string]$Branch = 'main',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

if (-not $env:GH_TOKEN) {
    $patScript = Join-Path $env:USERPROFILE '.dsh\.secrets\get-github-pat.ps1'
    if (Test-Path $patScript) { & $patScript -AsEnvironmentVariable | Out-Null }
}
if (-not $env:GH_TOKEN) { Write-Output 'PUBLISH=FAIL reason=no-token'; exit 3 }

$Headers = @{ Authorization = "Bearer $env:GH_TOKEN"; 'User-Agent' = 'myainet-publish'; Accept = 'application/vnd.github+json' }
$api = "https://api.github.com/repos/$Owner/$Repo"

function ApiGet([string]$u) { (Invoke-WebRequest $u -Headers $Headers -TimeoutSec 30 -UseBasicParsing).Content | ConvertFrom-Json }
function ApiSend([string]$u, [string]$method, $obj) {
    $body = $obj | ConvertTo-Json -Depth 20 -Compress
    (Invoke-WebRequest $u -Method $method -Headers $Headers -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60 -UseBasicParsing).Content | ConvertFrom-Json
}

$ref       = ApiGet "$api/git/ref/heads/$Branch"
$baseSha   = $ref.object.sha
$baseTree  = (ApiGet "$api/git/commits/$baseSha").tree.sha
Write-Output ("base = " + $baseSha.Substring(0,7))
Write-Output ("ROLLBACK-TO " + $baseSha)

$files = Get-ChildItem $Source -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' }
Write-Output ("files = " + $files.Count)
if ($DryRun) { Write-Output 'PUBLISH=DRYRUN'; exit 0 }

$entries = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Source.Length + 1) -replace '\\', '/'
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.FullName))
    $blob = ApiSend "$api/git/blobs" 'POST' @{ content = $b64; encoding = 'base64' }
    $mode = if ($f.Extension -in @('.sh', '.ps1')) { '100755' } else { '100644' }
    $entries += @{ path = $rel; mode = $mode; type = 'blob'; sha = $blob.sha }
}

$tree   = ApiSend "$api/git/trees"   'POST' @{ tree = $entries }
$msg    = "sync from shared layer (" + $env:COMPUTERNAME + ") " + (Get-Date -Format 'yyyy-MM-dd')
$commit = ApiSend "$api/git/commits" 'POST' @{ message = $msg; tree = $tree.sha; parents = @($baseSha) }
$null   = ApiSend "$api/git/refs/heads/$Branch" 'PATCH' @{ sha = $commit.sha }
Write-Output ("pushed " + $commit.sha.Substring(0,7) + " (" + $entries.Count + " files)")

$now = ApiGet "$api/commits/$Branch"
Write-Output ("verify head = " + $now.sha.Substring(0,7))
if ($now.sha -ne $commit.sha) { Write-Output 'PUBLISH=FAIL reason=verify-mismatch'; exit 5 }
Write-Output 'PUBLISH=OK'
