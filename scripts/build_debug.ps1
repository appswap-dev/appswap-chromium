# Runs scripts/build_debug.sh via Git Bash.
# Usage: .\build_debug.ps1
param(
  [switch]$Portable
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot

$bash = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "$env:ProgramFiles\Git\usr\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
  throw 'Git Bash (bash.exe) not found. Install Git for Windows.'
}

$scriptArgs = @('scripts/build_debug.sh')

Push-Location $repoRoot
try {
  & $bash @scriptArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  Pop-Location
}
