Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
docker compose -f "$root/docker-compose.yml" down -v --remove-orphans
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker Compose reset"

Write-Host "Removed project containers, networks, and named volumes."
