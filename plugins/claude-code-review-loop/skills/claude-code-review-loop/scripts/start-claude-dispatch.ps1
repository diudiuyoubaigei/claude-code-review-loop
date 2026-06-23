param(
  [string]$Prompt,
  [string]$PromptFile,
  [string]$WorkingDirectory,
  [ValidateSet("acceptEdits", "auto", "bypassPermissions", "default", "dontAsk", "plan")]
  [string]$PermissionMode = "bypassPermissions",
  [string]$StateRoot = ""
)

$ErrorActionPreference = "Stop"

if ($WorkingDirectory) {
  $WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
} else {
  $WorkingDirectory = (Get-Location).Path
}

if ($PromptFile) {
  $Prompt = Get-Content -LiteralPath $PromptFile -Raw
}

if (-not $Prompt) {
  throw "Provide -Prompt or -PromptFile."
}

if (-not $StateRoot) {
  $StateRoot = Join-Path $env:TEMP "codex-claude-dispatch"
}

$claude = Get-Command claude -ErrorAction Stop
$runId = "{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$stateDirectory = Join-Path $StateRoot $runId
$promptPath = Join-Path $stateDirectory "prompt.txt"
$logPath = Join-Path $stateDirectory "claude.log"
$metaPath = Join-Path $stateDirectory "run.json"
$runnerPath = Join-Path $stateDirectory "runner.ps1"

New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
Set-Content -LiteralPath $promptPath -Value $Prompt -Encoding utf8
Set-Content -LiteralPath $logPath -Value "" -Encoding utf8

$meta = [ordered]@{
  runId = $runId
  status = "starting"
  workingDirectory = $WorkingDirectory
  permissionMode = $PermissionMode
  startedAt = (Get-Date).ToString("o")
  finishedAt = $null
  promptPath = $promptPath
  logPath = $logPath
  stateDirectory = $stateDirectory
  runnerPid = $null
  exitCode = $null
  error = $null
}
$meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding utf8

$runnerScript = @'
param(
  [string]$MetaPath,
  [string]$PromptPath,
  [string]$LogPath,
  [string]$WorkingDirectory,
  [string]$PermissionMode,
  [string]$ClaudePath
)

$ErrorActionPreference = "Stop"

function Update-RunMeta {
  param([scriptblock]$Mutator)

  $run = Get-Content -LiteralPath $MetaPath -Raw | ConvertFrom-Json
  & $Mutator $run
  $run | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $MetaPath -Encoding utf8
}

Update-RunMeta {
  param($run)
  $run.status = "running"
  $run.runnerPid = $PID
}

if ($WorkingDirectory) {
  Set-Location -LiteralPath $WorkingDirectory
}

try {
  $prompt = Get-Content -LiteralPath $PromptPath -Raw
  $prompt | & $ClaudePath --permission-mode $PermissionMode -p 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Null
  $exitCode = $LASTEXITCODE

  Update-RunMeta {
    param($run)
    $run.exitCode = $exitCode
    $run.finishedAt = (Get-Date).ToString("o")
    $run.status = if ($exitCode -eq 0) { "completed" } else { "failed" }
  }
} catch {
  $_ | Out-String | Add-Content -LiteralPath $LogPath -Encoding utf8

  Update-RunMeta {
    param($run)
    $run.exitCode = -1
    $run.finishedAt = (Get-Date).ToString("o")
    $run.status = "failed"
    $run.error = $_.Exception.Message
  }
}
'@

Set-Content -LiteralPath $runnerPath -Value $runnerScript -Encoding utf8

$process = Start-Process -FilePath "powershell.exe" `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $runnerPath,
    "-MetaPath",
    $metaPath,
    "-PromptPath",
    $promptPath,
    "-LogPath",
    $logPath,
    "-WorkingDirectory",
    $WorkingDirectory,
    "-PermissionMode",
    $PermissionMode,
    "-ClaudePath",
    $claude.Source
  ) `
  -WindowStyle Hidden `
  -PassThru

$meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
$meta.runnerPid = $process.Id
$meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding utf8
$meta | ConvertTo-Json -Depth 6
