Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
docker compose -f "$root/docker-compose.yml" up -d --no-build
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker Compose startup with existing images"

Write-Host "Doris FE UI: http://localhost:8030"
Write-Host "Flink UI: http://localhost:8081"
Write-Host "Started with existing local images. If images are missing, run scripts/start.ps1 once to build them."
