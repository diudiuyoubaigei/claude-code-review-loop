param(
  [string]$RunId,
  [string]$StateDirectory,
  [string]$StateRoot = "",
  [int]$WaitSeconds = 0,
  [int]$TailLines = 20
)

$ErrorActionPreference = "Stop"

if (-not $StateDirectory) {
  if (-not $RunId) {
    throw "Provide -RunId or -StateDirectory."
  }

  if (-not $StateRoot) {
    $StateRoot = Join-Path $env:TEMP "codex-claude-dispatch"
  }

  $StateDirectory = Join-Path $StateRoot $RunId
}

$metaPath = Join-Path $StateDirectory "run.json"
if (-not (Test-Path -LiteralPath $metaPath)) {
  throw "Run metadata not found: $metaPath"
}

function Get-RunMeta {
  return Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
}

function Get-ProcessAlive {
  param($Run)

  if (-not $Run.runnerPid) {
    return $false
  }

  return $null -ne (Get-Process -Id $Run.runnerPid -ErrorAction SilentlyContinue)
}

$deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))

while ($true) {
  $run = Get-RunMeta
  $processAlive = Get-ProcessAlive -Run $run
  $active = ($run.status -in @("starting", "running")) -and $processAlive

  if (-not $active) {
    if (($run.status -in @("starting", "running")) -and -not $processAlive -and -not $run.finishedAt) {
      $run.status = "unknown"
      $run.finishedAt = (Get-Date).ToString("o")
      $run.error = "Runner process exited without writing a terminal state."
      $run | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding utf8
    }
    break
  }

  if ((Get-Date) -ge $deadline) {
    break
  }

  Start-Sleep -Seconds ([Math]::Min(5, [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)))
}

$run = Get-RunMeta
$processAlive = Get-ProcessAlive -Run $run
$logTail = @()
$logUpdatedAt = $null

if (Test-Path -LiteralPath $run.logPath) {
  $logTail = @(Get-Content -LiteralPath $run.logPath -Tail $TailLines | ForEach-Object { ("$_" -replace "`0", "") })
  $logUpdatedAt = (Get-Item -LiteralPath $run.logPath).LastWriteTime.ToString("o")
}

$changedFiles = @()
$diffStat = @()

if ($run.workingDirectory -and (Test-Path -LiteralPath $run.workingDirectory)) {
  $gitStatus = @(& cmd.exe /d /c "git -C `"$($run.workingDirectory)`" status --short 2>nul")
  if ($LASTEXITCODE -eq 0) {
    foreach ($line in $gitStatus) {
      if (-not $line) {
        continue
      }

      $status = $line.Substring(0, [Math]::Min(2, $line.Length)).Trim()
      $path = if ($line.Length -gt 3) { $line.Substring(3).Trim() } else { "" }
      $changedFiles += [ordered]@{
        status = $status
        path = $path
      }
    }

    $diffStat = @(& cmd.exe /d /c "git -C `"$($run.workingDirectory)`" diff --stat 2>nul")
  }
}

$startedAt = if ($run.startedAt) { [datetimeoffset]::Parse($run.startedAt) } else { $null }
$finishedAt = if ($run.finishedAt) { [datetimeoffset]::Parse($run.finishedAt) } else { $null }
$touchedFilesSinceStart = @()

if ($startedAt -and $run.workingDirectory) {
  foreach ($entry in $changedFiles) {
    if (-not $entry.path) {
      continue
    }

    $fullPath = Join-Path $run.workingDirectory $entry.path
    if (-not (Test-Path -LiteralPath $fullPath)) {
      continue
    }

    $lastWriteTime = (Get-Item -LiteralPath $fullPath).LastWriteTime
    if ($lastWriteTime.ToUniversalTime() -ge $startedAt.UtcDateTime) {
      $touchedFilesSinceStart += [ordered]@{
        path = $entry.path
        lastWriteTime = $lastWriteTime.ToString("o")
      }
    }
  }
}

$elapsed = if ($startedAt) {
  if ($finishedAt) {
    [Math]::Round(($finishedAt - $startedAt).TotalMinutes, 1)
  } else {
    [Math]::Round(((Get-Date).ToUniversalTime() - $startedAt.UtcDateTime).TotalMinutes, 1)
  }
} else {
  $null
}

[ordered]@{
  runId = $run.runId
  status = $run.status
  processAlive = $processAlive
  startedAt = $run.startedAt
  finishedAt = $run.finishedAt
  elapsedMinutes = $elapsed
  workingDirectory = $run.workingDirectory
  runnerPid = $run.runnerPid
  exitCode = $run.exitCode
  error = $run.error
  logPath = $run.logPath
  logUpdatedAt = $logUpdatedAt
  outputTail = $logTail
  changedFileCount = $changedFiles.Count
  changedFiles = $changedFiles
  touchedFileCount = $touchedFilesSinceStart.Count
  touchedFilesSinceStart = $touchedFilesSinceStart
  diffStat = $diffStat
} | ConvertTo-Json -Depth 6
