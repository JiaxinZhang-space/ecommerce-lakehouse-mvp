Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml")

& (Join-Path $root "scripts/validate-repo.ps1")

Write-Host "Waiting for Kafka broker..."
docker @compose exec -T kafka bash -lc "until /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --list >/dev/null 2>&1; do sleep 3; done"
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Kafka readiness check"
docker @compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --delete --if-exists --topic trade_order_events
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Kafka demo topic reset"
Start-Sleep -Seconds 3
docker @compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --create --if-not-exists --topic trade_order_events --partitions 1 --replication-factor 1
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Kafka demo topic creation"
Get-Content "$root/data/trade_order_events.jsonl" | docker @compose exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:9092 --topic trade_order_events
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Kafka deterministic event production"

Write-Host "Reset and produced deterministic trade events to Kafka topic trade_order_events."
