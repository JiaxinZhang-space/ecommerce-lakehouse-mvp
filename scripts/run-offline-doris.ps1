Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml", "--profile", "tools")

Write-Host "Applying sql/doris/10_offline_trade_warehouse.sql..."
Get-Content "$root/sql/doris/10_offline_trade_warehouse.sql" -Raw | docker @compose run --rm -T mysql-client -hdoris -P9030 -uroot
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris offline warehouse SQL"
Write-Host "Doris offline warehouse chain finished: ODS -> DWD -> DWS -> ADS."
