Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "native-command.ps1")

Write-Host "Checking Docker CLI..."
docker version --format "{{.Client.Version}}" | Out-Host
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker CLI check"

Write-Host "Checking Docker Compose..."
docker compose version | Out-Host
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker Compose check"

Write-Host "Checking Docker Engine..."
docker info --format "{{.ServerVersion}}" | Out-Host
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Docker Engine check"

Write-Host "Checking vm.max_map_count for Doris BE..."
try {
    $vmMaxMapCount = docker run --rm --entrypoint bash apache/doris:2.1.9-all -lc "sysctl -n vm.max_map_count"
    Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "vm.max_map_count check"
    $vmMaxMapCountNumber = [int]$vmMaxMapCount.Trim()
    if ($vmMaxMapCountNumber -lt 2000000) {
        Write-Warning "vm.max_map_count is $vmMaxMapCountNumber, below Doris's strict installation recommendation of 2000000."
        Write-Warning "This local demo uses SKIP_CHECK_ULIMIT=true; production or strict validation should set it with: wsl -d docker-desktop -u root sysctl -w vm.max_map_count=2000000"
    } else {
        Write-Host "vm.max_map_count is $vmMaxMapCountNumber."
    }
} catch {
    Write-Warning "Could not check vm.max_map_count automatically: $($_.Exception.Message)"
}

Write-Host "Checking required ports..."
$ports = @(3307, 8030, 8040, 9030, 8081, 9094)
foreach ($port in $ports) {
    $used = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($used) {
        Write-Warning "Port $port is already in use. Stop the conflicting process or change docker-compose.yml."
    } else {
        Write-Host "Port $port is free."
    }
}
