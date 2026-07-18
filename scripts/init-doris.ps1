Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml", "--profile", "tools")

Write-Host "Waiting for Doris FE protocol and at least one alive BE..."
$waitForDoris = @'
until mysql -hdoris -P9030 -uroot -e 'select 1' >/dev/null 2>&1; do sleep 5; done
until mysql -hdoris -P9030 -uroot --batch --raw --skip-column-names -e 'SHOW BACKENDS' 2>/dev/null | grep -Eq '[[:space:]]true[[:space:]]'; do sleep 5; done
'@
docker @compose run --rm --entrypoint sh mysql-client -lc $waitForDoris
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris FE/BE readiness check"

Write-Host "Applying sql/doris/00_init.sql..."
Get-Content "$root/sql/doris/00_init.sql" -Raw | docker @compose run --rm -T mysql-client -hdoris -P9030 -uroot
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris ODS/DIM initialization"

Write-Host "Applying sql/doris/20_realtime_sink.sql..."
Get-Content "$root/sql/doris/20_realtime_sink.sql" -Raw | docker @compose run --rm -T mysql-client -hdoris -P9030 -uroot
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris realtime ADS initialization"

Write-Host "Doris ODS and realtime sink tables are ready."
