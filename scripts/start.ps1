Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
docker compose -f "$root/docker-compose.yml" up -d --build
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker Compose build and startup"

Write-Host "Doris FE UI: http://localhost:8030"
Write-Host "Flink UI: http://localhost:8081"
