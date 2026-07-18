param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 180,

    [ValidateRange(1, 60)]
    [int]$PollIntervalSeconds = 5,

    [ValidateRange(1, 100)]
    [int]$RequiredCompletedCheckpoints = 2,

    [string]$FlinkRestUrl = "http://localhost:8081"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml")
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastStatus = "Flink REST has not responded yet."
$terminalJobStates = @("FINISHED", "CANCELED", "FAILED", "SUSPENDED")
$baseRestUrl = $FlinkRestUrl.TrimEnd("/")
$observedJobId = $null
$failedCheckpointBaseline = $null
$completedCheckpointIdBaseline = $null
$checkpointObservationCount = 0

$paimonBucketPaths = @(
    "/warehouse/paimon/ods.db/ods_trade_order_event/bucket-0",
    "/warehouse/paimon/dwd.db/dwd_trade_order_detail_inc/bucket-0",
    "/warehouse/paimon/dwd.db/dwd_trade_order_refund_inc/bucket-0",
    "/warehouse/paimon/dws.db/dws_trade_day_window/bucket-0",
    "/warehouse/paimon/ads.db/ads_trade_stats_realtime/bucket-0"
)

$expectedJobNameFragments = @(
    "paimon_catalog.ods.ods_trade_order_event",
    "paimon_catalog.dwd.dwd_trade_order_detail_inc",
    "paimon_catalog.dwd.dwd_trade_order_refund_inc",
    "paimon_catalog.dws.dws_trade_day_window",
    "paimon_catalog.ads.ads_trade_stats_realtime",
    "default_catalog.default_database.doris_ads_trade_stats_realtime"
)

