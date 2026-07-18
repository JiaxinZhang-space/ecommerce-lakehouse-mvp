Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

$requiredFiles = @(
    ".gitignore",
    ".gitattributes",
    "CONTRIBUTIONS.md",
    "LICENSE",
    "NOTICE.md",
    "README.md",
    "docker-compose.yml",
    "data/trade_order_events.jsonl",
    "docker/flink/Dockerfile",
    "scripts/native-command.ps1",
    "sql/mysql/00_business.sql",
    "sql/doris/00_init.sql",
    "sql/doris/10_offline_trade_warehouse.sql",
    "sql/doris/20_realtime_sink.sql",
    "sql/doris/90_compare.sql",
    "sql/flink/01_paimon_realtime.sql",
    "scripts/verify-flink-paimon.ps1"
)

$missing = @(
    $requiredFiles |
        Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) }
)
if ($missing.Count -gt 0) {
    throw "Missing required files: $($missing -join ', ')"
}

$forbiddenNames = @("target", ".tmp", ".env")
$forbidden = @(
    Get-ChildItem -LiteralPath $root -Recurse -Force |
        Where-Object { $_.Name -in $forbiddenNames }
)
if ($forbidden.Count -gt 0) {
    throw "Forbidden runtime artifacts found: $($forbidden.FullName -join ', ')"
}

$legacyReferences = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -Include *.md,*.ps1 |
        Where-Object { $_.FullName -ne $PSCommandPath } |
        Select-String -SimpleMatch "portfolio-mvp"
)
if ($legacyReferences.Count -gt 0) {
    throw "Legacy nested-directory references found: $($legacyReferences.Path -join ', ')"
}

$eventPath = Join-Path $root "data/trade_order_events.jsonl"
$eventLines = @(Get-Content -LiteralPath $eventPath -Encoding UTF8)
$blankLines = @($eventLines | Where-Object { -not $_.Trim() })
if ($blankLines.Count -gt 0) {
    throw "Fixture must not contain blank lines."
}

$events = @($eventLines | ForEach-Object { $_ | ConvertFrom-Json })
if ($events.Count -ne 10) {
    throw "Expected 10 deterministic events, found $($events.Count)."
}

$requiredEventFields = @(
    "event_id",
    "order_id",
    "user_id",
    "sku_id",
    "event_time",
    "dt",
    "sku_num",
    "split_original_amount",
    "split_activity_amount",
    "split_coupon_amount",
    "split_total_amount",
    "is_refund"
)
foreach ($event in $events) {
    $missingFields = @(
        $requiredEventFields |
            Where-Object { $_ -notin $event.PSObject.Properties.Name }
    )
    if ($missingFields.Count -gt 0) {
        throw "event_id=$($event.event_id) is missing fields: $($missingFields -join ', ')"
    }

    $expectedTotal = [decimal]$event.split_original_amount -
        [decimal]$event.split_activity_amount -
        [decimal]$event.split_coupon_amount
    if ([decimal]$event.split_total_amount -ne $expectedTotal) {
        throw "event_id=$($event.event_id) has an invalid split_total_amount."
    }
    if ([int]$event.is_refund -notin @(0, 1)) {
        throw "event_id=$($event.event_id) has an invalid is_refund value."
    }
}

$eventIds = @($events | ForEach-Object { [string]$_.event_id })
if (($eventIds | Sort-Object -Unique).Count -ne $events.Count) {
    throw "event_id must be unique."
}

$anchorDate = [datetime]::ParseExact(
    "2026-07-01",
    "yyyy-MM-dd",
    [Globalization.CultureInfo]::InvariantCulture
)
$expectedMetrics = @(
    [pscustomobject]@{
        recent_days = 1
        order_total_amount = [decimal]505.50
        order_count = 5
        order_user_count = 4
        order_refund_count = 2
        order_refund_user_count = 2
        avg_order_amount = [decimal]101.10
    },
    [pscustomobject]@{
        recent_days = 7
        order_total_amount = [decimal]1078.50
        order_count = 9
        order_user_count = 6
        order_refund_count = 3
        order_refund_user_count = 3
        avg_order_amount = [decimal]119.83
    },
    [pscustomobject]@{
        recent_days = 30
        order_total_amount = [decimal]1578.50
        order_count = 10
        order_user_count = 7
        order_refund_count = 4
        order_refund_user_count = 4
        avg_order_amount = [decimal]157.85
    }
)

foreach ($expected in $expectedMetrics) {
    $rangeStart = $anchorDate.AddDays(-([int]$expected.recent_days - 1))
    $scopedEvents = @(
        $events | Where-Object {
            $eventDate = [datetime]::ParseExact(
                [string]$_.dt,
                "yyyy-MM-dd",
                [Globalization.CultureInfo]::InvariantCulture
            )
            $eventDate -ge $rangeStart -and $eventDate -le $anchorDate
        }
    )
    $refundEvents = @($scopedEvents | Where-Object { [int]$_.is_refund -eq 1 })
    $orderCount = @($scopedEvents.order_id | Sort-Object -Unique).Count
    $gmv = [decimal](($scopedEvents | Measure-Object -Property split_total_amount -Sum).Sum)
    $actual = [pscustomobject]@{
        recent_days = [int]$expected.recent_days
        order_total_amount = $gmv
        order_count = $orderCount
        order_user_count = @($scopedEvents.user_id | Sort-Object -Unique).Count
        order_refund_count = @($refundEvents.order_id | Sort-Object -Unique).Count
        order_refund_user_count = @($refundEvents.user_id | Sort-Object -Unique).Count
        avg_order_amount = [math]::Round($gmv / $orderCount, 2)
    }

    foreach ($field in @(
        "order_total_amount",
        "order_count",
        "order_user_count",
        "order_refund_count",
        "order_refund_user_count",
        "avg_order_amount"
    )) {
        if ($actual.$field -ne $expected.$field) {
            throw "Metric fixture mismatch for recent_days=$($expected.recent_days), field=${field}: expected $($expected.$field), got $($actual.$field)."
        }
    }
}

Write-Host "Repository validation passed: structure, clean tree, 10 valid events, and expected 1/7/30-day metrics."
