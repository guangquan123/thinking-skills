<#
sync-to-github.ps1 — 把本 skill 同步发布到 GitHub
=====================================================
背景：本机 git push 到 github.com 会被网络重置（Connection was reset），
但 api.github.com 可通。本脚本走 GitHub REST API 推送，
并让远端提交对象与本地 git 提交对象**完全一致**（同 sha），
本地与远端历史保持对齐，后续可反复增量同步。

处理两种远端状态：
  - 空仓库（无任何提交）：Git Data API 被 409 拒绝，先用 Contents API
    PUT 一个文件引导出初始提交，再用 Git Data API 重建干净的根提交并强更 ref；
  - 非空仓库：直接 Git Data API 增量同步（上传缺失 blob → 建 tree → 建 commit → 更新 ref）。

用法（任意目录执行）：
  powershell -ExecutionPolicy Bypass -File "<skill根目录>\scripts\sync-to-github.ps1" -Message "feat: 本次更新说明"

行为：
  1. 若工作区有改动，先在本地 git commit（无改动则直接用 HEAD）
  2. 读取本地提交的 tree/作者/时间/消息
  3. 发布到远端，校验远端 commit sha 与本地一致

凭据：自动从 git credential manager 读取 github.com 令牌，脚本内不硬编码任何密钥。
注意：本文件必须保存为 UTF-8 with BOM，否则 PowerShell 5.1 会按 ANSI 误读中文导致解析失败。
#>
param(
  [string]$Message = "chore: 同步 skill 更新",
  [string]$Owner   = "guangquan123",
  [string]$Repo    = "problem-analysis",
  [string]$Branch  = "main"
)

$root = Split-Path -Parent $PSScriptRoot
$api  = "https://api.github.com/repos/$Owner/$Repo"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-Git {
  # 包装 git 命令：吞掉 stderr 警告（如 CRLF 提示），退出码非 0 才抛错
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = @()
  try {
    $out = @(& git @GitArgs 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { Write-Verbose $_.Exception.Message } else { "$_" }
    })
  } finally { $ErrorActionPreference = $prev }
  if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') 失败（退出码 $LASTEXITCODE）" }
  # 不带逗号返回：空数组在管道中展开为 0 个元素，避免调用方误判"有输出"
  return $out
}

