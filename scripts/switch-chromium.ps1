# Runs scripts/switch-chromium.sh via Git Bash.
# Usage: .\switch-chromium.ps1 <chromium-revision-hash>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$bash = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "$env:ProgramFiles\Git\usr\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
  throw 'Git Bash (bash.exe) not found. Install Git for Windows.'
}

Push-Location $repoRoot
try {
  & $bash 'scripts/switch-chromium.sh' @args
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  Pop-Location
}
