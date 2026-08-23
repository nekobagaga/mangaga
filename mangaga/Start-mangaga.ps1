$ErrorActionPreference = "Stop"

$appScript = Join-Path $PSScriptRoot "src\mangaga.ps1"
$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path -LiteralPath $appScript)) {
    throw "Cannot find app script: $appScript"
}

& $powershellExe -NoProfile -ExecutionPolicy Bypass -STA -File $appScript
