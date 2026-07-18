Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml", "--profile", "tools")
$sql = Get-Content "$root/sql/doris/90_compare.sql" -Raw

$rows = @(
    $sql |
        docker @compose run --rm -T mysql-client -hdoris -P9030 -uroot --batch --raw --skip-column-names
)
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris reconciliation query"
if ($rows.Count -eq 0) {
    throw "Reconciliation returned no rows."
}

$columnNames = @(
    "dt",
    "recent_days",
    "offline_gmv",
    "realtime_gmv",
    "offline_order_count",
    "realtime_order_count",
    "offline_user_count",
    "realtime_user_count",
    "offline_refund_count",
    "realtime_refund_count",
    "offline_refund_user_count",
    "realtime_refund_user_count",
    "offline_avg_order_amount",
    "realtime_avg_order_amount",
    "compare_status"
)

$results = @(
    foreach ($row in $rows) {
        $values = @($row -split "`t", -1)
        if ($values.Count -ne $columnNames.Count) {
            throw "Unexpected reconciliation row with $($values.Count) columns: $row"
        }

        $record = [ordered]@{}
        for ($index = 0; $index -lt $columnNames.Count; $index++) {
            $record[$columnNames[$index]] = $values[$index]
        }
        [PSCustomObject]$record
    }
)

foreach ($result in $results) {
    Write-Host (
        "{0} recent_days={1} gmv={2}/{3} orders={4}/{5} users={6}/{7} refunds={8}/{9} refund_users={10}/{11} avg_order={12}/{13} status={14}" -f
        $result.dt,
        $result.recent_days,
        $result.offline_gmv,
        $result.realtime_gmv,
        $result.offline_order_count,
        $result.realtime_order_count,
        $result.offline_user_count,
        $result.realtime_user_count,
        $result.offline_refund_count,
        $result.realtime_refund_count,
        $result.offline_refund_user_count,
        $result.realtime_refund_user_count,
        $result.offline_avg_order_amount,
        $result.realtime_avg_order_amount,
        $result.compare_status
    )
}

$badRows = @($results | Where-Object { $_.compare_status -ne "PASS" })
if ($badRows.Count -gt 0) {
    $summary = $badRows |
        ForEach-Object { "recent_days=$($_.recent_days), status=$($_.compare_status)" }
    throw "Reconciliation failed: $($summary -join '; ')"
}

Write-Host "Reconciliation passed for all rows."
