param(
    [switch]$Reset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scripts = Join-Path $root "scripts"

if ($Reset) {
    & (Join-Path $scripts "reset.ps1")
}

& (Join-Path $scripts "check-env.ps1")
& (Join-Path $scripts "start.ps1")
& (Join-Path $scripts "init-mysql.ps1")
& (Join-Path $scripts "init-doris.ps1")
& (Join-Path $scripts "sync-mysql-to-doris.ps1")
& (Join-Path $scripts "run-offline-doris.ps1")
& (Join-Path $scripts "produce-kafka-events.ps1")
& (Join-Path $scripts "start-realtime-paimon.ps1")

$maxAttempts = 60
$passedAttempt = 0
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        & (Join-Path $scripts "compare.ps1")
        $passedAttempt = $attempt
        break
    } catch {
        if ($attempt -eq $maxAttempts) {
            throw
        }
        Write-Host "Realtime ADS is not ready yet ($attempt/$maxAttempts); retrying in 5 seconds..."
        Start-Sleep -Seconds 5
    }
}

& (Join-Path $scripts "verify-flink-paimon.ps1")
Write-Host "End-to-end demo passed on reconciliation attempt $passedAttempt, including Flink checkpoint and Paimon storage verification."
