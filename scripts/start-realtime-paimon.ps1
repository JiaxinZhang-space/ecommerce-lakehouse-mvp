Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml")

$bucketInitializationCommand = "set -euo pipefail; mkdir -p /warehouse/paimon/ods.db/ods_trade_order_event/bucket-0 /warehouse/paimon/dwd.db/dwd_trade_order_detail_inc/bucket-0 /warehouse/paimon/dwd.db/dwd_trade_order_refund_inc/bucket-0 /warehouse/paimon/dws.db/dws_trade_day_window/bucket-0 /warehouse/paimon/ads.db/ads_trade_stats_realtime/bucket-0; chown -R 9999:9999 /warehouse/paimon"
docker @compose exec -T --user root jobmanager bash -lc $bucketInitializationCommand
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Paimon local bucket directory initialization"
docker @compose exec -T --user "9999:9999" jobmanager /opt/flink/bin/sql-client.sh -f /opt/flink/usrlib/sql/flink/01_paimon_realtime.sql
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Flink SQL submission"
Write-Host "Flink/Paimon realtime SQL submitted. Check http://localhost:8081 for the running job."
