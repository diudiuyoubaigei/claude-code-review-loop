param(
  [string]$Prompt,
  [string]$PromptFile,
  [string]$WorkingDirectory,
  [string]$PermissionMode = "acceptEdits"
)

$ErrorActionPreference = "Stop"

if ($WorkingDirectory) {
  Set-Location -LiteralPath $WorkingDirectory
}

if ($PromptFile) {
  $Prompt = Get-Content -LiteralPath $PromptFile -Raw
}

if (-not $Prompt) {
  throw "Provide -Prompt or -PromptFile."
}

$claude = Get-Command claude -ErrorAction Stop

& $claude.Source --permission-mode $PermissionMode -p $Prompt
exit $LASTEXITCODE