function Test-PaimonBuckets {
    param(
        [long]$MinimumDataFileEpochMilliseconds
    )

    $taskManagerProcessIdentities = @(
        docker @compose exec -T taskmanager ps -o "uid=,gid=" -C java
    )
    $processIdentityExitCode = $LASTEXITCODE
    Assert-NativeCommandSucceeded -ExitCode $processIdentityExitCode -Operation "TaskManager Java process identity check"
    $unexpectedProcessIdentities = @(
        $taskManagerProcessIdentities |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch "^9999\s+9999$"
            }
    )
    $nonEmptyProcessIdentities = @(
        $taskManagerProcessIdentities |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($nonEmptyProcessIdentities.Count -eq 0 -or $unexpectedProcessIdentities.Count -gt 0) {
        throw "Expected every TaskManager Java process to run as uid:gid 9999:9999, got: $($nonEmptyProcessIdentities -join ', ')."
    }
    $taskManagerUser = "9999:9999"
    $minimumDataFileEpochSeconds = $MinimumDataFileEpochMilliseconds / 1000.0

    foreach ($bucket in $paimonBucketPaths) {
        $null = @(docker @compose exec -T --user $taskManagerUser taskmanager test -d $bucket)
        $directoryExitCode = $LASTEXITCODE
        if ($directoryExitCode -eq 1) {
            Write-Host "Paimon bucket is not present yet: $bucket"
            return $false
        }
        Assert-NativeCommandSucceeded -ExitCode $directoryExitCode -Operation "Paimon bucket directory check: $bucket"

        $null = @(docker @compose exec -T --user $taskManagerUser taskmanager test -w $bucket)
        $writableExitCode = $LASTEXITCODE
        Assert-NativeCommandSucceeded -ExitCode $writableExitCode -Operation "Paimon bucket writable check: $bucket"

        $marker = "$bucket/.write-check-$([guid]::NewGuid().ToString('N'))"
        $null = @(docker @compose exec -T --user $taskManagerUser taskmanager touch $marker)
        $touchExitCode = $LASTEXITCODE
        Assert-NativeCommandSucceeded -ExitCode $touchExitCode -Operation "Paimon bucket write probe: $bucket"

        $null = @(docker @compose exec -T --user $taskManagerUser taskmanager rm -f $marker)
        $removeExitCode = $LASTEXITCODE
        Assert-NativeCommandSucceeded -ExitCode $removeExitCode -Operation "Paimon bucket write-probe cleanup: $bucket"

        $dataFileOutput = @(
            docker @compose exec -T --user $taskManagerUser taskmanager `
                find $bucket -maxdepth 1 -type f -name "data-*" -size "+0c" -printf "%T@|%p\n"
        )
        $findExitCode = $LASTEXITCODE
        Assert-NativeCommandSucceeded -ExitCode $findExitCode -Operation "Paimon data-file check: $bucket"

        $currentJobDataFiles = @()
        foreach ($line in $dataFileOutput) {
            $text = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) {
                continue
            }
            $parts = $text.Split("|", 2)
            if ($parts.Count -ne 2) {
                throw "Unexpected Paimon data-file metadata from bucket ${bucket}: $text"
            }
            $epochSeconds = 0.0
            $parsed = [double]::TryParse(
                $parts[0],
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$epochSeconds
            )
            if (-not $parsed) {
                throw "Invalid Paimon data-file timestamp from bucket ${bucket}: $text"
            }
            if ($epochSeconds -ge $minimumDataFileEpochSeconds) {
                $currentJobDataFiles += [pscustomobject]@{
                    EpochSeconds = $epochSeconds
                    Path = $parts[1]
                }
            }
        }
        if ($currentJobDataFiles.Count -eq 0) {
            Write-Host "No non-empty Paimon data file created since the current job started was found in bucket: $bucket"
            return $false
        }
        $latestDataFile = $currentJobDataFiles |
            Sort-Object -Property EpochSeconds -Descending |
            Select-Object -First 1
        Write-Host "Paimon bucket ready: $bucket -> $($latestDataFile.Path)"
    }

    return $true
}

while ((Get-Date) -lt $deadline) {
    try {
        $overview = Invoke-RestMethod `
            -Uri "$baseRestUrl/jobs/overview" `
            -Method Get `
            -TimeoutSec 5
    } catch {
        $lastStatus = "Flink jobs overview request failed: $($_.Exception.Message)"
        Write-Host "$lastStatus Retrying..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    $jobs = @($overview.jobs)
    $runningJobs = @($jobs | Where-Object { $_.state -eq "RUNNING" })
    $activeJobs = @($jobs | Where-Object { $_.state -notin $terminalJobStates })

    if ($runningJobs.Count -gt 1 -or $activeJobs.Count -gt 1) {
        $states = @($activeJobs | ForEach-Object { "$($_.jid):$($_.state)" })
        throw "Expected exactly one active RUNNING Flink job, found $($activeJobs.Count) active jobs: $($states -join ', ')"
    }

    if ($runningJobs.Count -ne 1 -or $activeJobs.Count -ne 1) {
        $lastStatus = "Expected one active RUNNING Flink job; running=$($runningJobs.Count), active=$($activeJobs.Count)."
        Write-Host "$lastStatus Retrying..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    $job = $runningJobs[0]
    $jobName = [string]$job.name
    $missingJobNameFragments = @(
        $expectedJobNameFragments |
            Where-Object { -not $jobName.Contains($_) }
    )
    if ($missingJobNameFragments.Count -gt 0) {
        throw "The active Flink job is not the expected six-sink ecommerce job. Missing name fragments: $($missingJobNameFragments -join ', ')"
    }
    $jobStartTime = [long]$job.'start-time'
    if ($jobStartTime -le 0) {
        throw "Flink job $($job.jid) does not expose a valid start-time."
    }
    $totalTasks = [int]$job.tasks.total
    $runningTasks = [int]$job.tasks.running
    $finishedTasks = [int]$job.tasks.finished
    $failedTasks = [int]$job.tasks.failed
    $canceledTasks = [int]$job.tasks.canceled
    $cancelingTasks = [int]$job.tasks.canceling
    if ($totalTasks -ne 9) {
        throw "Expected 9 Flink tasks for job $($job.jid), found $totalTasks."
    }
    if ($failedTasks -ne 0 -or $canceledTasks -ne 0 -or $cancelingTasks -ne 0) {
        throw "Flink job $($job.jid) has an invalid task state: failed=$failedTasks, canceled=$canceledTasks, canceling=$cancelingTasks."
    }
    if (($runningTasks + $finishedTasks) -ne 9) {
        $lastStatus = "job=$($job.jid), state=$($job.state), tasks_running=$runningTasks, tasks_finished=$finishedTasks, tasks_total=$totalTasks"
        Write-Host "$lastStatus; waiting for running + finished tasks to reach 9..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    try {
        $checkpoints = Invoke-RestMethod `
            -Uri "$baseRestUrl/jobs/$($job.jid)/checkpoints" `
            -Method Get `
            -TimeoutSec 5
    } catch {
        $lastStatus = "Checkpoint request for job $($job.jid) failed: $($_.Exception.Message)"
        Write-Host "$lastStatus Retrying..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    $completedCheckpoints = [int]$checkpoints.counts.completed
    $failedCheckpoints = [int]$checkpoints.counts.failed
    $checkpointHistory = @(
        $checkpoints.history |
            Sort-Object -Property id -Descending
    )
    $completedCheckpointIds = @(
        $checkpointHistory |
            Where-Object { $_.status -eq "COMPLETED" } |
            ForEach-Object { [long]$_.id }
    )
    $latestCompletedCheckpointId = if ($completedCheckpointIds.Count -gt 0) {
        [long]$completedCheckpointIds[0]
    } else {
        [long]-1
    }

    if ($observedJobId -ne $job.jid) {
        $observedJobId = $job.jid
        $failedCheckpointBaseline = $failedCheckpoints
        $completedCheckpointIdBaseline = $latestCompletedCheckpointId
        $checkpointObservationCount = 1
    } else {
        if ($failedCheckpoints -gt $failedCheckpointBaseline) {
            throw "Flink job $($job.jid) added failed checkpoints during verification: baseline=$failedCheckpointBaseline, current=$failedCheckpoints."
        }
        $checkpointObservationCount++
    }

    $recentCheckpoints = @(
        $checkpointHistory |
            Select-Object -First $RequiredCompletedCheckpoints
    )
    $recentCheckpointStatuses = @($recentCheckpoints | ForEach-Object { [string]$_.status })
    $recentCheckpointsCompleted = (
        $recentCheckpoints.Count -eq $RequiredCompletedCheckpoints -and
        @($recentCheckpointStatuses | Where-Object { $_ -ne "COMPLETED" }).Count -eq 0
    )

    $latestFailedCheckpoint = $null
    $latestProperty = $checkpoints.PSObject.Properties["latest"]
    if ($null -ne $latestProperty -and $null -ne $latestProperty.Value) {
        $latestFailedProperty = $latestProperty.Value.PSObject.Properties["failed"]
        if ($null -ne $latestFailedProperty) {
            $latestFailedCheckpoint = $latestFailedProperty.Value
        }
    }
    if ($null -ne $latestFailedCheckpoint) {
        throw "Flink job $($job.jid) reports a latest failed checkpoint; expected latest.failed to be empty."
    }

    try {
        $exceptions = Invoke-RestMethod `
            -Uri "$baseRestUrl/jobs/$($job.jid)/exceptions?maxExceptions=1" `
            -Method Get `
            -TimeoutSec 5
    } catch {
        $lastStatus = "Exception-history request for job $($job.jid) failed: $($_.Exception.Message)"
        Write-Host "$lastStatus Retrying..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    $rootException = $null
    $rootExceptionProperty = $exceptions.PSObject.Properties["root-exception"]
    if ($null -ne $rootExceptionProperty) {
        $rootException = [string]$rootExceptionProperty.Value
    }
    if (-not [string]::IsNullOrWhiteSpace($rootException)) {
        throw "Flink job $($job.jid) reports a root execution exception: $rootException"
    }
    $allExceptions = @()
    $allExceptionsProperty = $exceptions.PSObject.Properties["all-exceptions"]
    if ($null -ne $allExceptionsProperty -and $null -ne $allExceptionsProperty.Value) {
        $allExceptions = @($allExceptionsProperty.Value)
    }
    $exceptionHistoryEntries = @()
    $exceptionHistoryProperty = $exceptions.PSObject.Properties["exceptionHistory"]
    if ($null -ne $exceptionHistoryProperty -and $null -ne $exceptionHistoryProperty.Value) {
        $entriesProperty = $exceptionHistoryProperty.Value.PSObject.Properties["entries"]
        if ($null -ne $entriesProperty -and $null -ne $entriesProperty.Value) {
            $exceptionHistoryEntries = @($entriesProperty.Value)
        }
    }
    if ($allExceptions.Count -gt 0 -or $exceptionHistoryEntries.Count -gt 0) {
        throw "Flink job $($job.jid) reports execution exception history: all-exceptions=$($allExceptions.Count), exceptionHistory.entries=$($exceptionHistoryEntries.Count)."
    }

    $recentStatusText = if ($recentCheckpointStatuses.Count -gt 0) {
        $recentCheckpointStatuses -join ","
    } else {
        "none"
    }
    $hasNewCompletedCheckpoint = (
        $null -ne $completedCheckpointIdBaseline -and
        $latestCompletedCheckpointId -gt $completedCheckpointIdBaseline
    )
    $lastStatus = "job=$($job.jid), state=$($job.state), tasks_running=$runningTasks, tasks_finished=$finishedTasks, tasks_total=$totalTasks, completed_checkpoints=$completedCheckpoints, recent_checkpoint_statuses=$recentStatusText, completed_checkpoint_id_baseline=$completedCheckpointIdBaseline, latest_completed_checkpoint_id=$latestCompletedCheckpointId, failed_checkpoint_baseline=$failedCheckpointBaseline, failed_checkpoint_current=$failedCheckpoints"
    if (
        $completedCheckpoints -lt $RequiredCompletedCheckpoints -or
        -not $recentCheckpointsCompleted -or
        $checkpointObservationCount -lt 2 -or
        -not $hasNewCompletedCheckpoint
    ) {
        Write-Host "$lastStatus; waiting for $RequiredCompletedCheckpoints consecutive completed checkpoints plus a new completed checkpoint after the failure-count baseline..."
        Start-Sleep -Seconds $PollIntervalSeconds
        continue
    }

    if (Test-PaimonBuckets -MinimumDataFileEpochMilliseconds $jobStartTime) {
        Write-Host "Flink/Paimon verification passed: $lastStatus; the expected six-sink job has no execution exception or new checkpoint failure, every TaskManager Java process runs as 9999:9999, and all 5 Paimon buckets are writable and contain non-empty data files created since this job started."
        return
    }

    $lastStatus = "$lastStatus; one or more Paimon buckets are not populated yet"
    Write-Host "$lastStatus; retrying..."
    Start-Sleep -Seconds $PollIntervalSeconds
}

throw "Flink/Paimon verification timed out after $TimeoutSeconds seconds. Last status: $lastStatus"