function ConvertTo-IsoDate([string]$rawGitDate) {
  # rawGitDate 形如 "1758439000 +0800"
  $parts = $rawGitDate.Trim() -split ' '
  $epoch = [long]$parts[0]
  $tz = $parts[1]
  $sign = if ($tz[0] -eq '-') { -1 } else { 1 }
  $hh = [int]$tz.Substring(1, 2); $mm = [int]$tz.Substring(3, 2)
  $offset = [TimeSpan]::FromMinutes($sign * ($hh * 60 + $mm))
  $dto = [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToOffset($offset)
  $dto.ToString("yyyy-MM-ddTHH:mm:sszzz")
}

function Get-BlobTempFile([string]$blobSha, [string]$tmpPath) {
  # 二进制安全导出 blob 内容到临时文件（cmd 重定向，避免 PS 管道编码问题）
  cmd /c "git cat-file blob $blobSha > `"$tmpPath`" 2>nul"
  return $tmpPath
}

function Test-RepoEmptyError($err) {
  $detail = ''
  if ($err.Exception.Response) { $detail += [int]$err.Exception.Response.StatusCode }
  if ($err.ErrorDetails) { $detail += $err.ErrorDetails.Message }
  return ($detail -match '409|empty')
}

Push-Location $root
try {
  # ---------- 0) 本地提交 ----------
  Invoke-Git add -A | Out-Null
  $dirty = @(Invoke-Git status --porcelain)
  if ($dirty.Count -gt 0) {
    Invoke-Git commit -m $Message | Out-Null
    Write-Output "本地已提交：$Message"
  } else {
    Write-Output "本地无新改动，直接同步当前 HEAD"
  }
  $head   = ((Invoke-Git rev-parse HEAD) -join '').Trim()
  $meta   = ((Invoke-Git log -1 --date=raw --format='%an%x00%ae%x00%ad%x00%cn%x00%ce%x00%cd' HEAD) -join '') -split "`0"
  # git 的 commit 消息固定以单个尾部换行存储；%B 按行捕获会丢尾部换行，这里显式补回，
  # 保证远端 commit 对象与本地逐字节一致（sha 相同）
  $msgTxt = (((Invoke-Git log -1 --format=%B HEAD) -join "`n").TrimEnd("`n")) + "`n"
  Write-Output "本地 commit=$head"

  # ---------- 1) 凭据 ----------
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $cred = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
  $ErrorActionPreference = $prev
  $token = (($cred | Where-Object { $_ -like 'password=*' }) -replace 'password=','').Trim()
  if (-not $token) { throw "未找到 github.com 凭据（git credential fill 为空）" }
  $hdrs = @{ Authorization = "token $token"; Accept = "application/vnd.github+json"; "User-Agent" = "deepworks-skill-sync" }

  # ---------- 2) 远端分支现状 ----------
  $remoteHead = $null
  try {
    $refInfo = Invoke-RestMethod -Uri "$api/git/ref/heads/$Branch" -Headers $hdrs
    $remoteHead = $refInfo.object.sha
    Write-Output "远端 $Branch 当前=$remoteHead"
  } catch { Write-Output "远端分支 $Branch 尚不存在，将创建" }
  if ($remoteHead -eq $head) { Write-Output "远端已是最新（$head），无需同步"; exit 0 }

  # ---------- 3) 补齐远端缺失的 blob ----------
  $entries = @()
  $lines = @(Invoke-Git ls-tree -r HEAD)
  foreach ($l in $lines) {
    $m = [regex]::Match($l, '^(\d+) (\w+) ([0-9a-f]{40})\t(.+)$')
    if (-not $m.Success) { continue }
    $entries += @{ path = $m.Groups[4].Value; mode = $m.Groups[1].Value; type = "blob"; sha = $m.Groups[3].Value }
  }
  $tmpBlob = Join-Path $env:TEMP "skill-sync-blob.bin"
  $bootstrapped = $false
  foreach ($e in $entries) {
    $exists = $false
    try { $null = Invoke-RestMethod -Uri "$api/git/blobs/$($e.sha)" -Headers $hdrs; $exists = $true } catch { }
    if ($exists) { continue }
    Get-BlobTempFile $e.sha $tmpBlob | Out-Null
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tmpBlob))
    try {
      $null = Invoke-RestMethod -Method Post -Uri "$api/git/blobs" -Headers $hdrs `
        -Body (@{ content = $b64; encoding = "base64" } | ConvertTo-Json) -ContentType "application/json"
      Write-Output "上传 blob: $($e.path)"
    } catch {
      if ((Test-RepoEmptyError $_) -and -not $bootstrapped) {
        # 空仓库：Git Data API 被 409 拒绝，先用 Contents API 引导出第一个提交
        Write-Output "远端是空仓库，先用 Contents API 引导初始提交（随后会被干净的根提交替换）..."
        $null = Invoke-RestMethod -Method Put -Uri "$api/contents/$($e.path)" -Headers $hdrs `
          -Body (@{ message = "chore: bootstrap empty repository"; content = $b64; branch = $Branch } | ConvertTo-Json) `
          -ContentType "application/json"
        $bootstrapped = $true
        Start-Sleep -Seconds 2
        $null = Invoke-RestMethod -Method Post -Uri "$api/git/blobs" -Headers $hdrs `
          -Body (@{ content = $b64; encoding = "base64" } | ConvertTo-Json) -ContentType "application/json"
        Write-Output "引导完成，上传 blob: $($e.path)"
      } else {
        Write-Output "上传 blob 失败：$($e.path) - $($_.Exception.Message)"
        if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
        throw
      }
    }
  }
  if (Test-Path $tmpBlob) { Remove-Item $tmpBlob -Force }
  if ($bootstrapped) { Write-Output "注意：引导提交将在最后被完整根提交替换（force 更新 ref）" }

  # ---------- 4) 创建相同的 tree 与 commit ----------
  try {
    $tree = Invoke-RestMethod -Method Post -Uri "$api/git/trees" -Headers $hdrs `
      -Body (@{ tree = $entries } | ConvertTo-Json -Depth 5 -Compress) `
      -ContentType "application/json"
  } catch {
    Write-Output "创建 tree 失败：$($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    throw
  }
  $localTree = ((Invoke-Git rev-parse 'HEAD^{tree}') -join '').Trim()
  Write-Output "tree=$($tree.sha)（本地=$localTree）"

  $author    = @{ name = $meta[0]; email = $meta[1]; date = ConvertTo-IsoDate $meta[2] }
  $committer = @{ name = $meta[3]; email = $meta[4]; date = ConvertTo-IsoDate $meta[5] }
  $parents = @()
  if ($remoteHead -and -not $bootstrapped) { $parents = @($remoteHead) }
  try {
    $commit = Invoke-RestMethod -Method Post -Uri "$api/git/commits" -Headers $hdrs `
      -Body (@{ message = $msgTxt; tree = $tree.sha; parents = $parents; author = $author; committer = $committer } | ConvertTo-Json -Depth 5 -Compress) `
      -ContentType "application/json; charset=utf-8"
  } catch {
    Write-Output "创建 commit 失败：$($_.Exception.Message)"
    if ($_.ErrorDetails) { Write-Output $_.ErrorDetails.Message }
    throw
  }
  Write-Output "远端 commit=$($commit.sha)"

  # ---------- 5) 更新远端 ref ----------
  if ($bootstrapped) {
    # 引导提交是临时占位，强制替换为真实根提交
    $null = Invoke-RestMethod -Method Patch -Uri "$api/git/refs/heads/$Branch" -Headers $hdrs `
      -Body (@{ sha = $commit.sha; force = $true } | ConvertTo-Json) -ContentType "application/json"
  } elseif ($remoteHead) {
    $null = Invoke-RestMethod -Method Patch -Uri "$api/git/refs/heads/$Branch" -Headers $hdrs `
      -Body (@{ sha = $commit.sha; force = $false } | ConvertTo-Json) -ContentType "application/json"
  } else {
    $null = Invoke-RestMethod -Method Post -Uri "$api/git/refs" -Headers $hdrs `
      -Body (@{ ref = "refs/heads/$Branch"; sha = $commit.sha } | ConvertTo-Json) -ContentType "application/json"
  }

  if ($commit.sha -eq $head) {
    Write-Output "同步完成，本地与远端提交完全一致：$head"
  } else {
    Write-Output "同步完成，但远端 commit sha 与本地不同（可能是日期格式差异），内容一致。"
    Write-Output "远端=$($commit.sha) 本地=$head"
  }
  Write-Output "https://github.com/$Owner/$Repo"
} finally {
  Pop-Location
}
