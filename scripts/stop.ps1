Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
docker compose -f "$root/docker-compose.yml" down
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker Compose shutdown"
